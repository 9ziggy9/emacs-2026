;;; ui.el --- looks, windows, file and buffer browsing, popups -*- lexical-binding: t -*-

(require 'popup (locate-user-emacs-file "popup"))

;; Line numbers
(setq display-line-numbers-type 'relative)
(add-hook 'prog-mode-hook #'display-line-numbers-mode)

;; Echo area text at 60% of the buffer text size
(dolist (buf '(" *Echo Area 0*" " *Echo Area 1*"))
  (with-current-buffer (get-buffer-create buf)
    (face-remap-add-relative 'default :height 0.6)))

;; Long messages show only their first line, rather than growing the echo area
(setq message-truncate-lines t)

;;; Theme
(use-package railscasts-reloaded-theme :defer t)

;; Selections (visual mode) are shaded darker than the background, not
;; lighter; redone after each theme, since themes set the region face
(defun my/darken-region (&rest _)
  (require 'color)
  (let ((bg (face-background 'default nil t)))
    (when (color-defined-p bg)
      (set-face-background 'region (color-darken-name bg 7)))))

(my/darken-region)
(add-hook 'enable-theme-functions #'my/darken-region)

(use-package base16-theme :defer t)     ; ~360 schemes: base16-<name>
(use-package ef-themes :defer t)        ; ~34 polished light/dark themes
(use-package doom-themes :defer t)      ; ~60 themes: doom-<name>

;; The theme picked with consult-theme is remembered across restarts;
;; Railscasts until one is picked (or if the saved one is gone)
(defvar my/theme-file (locate-user-emacs-file "theme")
  "File holding the name of the last theme picked.")

(defun my/save-theme (theme)
  "Remember THEME for the next start."
  (when theme
    (with-temp-file my/theme-file
      (prin1 theme (current-buffer)))))

(defun my/saved-theme ()
  (ignore-errors
    (with-temp-buffer
      (insert-file-contents my/theme-file)
      (read (current-buffer)))))

(unless (ignore-errors (load-theme (my/saved-theme) t))
  (load-theme 'railscasts-reloaded t))

;; consult-theme lists color themes only, and the pick is remembered:
;; newcomers-presets changes settings (turns on the tab bar), light-blue
;; is obsolete, and base16 is just the base16 package's helper file
(with-eval-after-load 'consult
  (setq consult-themes
        (seq-difference (custom-available-themes)
                        '(newcomers-presets light-blue base16)))
  (advice-add 'consult-theme :after #'my/save-theme))

;;; Windows
(use-package window
  :ensure nil
  :custom
  (window-combination-resize t))

;;; Key hints: pause after a prefix to see what can follow it
(use-package which-key
  :ensure nil                          ; built in since Emacs 30
  :init (which-key-mode 1))

;;; Richer help buffers (source, references, keybindings)
(use-package helpful
  :bind
  (([remap describe-function] . helpful-callable)
   ([remap describe-variable] . helpful-variable)
   ([remap describe-command]  . helpful-command)
   ([remap describe-key]      . helpful-key)
   ([remap describe-symbol]   . helpful-symbol)))

;;; Command log: a live side buffer of every key and the command it ran
(use-package command-log-mode
  :commands clm/toggle-command-log-buffer
  :custom
  (command-log-mode-key-binding-open-log nil)   ; don't grab C-c o
  (command-log-mode-open-log-turns-on-mode t)   ; opening the log starts logging
  (command-log-mode-is-global t))               ; ...in every buffer

;;; File tree: C-t (see universal.el)
(use-package treemacs
  :defer t
  :hook
  (treemacs-mode . (lambda ()        ; text at 75%
                     (face-remap-add-relative 'default :height 0.75)))
  (treemacs-mode . my/treemacs-preview-setup)
  :custom
  (treemacs-no-png-images t)         ; no icons, just +/- on directories
  (treemacs-width 22)                ; columns (default 35)
  :config
  (add-hook 'window-selection-change-functions #'my/treemacs-keep-preview)
  (treemacs-follow-mode 1)           ; highlight the file you're in
  (treemacs-project-follow-mode 1))  ; switch projects as you do

;; Preview: resting on a file in treemacs shows it in the window you came
;; from.  A file opened only to preview is closed as soon as the preview
;; moves on, so at most one exists; leaving treemacs keeps whatever is
;; showing.  (treemacs-peek-mode only cleans up on some ways of leaving.)
(declare-function treemacs-current-button "treemacs-core-utils")
(declare-function treemacs-button-get "treemacs-core-utils")

(defvar my/treemacs-preview-buffer nil
  "Buffer opened only for previewing, or nil.")

(defvar my/treemacs-preview-timer nil)

(defun my/treemacs-preview (treemacs-buf)
  "Show the file at point in TREEMACS-BUF in the most recent other window."
  (when (eq (window-buffer (selected-window)) treemacs-buf)
    (with-current-buffer treemacs-buf
      (let* ((button (treemacs-current-button))
             (path (and button (treemacs-button-get button :path)))
             (win (get-mru-window nil nil t)))
        (when (and (stringp path) (file-regular-p path) (window-live-p win))
          (let* ((existing (get-file-buffer path))
                 (buf (or existing
                          (let ((inhibit-message t))
                            (find-file-noselect path))))
                 (old my/treemacs-preview-buffer))
            (set-window-buffer win buf)
            (setq my/treemacs-preview-buffer (unless existing buf))
            (when (and (buffer-live-p old) (not (eq old buf))
                       (not (get-buffer-window old t)))
              (kill-buffer old))))))))

(defun my/treemacs-preview-soon ()
  "Preview once the cursor rests, so scrolling past files doesn't open them."
  (when (timerp my/treemacs-preview-timer)
    (cancel-timer my/treemacs-preview-timer))
  (setq my/treemacs-preview-timer
        (run-with-idle-timer 0.15 nil #'my/treemacs-preview (current-buffer))))

(defun my/treemacs-preview-setup ()
  (add-hook 'post-command-hook #'my/treemacs-preview-soon nil t))

(defun my/treemacs-keep-preview (&rest _)
  "Leaving treemacs, by any route, keeps the previewed file open."
  (unless (with-current-buffer (window-buffer (selected-window))
            (derived-mode-p 'treemacs-mode))
    (setq my/treemacs-preview-buffer nil)))

(use-package treemacs-evil           ; j/k and friends inside treemacs
  :after (treemacs evil))

;;; Dired
(use-package dired
  :ensure nil
  :custom
  (dired-kill-when-opening-new-dired-buffer t)
  :init
  ;; After evil-collection's own dired keys, so these win
  (add-hook 'evil-collection-setup-hook
            (lambda (mode _keymaps)
              (when (eq mode 'dired)
                (evil-define-key 'normal dired-mode-map
                  "=" #'dired-create-empty-file   ; the +/= key on its own
                  "+" #'dired-create-directory))))) ; with Shift

(declare-function dired-get-file-for-visit "dired")
(declare-function dired-find-file "dired")
(declare-function dired-goto-file "dired")
(declare-function dired-noselect "dired")

(defun pop/dired-here ()
  "A dired buffer at the main buffer's directory, on the file you came from."
  (let* ((main (pop/main-buffer))
         (file (buffer-file-name main))
         (buf (dired-noselect (buffer-local-value 'default-directory main))))
    (when file
      (with-current-buffer buf (dired-goto-file file)))
    buf))

(defun pop/dired-find-file ()
  "Enter directories in place; open files in the main frame."
  (interactive)
  (let ((file (dired-get-file-for-visit)))
    (if (file-directory-p file)
        (dired-find-file)
      (pop/hide)
      (find-file file))))

(defun pop/dired-open-in-split ()
  "Hide the popup and open the file at point in a new split in the main frame."
  (interactive)
  (let ((file (dired-get-file-for-visit)))
    (pop/hide)
    (select-window (split-window-right))
    (find-file file)))

(pop/define dired
  :match   (derived-mode-p 'dired-mode)
  :open    #'pop/dired-here
  :size    (0.8 . 0.8)
  :setup   (pop/text-scale 0.8)
  :keys    ("RET"        pop/dired-find-file
            "C-<return>" pop/dired-open-in-split
            "q"          pop/hide)
  :hints   ("C-RET" "split"  "-" "up"  "m/u" "mark"
            "d/x" "delete"  "R" "rename"  "C" "copy"  "=" "file"  "+" "dir"
            "?" "keys")
  :help    (("Move"
             "RET" "open file / enter dir"
             "C-RET" "open in a split"
             "-" "up a directory"
             "j/k" "next / previous line"
             "> / <" "next / previous dir"
             "gg/G" "top / bottom"
             "/" "search")
            ("Mark"
             "m" "mark"
             "u" "unmark"
             "U" "unmark all"
             "t" "toggle marks"
             "* /" "mark directories"
             "% m" "mark by regexp")
            ("Act on marked (or at point)"
             "C" "copy"
             "R" "rename / move"
             "D" "delete now"
             "d" "flag for deletion"
             "x" "delete flagged"
             "S" "symlink"
             "M" "chmod"
             "Z" "compress / uncompress"
             "c" "compress to archive"
             "!" "shell command"
             "&" "async shell command")
            ("Create"
             "=" "new file"
             "+" "new directory")
            ("View & edit"
             "(" "show / hide details"
             "o" "toggle sort: name / date"
             "g r" "refresh"
             "I" "insert subdir below"
             "Y" "copy file name"
             "i" "edit names in place"
             "C-c C-c" "...save edits"
             "C-c C-k" "...discard edits")
            ("Search marked files"
             "A" "find regexp"
             "Q" "find and replace")
            ("Popup"
             "?" "this sheet"
             "esc/q" "close"
             "C-x" "close and kill buffer")))

;;; Ibuffer
(use-package ibuffer
  :ensure nil
  :custom
  (ibuffer-expert t)
  (ibuffer-show-empty-filter-groups nil))

(use-package ibuffer-project            ; group buffers by project
  :hook
  (ibuffer . (lambda ()
               (setq ibuffer-filter-groups (ibuffer-project-generate-filter-groups)))))

(declare-function ibuffer "ibuffer")
(declare-function ibuffer-update "ibuffer")
(declare-function ibuffer-current-buffer "ibuffer")
(declare-function ibuffer-jump-to-buffer "ibuffer")

(defun pop/ibuffer-here ()
  "A fresh ibuffer list, with the cursor on the buffer you came from."
  (let ((main (pop/main-buffer)))
    (save-window-excursion (ibuffer nil "*Ibuffer*" nil t))
    (with-current-buffer "*Ibuffer*"
      (ibuffer-update nil t)
      (ignore-errors (ibuffer-jump-to-buffer (buffer-name main)))
      (current-buffer))))

(defun pop/ibuffer-visit ()
  "Hide the popup and show the buffer at point in the main window."
  (interactive)
  (let ((buf (ibuffer-current-buffer t)))
    (pop/hide)
    (switch-to-buffer buf)))

(defun pop/ibuffer-visit-in-split ()
  "Hide the popup and show the buffer at point in a new split."
  (interactive)
  (let ((buf (ibuffer-current-buffer t)))
    (pop/hide)
    (select-window (split-window-right))
    (switch-to-buffer buf)))

(pop/define ibuffer
  :match   (derived-mode-p 'ibuffer-mode)
  :open    #'pop/ibuffer-here
  :setup   (pop/text-scale 0.8)
  :keys    ("RET"        pop/ibuffer-visit
            "C-<return>" pop/ibuffer-visit-in-split
            "q"          pop/hide)
  :hints   ("C-RET" "split"  "m/u" "mark"  "d/x" "kill"
            "S" "save"  "TAB" "next group"
            "?" "keys")
  :help    (("Visit"
             "RET" "show buffer"
             "C-RET" "show in a split"
             "TAB/S-TAB" "next / previous group"
             "M-j" "jump to group"
             "g r" "refresh")
            ("Mark"
             "m" "mark"
             "u" "unmark"
             "U" "unmark all"
             "t" "toggle marks"
             "* m" "mark modified"
             "* u" "mark unsaved"
             "." "mark old buffers")
            ("Act on marked"
             "d" "flag to kill"
             "x" "kill flagged"
             "D" "kill now"
             "S" "save"
             "V" "revert from disk"
             "T" "toggle read-only"
             "O" "occur (search lines)"
             "Q" "query replace"
             "=" "diff with file")
            ("Filter"
             "s n" "by name"
             "s m" "by mode"
             "s f" "by file name"
             "s c" "by content"
             "s p" "remove last filter"
             "s /" "remove all filters")
            ("Sort"
             "," "cycle sort order"
             "o v" "by recency"
             "o a" "alphabetically"
             "o s" "by size"
             "o m" "by mode"
             "o i" "reverse")
            ("Popup"
             "?" "this sheet"
             "esc/q" "close"
             "C-x" "close and kill buffer")))

;;; Scratchpad

;; The *scratch* buffer, for notes and trying out elisp; escape leaves
;; insert state first, then closes

(pop/define scratch
  :match (equal (buffer-name) "*scratch*")
  :open  #'get-scratch-buffer-create)

;;; README

;; README.org at the root of the git repo you're in (wherever .git is),
;; created on first save if there isn't one

(defun pop/readme-here ()
  "The README.org buffer for the main buffer's git repo."
  (let* ((dir (buffer-local-value 'default-directory (pop/main-buffer)))
         (root (or (locate-dominating-file dir ".git")
                   (user-error "Not in a git repo: no .git above %s"
                               (abbreviate-file-name dir)))))
    (find-file-noselect (expand-file-name "README.org" root))))

(pop/define readme
  :match (and buffer-file-name
              (equal (file-name-nondirectory buffer-file-name) "README.org"))
  :open  #'pop/readme-here)

;;; Window keys

;; A cheat sheet of the universal keys (universal.el), laid out like ?
;; in other popups; update it when those change

(defvar pop/wm-help
  '(("Move between windows"
     "C-h/j/k/l" "left / down / up / right")
    ("Swap windows"
     "C-S-h/j/k/l" "swap left / down / up / right")
    ("Layout"
     "C-RET" "split right, with dired"
     "C-x" "close window"
     "C-f" "fullscreen on / off"
     "C-]" "side by side <-> stacked")
    ("Resize"
     "C-<left>/<right>" "narrower / wider"
     "C-<up>/<down>" "taller / shorter")
    ("Buffers"
     "C-, / C-." "previous / next file buffer"
     "C-t" "file tree")
    ("Zoom"
     "C-=" "bigger"
     "C--" "smaller"
     "C-0" "reset")
    ("Search"
     "M-s M-f" "find a file"
     "M-s M-d" "this document"
     "M-s M-i" "definitions here"
     "M-s M-I" "project symbols"
     "M-s M-p" "text in the project")
    ("Popups"
     "F1-F6" "mode line slots, on / off"
     "esc" "close"
     "C-x" "close and kill buffer"))
  "Sections (HEADING KEY TEXT ...) for the window keys popup.")

(define-derived-mode pop/wm-mode special-mode "Window keys"
  "The window keys cheat sheet."
  (setq-local cursor-type nil
              truncate-lines t))

(defun pop/wm-buffer ()
  (with-current-buffer (get-buffer-create "*window keys*")
    (unless (derived-mode-p 'pop/wm-mode)
      (pop/wm-mode))
    (current-buffer)))

(defun pop/wm-render ()
  "Lay out the sheet to fit the popup's current width."
  (let ((inhibit-read-only t))
    (erase-buffer)
    (pop/insert-keys "Window keys" pop/wm-help
                     (window-body-width (frame-root-window pop/frame)))
    (goto-char (point-min))))

(pop/define wm
  :match (derived-mode-p 'pop/wm-mode)
  :open  #'pop/wm-buffer
  :setup (pop/wm-render)
  :keys  ("q" pop/hide)
  :hints ("esc/q" "close"))

(provide 'ui)
