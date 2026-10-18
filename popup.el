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
             (width . 0.75) (height . 0.75)  ; 75% of the main frame
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

(defvar pop/active nil
  "Non-nil while the popup frame has focus.")

(defun pop/update-active (&rest _)
  (setq pop/active (and (pop/live-p) (eq (selected-frame) pop/frame))))

(defun pop/refuse-split (&rest _)
  (user-error "Popups can't be split"))

(defun pop/display (buffer alist)
  "`display-buffer' action: show BUFFER in the popup frame."
  (unless (pop/live-p) (pop/make-frame))
  (let ((win (frame-root-window pop/frame)))
    (prog1 (window--display-buffer buffer win 'reuse alist)
      ;; Dedicating lets `q' hide the frame; dired needs to switch
      ;; buffers as you browse, so it handles `q' itself instead
      (set-window-dedicated-p win (and (pop/buffer-p buffer) 'popup))
      (set-window-parameter win 'mode-line-format 'none) ; no mode line
      ;; Every split attempt (C-<return>, :sp, :vs...) asks the window's
      ;; `split-window' parameter first; refuse them all in the popup
      (set-window-parameter win 'split-window #'pop/refuse-split)
      (unless pop/suppress
        (make-frame-visible pop/frame)))))

(add-to-list 'display-buffer-alist '(pop/buffer-p pop/display))

;; When `q' closes a popup, hide its frame rather than minimizing all of Emacs
(setq iconify-child-frame 'make-invisible)

(defun pop/showing-p (pred)
  "Non-nil if the popup is visible and its buffer satisfies PRED."
  (and (pop/visible-p)
       (with-current-buffer (window-buffer (frame-root-window pop/frame))
         (funcall pred))))

(defun pop/focus ()
  "Move focus into the popup."
  (select-frame-set-input-focus pop/frame)
  (select-window (frame-root-window pop/frame))
  (pop/update-active))

(defun pop/hide ()
  "Hide the popup and return focus to the main frame."
  (interactive)
  (when (pop/visible-p)
    (let ((parent (frame-parent pop/frame)))
      (make-frame-invisible pop/frame)
      (select-frame-set-input-focus parent)
      (pop/update-active))))

(defun pop/close-or-delete-window ()
  "In the popup, hide it and kill its buffer; elsewhere, delete the window."
  (interactive)
  (if (not (eq (selected-frame) pop/frame))
      (delete-window)
    (let ((buf (window-buffer (frame-root-window pop/frame)))
          (kill-buffer-query-functions nil))   ; don't ask about running builds
      (pop/hide)
      (kill-buffer buf))))

;;;; Keys inside the popup

;; These beat your universal keys, but only while focus is in the popup.
;; Bind anything here that should behave differently in a popup.
(defvar-keymap pop/keys-map
  "C-<return>" #'pop/ctrl-return)

(defun pop/ctrl-return ()
  "C-<return> in a popup: dired opens in a new split, compile prompts.
In the popup's minibuffer, it submits."
  (interactive)
  (cond ((minibufferp) (exit-minibuffer))
        ((derived-mode-p 'dired-mode) (pop/dired-open-in-split))
        ((derived-mode-p 'compilation-mode) (pop/compile-prompt))))

(add-hook 'window-selection-change-functions #'pop/update-active)

;; Go in front of `univ-keys-map', which universal.el registers when it loads
(with-eval-after-load 'universal
  (add-to-list 'emulation-mode-map-alists `((pop/active . ,pop/keys-map))))

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
  (cond ((pop/showing-p (lambda () (derived-mode-p 'compilation-mode)))
         (pop/hide))
        (t (unless (get-buffer "*compilation*")
             (let ((dir default-directory))
               (with-current-buffer (get-buffer-create "*compilation*")
                 (setq default-directory dir)
                 (compilation-mode)
                 (let ((inhibit-read-only t))
                   (insert "C-<return> to enter a compile command\n")))))
           (display-buffer "*compilation*")
           (pop/focus))))

(defun pop/compile-prompt ()
  "Prompt for a compile command in the popup's minibuffer and run it.
The prompt starts with the last command, so C-<return> twice reruns it."
  (interactive)
  (let ((command (read-shell-command "Compile: " compile-command
                                     'compile-history)))
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
  "Bind RET in compilation buffers, overriding evil.
The button map is the keymap on the error text itself, which wins
over everything else when point is on an error."
  (dolist (map (list compilation-mode-map compilation-button-map))
    (keymap-set map "RET" #'pop/compile-goto-error))
  (with-eval-after-load 'evil
    (evil-define-key* '(normal motion) compilation-mode-map
      (kbd "RET") #'pop/compile-goto-error)))

(with-eval-after-load 'compile
  (pop/compile-setup-keys))

;;;; Dired

(declare-function dired-get-file-for-visit "dired")
(declare-function dired-find-file "dired")
(declare-function dired-goto-file "dired")
(declare-function dired-noselect "dired")
(defvar dired-mode-map)

(defun pop/main-buffer ()
  "The buffer you're working in in the main frame."
  (window-buffer (frame-selected-window
                  (or (and (pop/live-p) (frame-parent pop/frame))
                      (selected-frame)))))

(defun pop/dired-toggle ()
  "Show or hide a dired popup at the current file's directory."
  (interactive)
  (if (pop/showing-p (lambda () (derived-mode-p 'dired-mode)))
      (pop/hide)
    (let* ((main (pop/main-buffer))
           (file (buffer-file-name main))
           (buf (dired-noselect (buffer-local-value 'default-directory main))))
      (pop/display buf nil)
      (pop/focus)
      (when file (dired-goto-file file)))))   ; land on the file you came from

(defun pop/dired-find-file ()
  "In the popup: enter directories in place; open files in the main frame."
  (interactive)
  (let ((file (dired-get-file-for-visit)))
    (if (and (eq (selected-frame) pop/frame)
             (not (file-directory-p file)))
        (progn (pop/hide)
               (find-file file))
      (dired-find-file))))

(defun pop/dired-open-in-split ()
  "Hide the popup and open the file at point in a new split in the main frame."
  (interactive)
  (let ((file (dired-get-file-for-visit)))
    (pop/hide)
    (select-window (split-window-right))
    (find-file file)))

(defun pop/dired-quit ()
  "Hide the popup when in it; otherwise the usual `quit-window'."
  (interactive)
  (if (eq (selected-frame) pop/frame)
      (pop/hide)
    (quit-window)))

;; Remapping catches these commands whichever key runs them (RET, q, evil's)
(with-eval-after-load 'dired
  (keymap-set dired-mode-map "<remap> <dired-find-file>" #'pop/dired-find-file)
  (keymap-set dired-mode-map "<remap> <quit-window>" #'pop/dired-quit))

(provide 'popup)
