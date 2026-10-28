;;; langs.el --- programming: indentation, C, eglot, compiling -*- lexical-binding: t -*-

(require 'popup (locate-user-emacs-file "popup"))

;; Mode-specific popups go here, each with its mode's slots, which
;; replace the defaults (see `ml/mode-slots' in modeline.el):
;;
;;   (with-eval-after-load 'modeline
;;     (add-to-list 'ml/mode-slots
;;                  '(c-ts-mode ("compile" . pop/compile-toggle) ...)))

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

;;; C
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

;;; Language server
(use-package consult-eglot              ; project-wide symbols, via clangd
  :after (consult eglot))

(use-package eldoc
  :ensure nil
  :custom
  (eldoc-idle-delay 0.2)                 ; pause before docs appear (default 0.5)
  (eldoc-echo-area-use-multiline-p nil)  ; one line, like other messages
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

;;; Compilation

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
            "K" "stop"  "?" "keys"))

(provide 'langs)
