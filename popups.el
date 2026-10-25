;;; popups.el --- popup type definitions -*- lexical-binding: t -*-

;; Each popup is a `pop/define' declaration plus the few commands it
;; needs.  Toggle keys live in universal.el.

(require 'popup)

(declare-function face-remap-remove-relative "face-remap")
(defvar-local pop/text-scale-cookie nil)

(defun pop/text-scale (factor)
  "Scale the current buffer's text by FACTOR, replacing any earlier scale."
  (when pop/text-scale-cookie
    (face-remap-remove-relative pop/text-scale-cookie))
  (setq-local pop/text-scale-cookie
              (face-remap-add-relative 'default :height factor)))

;;;; Compilation

(defvar compilation-always-kill)
(defvar compilation-scroll-output)
(defvar compile-command)
(defvar compile-history)
(declare-function compile-goto-error "compile")
(declare-function compilation-mode "compile")

(setq compilation-always-kill t               ; new compile kills old, no prompt
      compilation-scroll-output 'first-error) ; follow output, stop at 1st error

;; Render gcc's colored output instead of showing raw escape codes
(add-hook 'compilation-filter-hook #'ansi-color-compilation-filter)

;; No column indicator in compilation buffers
(setq global-display-fill-column-indicator-modes
      '((not special-mode compilation-mode) t))

(defvar compilation-directory)

;; Compiles run from the project root of the file you're in.  A directory
;; picked with `d' sticks while you stay in that project.

(defvar pop/compile-picked-dir nil
  "Directory chosen with `pop/compile-set-directory', or nil.")

