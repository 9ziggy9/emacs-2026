;;; popup.el --- Quake-style floating popups -*- lexical-binding: t -*-

;;;; The popup frame
(defvar pop/border-color "#cc7833"
  "Color of the border around the popup (Railscasts orange).")

(defvar pop/border-width 3
  "Width of the border around the popup, in pixels.")

(defvar pop/text-scale 0.8
  "Text size in popup buffers, relative to normal buffer text.")

(defvar pop/regexp (rx bos "*compilation*" eos)
  "Buffers whose names match this open in the floating popup.")

(defvar pop/frame nil
  "The child frame that holds popups, reused between calls.")

(defun pop/buffer-p (buffer-or-name &optional _)
  "Non-nil if BUFFER-OR-NAME should be shown in the popup."
  (when-let* ((buf (get-buffer buffer-or-name)))
    (string-match-p pop/regexp (buffer-name buf))))

(defun pop/live-p ()
  (and pop/frame (frame-live-p pop/frame) t))

(defun pop/visible-p ()
  (and (pop/live-p) (frame-visible-p pop/frame) t))

(defun pop/make-frame ()
  "Create the hidden popup frame, centered over the main frame."
  (let ((parent (or (frame-parent) (selected-frame))))
    (setq pop/frame
          (make-frame
           `((parent-frame . ,parent)
             (left . 0.5) (top . 0.5)        ; 0.5 = dead center
             (width . 0.75) (height . 0.75)    ; half the main frame
             (keep-ratio . t)
             (minibuffer . t)                ; its own minibuffer for prompts
             (unsplittable . t)
             (no-other-frame . t)
             (undecorated . t)
             (child-frame-border-width . ,pop/border-width)
             (visibility . nil))))
    (set-face-background 'child-frame-border pop/border-color pop/frame)
    pop/frame))

(defvar pop/suppress nil
  "When non-nil, popup buffers are updated but the popup stays hidden.")

(defun pop/display (buffer alist)
  "`display-buffer' action: show BUFFER in the popup frame."
  (unless (pop/live-p) (pop/make-frame))
  (let ((win (frame-root-window pop/frame)))
    (prog1 (window--display-buffer buffer win 'reuse alist)
      (set-window-dedicated-p win 'popup)              ; lets `q' hide the frame
      (set-window-parameter win 'mode-line-format 'none) ; no mode line
      (unless pop/suppress
        (make-frame-visible pop/frame)))))

(add-to-list 'display-buffer-alist '(pop/buffer-p pop/display))

;; When `q' closes a popup, hide its frame rather than minimizing all of Emacs
(setq iconify-child-frame 'make-invisible)

(defun pop/focus ()
  "Move focus into the popup."
  (select-frame-set-input-focus pop/frame)
  (select-window (frame-root-window pop/frame)))

(defun pop/hide ()
  "Hide the popup and return focus to the main frame."
  (interactive)
  (when (pop/visible-p)
    (let ((parent (frame-parent pop/frame)))
      (make-frame-invisible pop/frame)
      (select-frame-set-input-focus parent))))

(defun pop/close-or-delete-window ()
  "In the popup, hide it and kill its buffer; elsewhere, delete the window."
  (interactive)
  (if (not (eq (selected-frame) pop/frame))
      (delete-window)
    (let ((buf (window-buffer (frame-root-window pop/frame)))
          (kill-buffer-query-functions nil))   ; don't ask about running builds
      (pop/hide)
      (kill-buffer buf))))

;;;; Compilation

;; Tell the byte compiler these come from compile.el and evil
(defvar compilation-always-kill)
(defvar compilation-scroll-output)
(defvar compilation-mode-map)
(defvar compilation-button-map)
(defvar compile-command)
(defvar compile-history)
(declare-function compile-goto-error "compile")
(declare-function compilation-mode "compile")
(declare-function evil-define-key* "evil-core")

(setq compilation-always-kill t               ; new compile kills old, no prompt
      compilation-scroll-output 'first-error) ; follow output, stop at 1st error

;; Render gcc's colored output instead of showing raw escape codes
(add-hook 'compilation-filter-hook #'ansi-color-compilation-filter)

;; No column indicator in compilation buffers
(setq global-display-fill-column-indicator-modes
      '((not special-mode compilation-mode) t))

(defun pop/compile-buffer-setup ()
  "Shrink the text in compilation buffers."
  (face-remap-add-relative 'default :height pop/text-scale))

(add-hook 'compilation-mode-hook #'pop/compile-buffer-setup)

(defun pop/compile-toggle ()
  "Show or hide the compilation popup.
The first time, opens an empty compilation buffer in the current
file's directory, ready for `pop/compile-prompt'."
  (interactive)
  (cond ((pop/visible-p) (pop/hide))
        (t (unless (get-buffer "*compilation*")
             (let ((dir default-directory))
               (with-current-buffer (get-buffer-create "*compilation*")
                 (setq default-directory dir)
                 (compilation-mode)
                 (let ((inhibit-read-only t))
                   (insert "C-n to enter a compile command\n")))))
           (display-buffer "*compilation*")
           (pop/focus))))

(defvar-keymap pop/compile-prompt-map
  :doc "Extra keys while entering a compile command."
  "C-n" #'exit-minibuffer)

(defun pop/compile-prompt ()
  "Prompt for a compile command in the popup's minibuffer and run it.
The prompt starts with the last command, so C-n C-n reruns it."
  (interactive)
  (let ((command
         (minibuffer-with-setup-hook
             (lambda ()
               (use-local-map (make-composed-keymap pop/compile-prompt-map
                                                    (current-local-map))))
           (read-shell-command "Compile: " compile-command 'compile-history))))
    (compile command)
    (pop/focus)))

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

(defun pop/compile-setup-keys ()
  "Bind RET and C-n in compilation buffers, overriding evil.
The button map is the keymap on the error text itself, which wins
over everything else when point is on an error."
  (dolist (map (list compilation-mode-map compilation-button-map))
    (keymap-set map "RET" #'pop/compile-goto-error)
    (keymap-set map "C-n" #'pop/compile-prompt))
  (with-eval-after-load 'evil
    (evil-define-key* '(normal motion) compilation-mode-map
      (kbd "RET") #'pop/compile-goto-error
      (kbd "C-n") #'pop/compile-prompt)))

(with-eval-after-load 'compile
  (pop/compile-setup-keys))

(provide 'popup)
