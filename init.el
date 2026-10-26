;;; init.el --- -*- lexical-binding: t -*-

;; UI cleanup, no-litter settings, custom-file
(load (locate-user-emacs-file "clean") nil t)

;; Packages are initialized automatically before init.el
(setq use-package-always-ensure t)

;; Revert buffers when files change on disk (e.g. git branch switch)
(global-auto-revert-mode 1)

;; Indentation
(setq-default indent-tabs-mode nil
              tab-width 2
              c-basic-offset 2
              standard-indent 2)

;; Fill column: in code, the part of a line past it is drawn in red
(setq-default fill-column 80)

(use-package whitespace
  :ensure nil
  :hook (prog-mode . whitespace-mode)
  :custom
  (whitespace-style '(face lines-tail))
  (whitespace-line-column nil)          ; nil means use `fill-column'
  :custom-face
  (whitespace-line ((t (:foreground "#ff5f5f" :background unspecified
                        :weight unspecified)))))

;; Line numbers
(setq display-line-numbers-type 'relative)
(add-hook 'prog-mode-hook #'display-line-numbers-mode)

;; Echo area text at 60% of the buffer text size
(dolist (buf '(" *Echo Area 0*" " *Echo Area 1*"))
  (with-current-buffer (get-buffer-create buf)
    (face-remap-add-relative 'default :height 0.6)))

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

;;; Evil
(use-package evil
  :init
  ;; These must be set before evil loads
  (setq evil-want-keybinding nil      ; leave other modes' maps alone
        evil-want-C-u-scroll t        ; C-u scrolls up, like vim
        evil-want-Y-yank-to-eol t     ; Y behaves like y$
        evil-undo-system 'undo-redo   ; built-in redo for C-r
        evil-split-window-below t     ; :sp opens below
        evil-vsplit-window-right t    ; :vs opens right
        evil-echo-state nil)          ; no -- INSERT -- in the echo area
  :config
  (evil-mode 1)
  (evil-define-key 'visual 'global
    "-"   #'evil-join
    "C"   #'comment-or-uncomment-region
    (kbd "SPC") #'my/cursors-at-line-starts
    "J"   #'my/move-lines-down
    "K"   #'my/move-lines-up
    "f"   #'my/fold-selection
    "F"   #'my/unfold-selection)
  (evil-define-key 'normal 'global
    "-" #'evil-join
    "C" #'comment-line
    "L" #'evil-multiedit-match-and-next
    "F" #'vimish-fold-delete
    ;; Tab toggles the fold under the cursor, in code only, so Tab keeps
    ;; its own job elsewhere (org, popups...)
    (kbd "<tab>") `(menu-item "" vimish-fold-toggle
                              :filter ,(lambda (cmd)
                                         (when (derived-mode-p 'prog-mode)
                                           cmd)))))

(use-package evil-multiedit            ; L: edit every match of the word at once
  :after evil
  :commands evil-multiedit-match-and-next)

;; Multiple cursors: SPC on a visual selection puts a cursor at the start
;; of each line; entering visual mode again collapses back to one
(use-package evil-mc
  :after evil
  :init
  (setq evil-mc-key-map (make-sparse-keymap)) ; none of its default keys
  :config
  (global-evil-mc-mode 1)
  (add-hook 'evil-visual-state-entry-hook
            (lambda ()
              (unless (evil-mc-executing-command-p)
                (evil-mc-undo-all-cursors)))))

(declare-function evil-mc-make-cursor-in-visual-selection "evil-mc-cursor-make")

(evil-define-command my/cursors-at-line-starts ()
  "Put a cursor at the start of every selected line, in normal state."
  :repeat ignore
  :evil-mc t
  (when (evil-visual-state-p)
    (evil-mc-make-cursor-in-visual-selection t)
    (evil-normal-state)))

;; Moving the selected lines with J/K: the whole lines the selection
;; touches move past their neighbour, and the selection moves with them
(defun my/move-lines (n)
  "Move the lines of the visual selection N lines down (up if negative)."
  (let* ((beg (save-excursion (goto-char evil-visual-beginning)
                              (line-beginning-position)))
         (end (save-excursion (goto-char (max beg (1- evil-visual-end)))
                              (line-beginning-position 2)))
         (mark-off (- evil-visual-mark beg))
         (point-off (- evil-visual-point beg))
         (type (evil-visual-type)))
    (unless (= (if (< n 0) beg end) (if (< n 0) (point-min) (point-max)))
      (let ((text (delete-and-extract-region beg end)))
        (goto-char beg)
        ;; The last line has no newline: borrow the one before it
        (unless (string-suffix-p "\n" text)
          (setq text (concat text "\n"))
          (delete-char -1))
        (forward-line n)
        ;; Moving onto the last line, which has no newline: give it one
        (when (and (eobp) (not (bolp)))
          (insert "\n")
          (setq text (substring text 0 -1)))
        (let ((new (point)))
          (insert text)
          (evil-visual-make-selection (+ new mark-off) (+ new point-off) type)
          (setq deactivate-mark nil))))))

(defun my/move-lines-down ()
  "Move the selected lines down one."
  (interactive)
  (my/move-lines 1))

(defun my/move-lines-up ()
  "Move the selected lines up one."
  (interactive)
  (my/move-lines -1))

;; Folding: f folds the selected lines, Tab opens and closes a fold, F
;; removes folds for good.  Folds last until the buffer is closed.
(use-package vimish-fold
  :commands (vimish-fold vimish-fold-toggle vimish-fold-delete))

(declare-function vimish-fold--folds-in "vimish-fold")
(declare-function vimish-fold--delete "vimish-fold")

(defun my/fold-selection ()
  "Fold the lines of the visual selection."
  (interactive)
  (vimish-fold evil-visual-beginning evil-visual-end)
  (evil-normal-state))

(defun my/unfold-selection ()
  "Remove every fold the visual selection touches."
  (interactive)
  (require 'vimish-fold)
  (mapc #'vimish-fold--delete
        (vimish-fold--folds-in evil-visual-beginning evil-visual-end))
  (evil-normal-state))

(use-package evil-collection
  :after evil
  :config
  (setq evil-collection-mode-list '(dired ibuffer corfu helpful))
  (evil-collection-init))

;;; Windows
(use-package window
  :ensure nil
  :custom
  (window-combination-resize t))

;;; Dired
(use-package dired
  :ensure nil
  :custom
  (dired-kill-when-opening-new-dired-buffer t)
  :config
  (evil-define-key 'normal dired-mode-map
    "=" #'dired-create-empty-file     ; the +/= key on its own
    "+" #'dired-create-directory))    ; with Shift

(use-package ibuffer
  :ensure nil
  :custom
  (ibuffer-expert t)
  (ibuffer-show-empty-filter-groups nil))

(use-package ibuffer-project            ; group buffers by project
  :hook
  (ibuffer . (lambda ()
               (setq ibuffer-filter-groups (ibuffer-project-generate-filter-groups)))))

;;; Completion: fzf-style fuzzy finding in the minibuffer
(use-package vertico              ; vertical candidate list
  :init (vertico-mode 1)
  :custom (vertico-cycle t)
  :bind (:map vertico-map
         ("C-j" . vertico-next)
         ("C-k" . vertico-previous)))

(use-package orderless            ; fzf-like matching
  :custom
  (completion-styles '(orderless basic))
  (completion-category-overrides '((file (styles basic partial-completion))))
  ;; Each space-separated term matches literally, as a regexp, or
  ;; fuzzily (letters in order, like fzf); terms can come in any order
  (orderless-matching-styles '(orderless-literal orderless-regexp orderless-flex)))

(use-package consult              ; buffer switcher and searches
  :init
  (recentf-mode 1)                ; lets consult-buffer offer recent files too
  :config
  ;; Hide non-color "themes" from consult-theme: newcomers-presets changes
  ;; settings (turns on the tab bar), light-blue is obsolete, and base16 is
  ;; just the base16 package's helper file
  (setq consult-themes
        (seq-difference (custom-available-themes)
                        '(newcomers-presets light-blue base16)))
  (advice-add 'consult-theme :after #'my/save-theme))

(use-package consult-eglot              ; project-wide symbols, via clangd
  :after (consult eglot))

(use-package marginalia           ; a description beside each candidate
  :init (marginalia-mode 1))

;;; M-x: a centered box, bordered like the popups, at 75% text.  M-m
;;; and M-p inside narrow it (see below).
(use-package vertico-posframe
  :custom
  (vertico-posframe-border-width 3)
  :custom-face
  (vertico-posframe-border ((t (:background "#cc7833"))))) ; popup orange

(use-package vertico-multiform    ; per-command looks, part of vertico
  :ensure nil
  :after vertico
  :custom
  (vertico-multiform-commands
   '((execute-extended-command
      posframe
      (vertico-count . 16)
      (vertico-posframe-min-height . 16)))) ; 20 lines at 75% text, hints included
  :config
  (vertico-multiform-mode 1))

;; Two filters, on and off independently, and combinable:
;;   M-m  commands from the modes active in your buffer
;;   M-p  commands with a key binding there
(defvar-local my/mx-filters nil
  "The M-x filters switched on: `active' and/or `bound'.")

(defvar-local my/mx-all-predicate nil
  "M-x's own predicate, which the filters narrow.")

(defvar-local my/mx-mode-prefixes nil
  "Name prefixes of the modes active where M-x was called, e.g. \"evil-\".")

(defvar-local my/mx-bound nil
  "Commands with a key binding where M-x was called, worked out on first M-p.")

(defun my/mx-active-modes (buffer)
  "Prefixes for BUFFER's major mode (and parents) and its minor modes."
  (with-current-buffer buffer
    (delete-dups
     (mapcar (lambda (mode)
               (concat (string-remove-suffix
                        "-mode" (string-remove-prefix "global-" (symbol-name mode)))
                       "-"))
             (append (derived-mode-all-parents major-mode)
                     local-minor-modes global-minor-modes)))))

(defun my/mx-bound-commands (buffer)
  "A set of the commands bound to a key in BUFFER (menus don't count).
Walks BUFFER's keymaps for candidates, then keeps those `where-is'
can still reach, so a key another map shadows doesn't count."
  (let ((seen (make-hash-table :test #'eq))
        (set (make-hash-table :test #'eq)))
    (with-current-buffer buffer
      (named-let walk ((maps (current-active-maps)) (depth 0))
        (dolist (map maps)
          (map-keymap
           (lambda (event def)
             (unless (memq event '(menu-bar tool-bar tab-bar remap))
               (when (eq (car-safe def) 'menu-item)
                 (setq def (nth 2 def)))
               (cond ((and (symbolp def) (commandp def))
                      (puthash def t seen))
                     ((and (keymapp def) (< depth 4))
                      (walk (list def) (1+ depth))))))
           map)))
      (maphash (lambda (sym _)
                 (when (seq-some (lambda (key)
                                   (not (memq (aref key 0)
                                              '(menu-bar tool-bar tab-bar remap))))
                                 (where-is-internal sym))
                   (puthash sym t set)))
               seen))
    set))

(defun my/mx-setup ()
  "Shrink M-x's text and note the active modes, for M-m."
  (when (eq current-minibuffer-command 'execute-extended-command)
    (face-remap-add-relative 'default :height 0.75)
    (setq my/mx-all-predicate minibuffer-completion-predicate
          my/mx-mode-prefixes (my/mx-active-modes
                               (window-buffer (minibuffer-selected-window))))
    ;; The box's first sizing cuts off the hint line; redraw it once
    ;; it's up, as any later keypress would
    (run-at-time 0 nil #'my/mx-redraw (current-buffer))))

(add-hook 'minibuffer-setup-hook #'my/mx-setup)

(defvar vertico--input)
(declare-function vertico--exhibit "vertico")

(defun my/mx-redraw (minibuffer)
  "Recompute and redisplay M-x's candidates in MINIBUFFER."
  (when (buffer-live-p minibuffer)
    (with-current-buffer minibuffer
      (setq vertico--input t)
      (vertico--exhibit))))

(defun my/mx-toggle (filter)
  "Switch FILTER on or off, and narrow the candidates to match."
  (setq my/mx-filters (if (memq filter my/mx-filters)
                          (delq filter my/mx-filters)
                        (cons filter my/mx-filters)))
  (let ((buffer (window-buffer (minibuffer-selected-window)))
        (all my/mx-all-predicate)
        (prefixes my/mx-mode-prefixes)
        (bound (and (memq 'bound my/mx-filters)
                    (or my/mx-bound
                        (setq my/mx-bound (my/mx-bound-commands
                                           (window-buffer (minibuffer-selected-window)))))))
        (active (memq 'active my/mx-filters)))
    (setq minibuffer-completion-predicate
          (if (not my/mx-filters)
              all
            (lambda (sym)
              (and (funcall all sym)
                   (or (not bound) (gethash sym bound))
                   (or (not active)
                       (let ((name (symbol-name sym)))
                         (seq-some (lambda (p) (string-prefix-p p name)) prefixes))
                       (command-completion-using-modes-and-keymaps-p sym buffer)))))))
  (setq vertico--input t))                ; recompute the candidates

(defun my/mx-toggle-active ()
  "In M-x, show only commands from the active modes (or stop).
A command counts if its name starts with an active mode's (evil-...,
c-ts-...), it's bound in the buffer's mode keymaps, or it's declared
for one of the buffer's modes."
  (interactive)
  (my/mx-toggle 'active))

(defun my/mx-toggle-bound ()
  "In M-x, show only commands with a key binding (or stop)."
  (interactive)
  (my/mx-toggle 'bound))

;; Hint lines under the candidates, like the popups': the filter keys
;; (one that's on is lit up), then the orderless prefixes that narrow
;; what a single search term matches
(defun my/mx-hints ()
  (cl-flet ((hint (key text filter)
              (concat (propertize key 'face 'pop/hint-key) " "
                      (propertize text 'face (if (memq filter my/mx-filters)
                                                 'pop/hint-key
                                               'pop/hint-text))))
            (prefix (char text)        ; a size down from the keys above
              (concat (propertize char 'face '(:inherit pop/hint-key :height 0.85))
                      (propertize "x " 'face '(:inherit shadow :height 0.85))
                      (propertize text 'face '(:inherit pop/hint-text :height 0.85)))))
    (concat " " (hint "M-m" "active modes" 'active) "  "
            (hint "M-p" "has a key" 'bound) "\n "
            (mapconcat (lambda (p) (prefix (car p) (cdr p)))
                       '(("!" . "not") ("&" . "in docs")
                         ("^" . "start") ("," . "initials")
                         ("=" . "exact"))
                       "  "))))

(defun my/mx-add-hints (args)
  "Add the hint lines to M-x's candidate LINES (the first of ARGS)."
  (if (eq current-minibuffer-command 'execute-extended-command)
      (list (append (car args) (list (concat "\n" (my/mx-hints)))))
    args))

(advice-add 'vertico--display-candidates :filter-args #'my/mx-add-hints)

(with-eval-after-load 'vertico
  (pcase-dolist (`(,key . ,cmd) '(("M-m" . my/mx-toggle-active)
                                  ("M-p" . my/mx-toggle-bound)))
    (keymap-set vertico-map key
                `(menu-item "" ,cmd
                            :filter ,(lambda (cmd)
                                       (and (eq current-minibuffer-command
                                                'execute-extended-command)
                                            cmd))))))

;; LANGS
(use-package c-ts-mode
  :ensure nil
  :init
  ;; Use the tree-sitter modes for .c and .h files
  (add-to-list 'major-mode-remap-alist '(c-mode . c-ts-mode))
  (add-to-list 'major-mode-remap-alist '(c-or-c++-mode . c-or-c++-ts-mode))
  :config
  ;; Where to fetch the C grammar from
  (add-to-list 'treesit-language-source-alist
               '(c "https://github.com/tree-sitter/tree-sitter-c"))
  :custom
  (c-ts-mode-indent-offset 2)
  (c-ts-mode-indent-style 'k&r)
  :hook
  (c-ts-mode . electric-pair-local-mode))

;;; Autocompletion: a popup of candidates as you type
(use-package corfu
  :init (global-corfu-mode 1)
  :custom
  (corfu-auto t)             ; show candidates automatically while typing
  (corfu-auto-prefix 2)      ; ...after 3 characters
  (corfu-auto-delay 0.4)     ; ...and a short pause
  (corfu-cycle t)            ; wrap around at the ends of the list
  :config
  ;; Popup text at 75% of the buffer's (text scaling included)
  (set-face-attribute 'corfu-default nil :height 0.75))

;;; Command log: a live side buffer of every key and the command it ran
(use-package command-log-mode
  :commands clm/toggle-command-log-buffer
  :custom
  (command-log-mode-key-binding-open-log nil)   ; don't grab C-c o
  (command-log-mode-open-log-turns-on-mode t)   ; opening the log starts logging
  (command-log-mode-is-global t))               ; ...in every buffer

;;; Key hints: pause after a prefix to see what can follow it
(use-package which-key
  :ensure nil                          ; built in since Emacs 30
  :init (which-key-mode 1))

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

;;; Richer help buffers (source, references, keybindings)
(use-package helpful
  :bind
  (([remap describe-function] . helpful-callable)
   ([remap describe-variable] . helpful-variable)
   ([remap describe-command]  . helpful-command)
   ([remap describe-key]      . helpful-key)
   ([remap describe-symbol]   . helpful-symbol)))

(use-package eldoc
  :ensure nil
  :custom
  (eldoc-idle-delay 0.2)                 ; pause before docs appear (default 0.5)
  (eldoc-echo-area-use-multiline-p t)    ; let the echo area grow to fit
  (eldoc-echo-area-prefer-doc-buffer t)) ; if *eldoc* is open, show docs there instead

(use-package eglot
  :ensure nil
  :hook (c-ts-mode . eglot-ensure)     ; start clangd in every C buffer
  :init
  (setq eglot-stay-out-of '(eldoc))    ; keep eglot out of the echo area
  :custom
  (eglot-ignored-server-capabilities '(:inlayHintProvider)) ; no inline hints
  (eglot-autoshutdown t)               ; stop it when the last C buffer closes
  (eglot-extend-to-xref t)             ; headers you jump into reuse that clangd
  :config
  ;; clangd marks inactive #ifdef branches (e.g. an stb-style
  ;; #ifdef FOO_IMPLEMENTATION block) as "comment" tokens, greying them out;
  ;; tree-sitter already highlights real comments
  (setq eglot-semantic-token-types
        (delete "comment" eglot-semantic-token-types)))

;;; Popups
(load (locate-user-emacs-file "popup") nil t)  ;; API
(load (locate-user-emacs-file "popups") nil t) ;; Implementations

;; Keys that override everything; must load after evil
(load (locate-user-emacs-file "universal") nil t)

;; Mode line, with F-key slots; must load after universal
(load (locate-user-emacs-file "modeline") nil t)