(defun pop/project-dir (buffer)
  "BUFFER's project root, or its own directory if it's in no project."
  (let ((dir (buffer-local-value 'default-directory buffer)))
    (if-let* ((project (project-current nil dir)))
        (expand-file-name (project-root project))
      dir)))

(defun pop/compile-use-directory (dir)
  "Compile from DIR from now on, reruns included."
  (setq default-directory (file-name-as-directory dir)
        compilation-directory default-directory))

(defun pop/compile-buffer ()
  "The compilation buffer, pointed at the current project's root."
  (let ((root (pop/project-dir (pop/main-buffer))))
    (with-current-buffer (get-buffer-create "*compilation*")
      (unless (derived-mode-p 'compilation-mode)
        (compilation-mode))
      ;; Leave a running compile alone; changing directory mid-run would
      ;; break finding the files its errors point at
      (unless (get-buffer-process (current-buffer))
        (unless (and pop/compile-picked-dir
                     (string-prefix-p root pop/compile-picked-dir))
          (setq pop/compile-picked-dir nil))
        (pop/compile-use-directory (or pop/compile-picked-dir root)))
      (current-buffer))))

(defun pop/compile-set-directory ()
  "Choose the directory compiles run from."
  (interactive)
  (if (get-buffer-process (current-buffer))
      (user-error "Wait for the compile to finish (or K to stop it)")
    (let ((dir (read-directory-name "Compile in: " default-directory nil t)))
      (setq pop/compile-picked-dir (file-name-as-directory (expand-file-name dir)))
      (pop/compile-use-directory pop/compile-picked-dir)
      (force-mode-line-update))))

(defun pop/compile-prompt ()
  "Prompt for a compile command in the popup's minibuffer and run it.
The prompt starts with the last command, so C-<return> twice reruns it."
  (interactive)
  (compile (read-shell-command "Compile: " compile-command 'compile-history))
  (pop/focus))

(defun pop/compile-goto-error ()
  "Hide the popup and jump to the error at point in the main frame."
  (interactive)
  (let ((buf (current-buffer))
        (pos (point))
        ;; Jumping makes compile re-display its buffer; keep the popup hidden
        (pop/suppress t))
    (pop/hide)
    (with-current-buffer buf
      (goto-char pos)
      (compile-goto-error))
    (pop/hide)))

(defun pop/compile-rerun ()
  "Run the last compile command again."
  (interactive)
  (recompile)
  (pop/focus))

;; Status bar: state, how long it took, the command, and error counts

(defvar compilation-arguments)
(defvar compilation-num-errors-found)
(defvar compilation-num-warnings-found)

(defvar-local pop/compile-started nil "When the current run started.")
(defvar-local pop/compile-result nil "(MESSAGE . SECONDS) of the last finished run.")

(add-hook 'compilation-start-hook
          (lambda (_proc)
            (setq pop/compile-started (float-time)
                  pop/compile-result nil)))

(add-hook 'compilation-finish-functions
          (lambda (buf msg)
            (with-current-buffer buf
              (setq pop/compile-result
                    (cons (string-trim msg)
                          (and pop/compile-started
                               (- (float-time) pop/compile-started)))))))

(defun pop/compile-status ()
  "The run's state as a colored string, e.g. \"✓ done 1.2s\"."
  (pcase-let ((`(,msg . ,secs) pop/compile-result))
    (cond ((get-buffer-process (current-buffer))
           (propertize "● running" 'face 'warning))
          ((null msg)
           (propertize "○ ready" 'face 'shadow))
          ((string-prefix-p "finished" msg)
           (propertize (format "✓ done %.1fs" (or secs 0)) 'face 'success))
          (t
           (propertize (if (string-match "code \\([0-9]+\\)" msg)
                           (format "✗ exit %s  %.1fs" (match-string 1 msg) (or secs 0))
                         (format "✗ %s" msg))
                       'face 'error)))))

(defun pop/compile-header ()
  "Header line for the compile popup."
  (let ((cmd (car compilation-arguments))
        (errors compilation-num-errors-found)
        (warnings compilation-num-warnings-found))
    (list " " (pop/compile-status)
          "   " (propertize (string-replace "%" "%%" (abbreviate-file-name default-directory))
                            'face 'font-lock-function-name-face)
          (if cmd
              (concat "   " (propertize (string-replace "%" "%%" cmd)
                                        'face 'font-lock-string-face))
            "   C-RET to start")
          'mode-line-format-right-align
          (if (> errors 0)
              (propertize (format "%d error%s  " errors (if (= errors 1) "" "s"))
                          'face 'error)
            "")
          (if (> warnings 0)
              (propertize (format "%d warning%s  " warnings (if (= warnings 1) "" "s"))
                          'face 'warning)
            ""))))

(pop/define compile
  :match   (derived-mode-p 'compilation-mode)
  :open    #'pop/compile-buffer
  :capture t
  :setup   (progn (pop/text-scale 0.8)
                  (setq-local header-line-format '(:eval (pop/compile-header))))
  :keys    ("RET"        pop/compile-goto-error
            "C-<return>" pop/compile-prompt
            "r"          pop/compile-rerun
            "n"          compilation-next-error
            "p"          compilation-previous-error
            "K"          kill-compilation
            "d"          pop/compile-set-directory
            "q"          pop/hide)
  :hints   ("C-RET" "compile"  "r" "rerun"  "d" "directory"  "n/p" "next/prev error"
            "RET" "go to error"  "K" "stop"  "?" "keys"  "esc" "close")
  :help    (("Run"
             "C-RET" "enter a compile command"
             "C-RET C-RET" "rerun, from the prompt"
             "r" "rerun the last command"
             "K" "stop the running compile"
             "d" "change directory (sticks per project)")
            ("Errors"
             "n" "next error"
             "p" "previous error"
             "RET" "jump to error at point"
             "M-n/M-p" "next/previous error")
            ("Output"
             "j/k" "move"
             "gg/G" "top / bottom"
             "/" "search")
            ("Popup"
             "?" "this sheet"
             "esc/q" "close"
             "C-x" "close and kill buffer")))

;;;; Dired

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
  :keys    ("RET"        pop/dired-find-file
            "C-<return>" pop/dired-open-in-split
            "q"          pop/hide)
  :hints   ("RET" "open"  "C-RET" "split"  "-" "up"  "m/u" "mark"
            "d/x" "delete"  "R" "rename"  "C" "copy"  "=" "file"  "+" "dir"
            "?" "keys"  "esc" "close")
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

;;;; Ibuffer

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
  :keys    ("RET"        pop/ibuffer-visit
            "C-<return>" pop/ibuffer-visit-in-split
            "q"          pop/hide)
  :hints   ("RET" "visit"  "C-RET" "split"  "m/u" "mark"  "d/x" "kill"
            "S" "save"  "s n" "filter"  "s /" "unfilter"  "TAB" "next group"
            "?" "keys"  "esc" "close")
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

(provide 'popups)
