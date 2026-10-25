;;; popup.el --- framework for Quake-style floating popups -*- lexical-binding: t -*-

;; Popup types are declared with `pop/define' (see popups.el).  All types
;; share one centered child frame; showing a different type swaps its
;; content and size.  While a popup has focus, keys are looked up in this
;; order:
;;
;;   1. the popup type's own :keys (beats everything, evil included),
;;      then `pop/common-map', keys every popup shares (e.g. escape)
;;   2. your universal keys, unless the type is isolated (the default);
;;      isolated popups keep only universal keys bound to pop/ commands
;;      plus any listed in :keep
;;   3. the buffer's own bindings (mode map, evil)

(require 'cl-lib)

;;;; Settings

(defvar pop/border-color "#cc7833"
  "Color of the border around the popup (Railscasts orange).")

(defvar pop/border-width 3
  "Width of the border around the popup, in pixels.")

(defvar pop/default-size '(0.75 . 0.75)
  "Popup (WIDTH . HEIGHT) as fractions of the main frame.")

(defvar pop/always-keep '("C-=" "C--" "C-0")
  "Universal keys every popup keeps, even isolated ones (zoom).")

(defvar-keymap pop/common-map
  :doc "Keys every popup gets; a type's own :keys override these."
  "<escape>" #'pop/escape
  ;; Only where there's a reference, and not while typing (e.g. in the
  ;; scratchpad, or editing names in dired), so ? can still be typed
  "?"        `(menu-item "" pop/show-keys
                         :filter ,(lambda (cmd)
                                    (and (not (memq (bound-and-true-p evil-state)
                                                    '(insert replace emacs)))
                                         (pop/prop (pop/current-type) :help)
                                         cmd))))

(defvar-keymap pop/minibuffer-map
  :doc "Keys in the popup's minibuffer."
  "C-<return>" #'exit-minibuffer)

;;;; Popup types

(defvar pop/types nil
  "Alist of (NAME . PLIST) for each popup type, in definition order.")

(defun pop/register (name plist)
  (setf (alist-get name pop/types) plist))

(defun pop/type-of (buffer)
  "The name of the popup type BUFFER belongs to, or nil."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (car (cl-find-if (lambda (type) (funcall (plist-get (cdr type) :match)))
                       pop/types)))))

(defun pop/prop (name prop)
  (plist-get (alist-get name pop/types) prop))

(defconst pop/key-aliases
  '(("RET" . "<return>") ("TAB" . "<tab>")
    ("DEL" . "<backspace>") ("ESC" . "<escape>"))
  "Keys a GUI sends as a function key first, e.g. Return arrives as <return>.
Emacs only falls back to RET when nothing binds <return>, and packages
like evil-collection do bind it, so popup keys are bound under both.")

(defun pop/make-keys-map (pairs)
  "Keymap from PAIRS (KEY COMMAND ...), also binding each key's GUI alias."
  (let ((map (make-sparse-keymap)))
    (cl-loop for (key cmd) on pairs by #'cddr
             do (keymap-set map key cmd)
                (when-let* ((alias (cdr (assoc key pop/key-aliases))))
                  (keymap-set map alias cmd)))
    map))

;; Relative to the mode line, which modeline.el already shrinks to 0.85
(defface pop/hint-key '((t :inherit font-lock-keyword-face :weight bold :height 0.9))
  "Face for a key in a popup's hint line.")

(defface pop/hint-text '((t :inherit shadow :height 0.9))
  "Face for what a key does in a popup's hint line.")

(defun pop/format-hints (pairs)
  "Hint line from PAIRS (KEY TEXT ...), or nil if there are none."
  (when pairs
    (propertize
     (mapconcat (lambda (pair)
                  (concat (propertize (car pair) 'face 'pop/hint-key) " "
                          (propertize (cadr pair) 'face 'pop/hint-text)))
                (seq-split pairs 2)
                "  ")
     'local-map pop/hint-scroll-map
     'help-echo "Scroll here to see more")))

;; The hint line is the popup's mode line, which can't scroll by itself;
;; the mouse wheel over it shifts the text instead

(defvar pop/hint-offset 0
  "How many characters the hint line is scrolled to the right.")

(defun pop/scroll-hints (n)
  "Scroll the hint line N characters (negative scrolls back)."
  (let ((len (length (or (pop/prop (pop/current-type) :hints) ""))))
    (setq pop/hint-offset (max 0 (min (+ pop/hint-offset n) (1- len))))
    (force-mode-line-update t)))

(defun pop/scroll-hints-forward ()
  "Show more of the hint line."
  (interactive)
  (pop/scroll-hints 8))

(defun pop/scroll-hints-back ()
  "Show the start of the hint line again."
  (interactive)
  (pop/scroll-hints -8))

(defvar-keymap pop/hint-scroll-map
  "<mode-line> <wheel-down>"  #'pop/scroll-hints-forward
  "<mode-line> <wheel-right>" #'pop/scroll-hints-forward
  "<mode-line> <wheel-up>"    #'pop/scroll-hints-back
  "<mode-line> <wheel-left>"  #'pop/scroll-hints-back)

(defun pop/hint-line ()
  "The current popup's hints, scrolled by `pop/hint-offset'."
  (when-let* ((hints (pop/prop (pop/type-of (current-buffer)) :hints)))
    (if (zerop pop/hint-offset)
        (concat " " hints)
      (concat (propertize " « " 'face 'pop/hint-key 'local-map pop/hint-scroll-map)
              (substring hints (min pop/hint-offset (1- (length hints))))))))

(defmacro pop/define (name &rest props)
  "Define a popup type NAME and a `pop/NAME-toggle' command for it.

:match EXPR    evaluated in a buffer: non-nil if it belongs to this type
:open FN       returns the buffer to show when toggled on; without it,
               the most recent matching buffer is shown
:capture BOOL  route matching buffers here whenever Emacs displays them
:setup EXPR    evaluated in the buffer whenever it enters the popup
:size (W . H)  fractions of the main frame; default `pop/default-size'
:isolate BOOL  turn off universal keys in this popup (default t)
:keep KEYS     universal keys to keep anyway, e.g. (\"C-h\" \"C-=\")
:keys (KEY COMMAND ...)  bindings that beat everything in this popup
:hints (KEY TEXT ...)    key reminders shown along the popup's bottom
:help ((HEADING KEY TEXT ...) ...)  the fuller key reference shown on ?"
  (let ((map (intern (format "pop/%s-map" name)))
        (toggle (intern (format "pop/%s-toggle" name)))
        (keys (plist-get props :keys)))
    `(progn
       (defvar ,map nil)
       (setq ,map (pop/make-keys-map
                   (list ,@(cl-loop for (key cmd) on keys by #'cddr
                                    append (list key `#',cmd)))))
       (pop/register
        ',name
        (list :match (lambda () ,(plist-get props :match))
              :setup (lambda () ,(plist-get props :setup))
              :open ,(plist-get props :open)
              :capture ,(plist-get props :capture)
              :size ',(plist-get props :size)
              :isolate ,(if (plist-member props :isolate)
                            (plist-get props :isolate)
                          t)
              :keep ',(plist-get props :keep)
              :hints (pop/format-hints ',(plist-get props :hints))
              :help ',(plist-get props :help)
              :map ,map))
       (defun ,toggle ()
         ,(format "Show or hide the %s popup." name)
         (interactive)
         (pop/toggle ',name)))))

;;;; The popup frame

(defvar pop/frame nil
  "The child frame that holds popups, reused between calls.")

(defvar pop/suppress nil
  "When non-nil, popup buffers are updated but the popup stays hidden.")

(defun pop/live-p ()
  (and pop/frame (frame-live-p pop/frame) t))

(defun pop/visible-p ()
  (and (pop/live-p) (frame-visible-p pop/frame) t))

(defun pop/buffer ()
  "The buffer currently in the popup."
  (and (pop/live-p) (window-buffer (frame-root-window pop/frame))))

(defun pop/current-type ()
  (pop/type-of (pop/buffer)))

(defun pop/main-buffer ()
  "The buffer you're working in in the main frame."
  (window-buffer (frame-selected-window
                  (or (and (pop/live-p) (frame-parent pop/frame))
                      (selected-frame)))))

(defun pop/refuse-split (&rest _)
  (user-error "Popups can't be split"))

(defun pop/make-frame ()
  "Create the hidden popup frame over the main frame."
  (let ((parent (or (frame-parent) (selected-frame))))
    (setq pop/frame
          (make-frame
           `((parent-frame . ,parent)
             (left . 0.5) (top . 0.5)        ; 0.5 = dead center
             (width . ,(car pop/default-size))
             (height . ,(cdr pop/default-size))
             (keep-ratio . t)
             (minibuffer . t)                ; its own minibuffer for prompts
             (unsplittable . t)
             (no-other-frame . t)
             (undecorated . t)
             (child-frame-border-width . ,pop/border-width)
             (visibility . nil))))
    (set-face-background 'child-frame-border pop/border-color pop/frame)
    pop/frame))

(defun pop/resize (type)
  "Size and center the popup for TYPE."
  (let ((size (or (pop/prop type :size) pop/default-size)))
    (modify-frame-parameters pop/frame
                             `((width . ,(car size)) (height . ,(cdr size))
                               (left . 0.5) (top . 0.5)))))

(defun pop/setup-buffer ()
  "Run the current buffer's popup :setup, if it's in the popup."
  (when (and (pop/live-p) (eq (current-buffer) (pop/buffer)))
    (when-let* ((type (pop/type-of (current-buffer))))
      (funcall (pop/prop type :setup)))))

;; Some modes reset buffer-local settings (compile does on every run),
;; so redo the setup whenever a popup buffer changes mode
(add-hook 'after-change-major-mode-hook #'pop/setup-buffer)

(defun pop/display (buffer alist)
  "`display-buffer' action: show BUFFER in the popup frame."
  (unless (pop/live-p) (pop/make-frame))
  (let ((win (frame-root-window pop/frame))
        (type (pop/type-of buffer)))
    (when type (pop/resize type))
    (prog1 (window--display-buffer buffer win 'reuse alist)
      ;; Start where the buffer's cursor is, not where the popup last was,
      ;; so an :open function can position the cursor before showing
      (set-window-point win (with-current-buffer buffer (point)))
      ;; The mode line becomes the type's hint line, or goes away
      (setq pop/hint-offset 0)
      (set-window-parameter win 'mode-line-format
                            (if (and type (pop/prop type :hints))
                                '(:eval (pop/hint-line))
                              'none))
      ;; Every split attempt (C-<return>, :sp, :vs...) asks the window's
      ;; `split-window' parameter first; refuse them all in the popup
      (set-window-parameter win 'split-window #'pop/refuse-split)
      (with-current-buffer buffer (pop/setup-buffer))
      (unless pop/suppress
        (make-frame-visible pop/frame))
      (pop/update-keys))))

(defun pop/capture-p (buffer-or-name &optional _)
  "Non-nil if BUFFER-OR-NAME belongs to a type that captures its buffers."
  (when-let* ((type (pop/type-of (get-buffer buffer-or-name))))
    (pop/prop type :capture)))

(add-to-list 'display-buffer-alist '(pop/capture-p pop/display))

;; If something closes the popup's last window, hide its frame rather
;; than minimizing all of Emacs
(setq iconify-child-frame 'make-invisible)

;;;; Showing and hiding

(defun pop/focus ()
  "Move focus into the popup."
  (select-frame-set-input-focus pop/frame)
  (select-window (frame-root-window pop/frame))
  (pop/update-keys))

(defun pop/hide ()
  "Hide the popup and return focus to the main frame."
  (interactive)
  (when (pop/visible-p)
    (let ((parent (frame-parent pop/frame)))
      (make-frame-invisible pop/frame)
      (select-frame-set-input-focus parent)
      (pop/update-keys))))

(defun pop/escape ()
  "Back out of insert/visual state first; from normal state, hide the popup."
  (interactive)
  (if (memq (bound-and-true-p evil-state) '(insert visual replace operator))
      (evil-force-normal-state)
    (pop/hide)))

(defun pop/toggle (type)
  "Hide the popup if it's showing TYPE; otherwise show TYPE."
  (if (and (pop/visible-p) (eq (pop/current-type) type))
      (pop/hide)
    (let ((buf (if-let* ((open (pop/prop type :open)))
                   (funcall open)
                 (cl-find-if (lambda (b) (eq (pop/type-of b) type))
                             (buffer-list)))))
      (if (not buf)
          (message "No %s buffers yet" type)
        (pop/display buf nil)
        (pop/focus)))))

(defun pop/close-or-delete-window ()
  "In the popup, hide it and kill its buffer; elsewhere, delete the window."
  (interactive)
  (if (not (eq (selected-frame) pop/frame))
      (delete-window)
    (let ((buf (pop/buffer))
          (kill-buffer-query-functions nil))   ; don't ask about running jobs
      (pop/hide)
      (kill-buffer buf))))

;;;; Key layering

(defvar univ-keys-mode)
(defvar univ-keys-map)

(defvar pop/pushed-map nil
  "The keymap currently pushed on top of everything for the popup.")

(defvar pop/full-maps nil
  "Cache of (TYPE . KEYMAP): a type's :keys plus the universal keys it keeps.")

(defun pop/kept-universal-keys (type)
  "Universal keys TYPE keeps: those running pop/ commands, plus :keep."
  (let ((kept (make-sparse-keymap))
        (extra (mapcar #'key-parse (append pop/always-keep
                                           (pop/prop type :keep)))))
    (when (boundp 'univ-keys-map)
      (map-keymap
       (lambda (event cmd)
         (when (or (and (symbolp cmd)
                        (string-prefix-p "pop/" (symbol-name cmd)))
                   (member (vector event) extra))
           (define-key kept (vector event) cmd)))
       univ-keys-map))
    kept))

(defun pop/full-map (type)
  (or (alist-get type pop/full-maps)
      (setf (alist-get type pop/full-maps)
            (make-composed-keymap
             (list (pop/prop type :map)
                   pop/common-map
                   (if (pop/prop type :isolate)
                       (pop/kept-universal-keys type)
                     (make-sparse-keymap)))))))

(defun pop/update-keys (&rest _)
  "Put the right keys on top for wherever focus is now."
  (let* ((in-popup (and (pop/live-p) (eq (selected-frame) pop/frame)))
         (type (and in-popup (pop/current-type)))
         (map (cond ((not in-popup) nil)
                    ((window-minibuffer-p (selected-window)) pop/minibuffer-map)
                    (type (pop/full-map type)))))
    (unless (eq map pop/pushed-map)
      (when pop/pushed-map
        (internal-pop-keymap pop/pushed-map 'overriding-terminal-local-map))
      (when map
        (internal-push-keymap map 'overriding-terminal-local-map))
      (setq pop/pushed-map map))
    ;; Isolated popups switch the universal keys off while they have focus
    (when (boundp 'univ-keys-mode)
      (setq univ-keys-mode (not (and type (pop/prop type :isolate)))))))

(add-hook 'window-selection-change-functions #'pop/update-keys)
(add-hook 'window-buffer-change-functions #'pop/update-keys)
(add-hook 'minibuffer-setup-hook #'pop/update-keys)
(add-hook 'minibuffer-exit-hook #'pop/update-keys)

(defun pop/reset-keys ()
  "Rebuild cached popup keymaps, e.g. after changing your universal keys."
  (interactive)
  (setq pop/full-maps nil)
  (pop/update-keys))

;;;; Key reference

;; ? in a popup swaps in a sheet of its :help, laid out in columns;
;; ?, escape or q bring back what was there

(defface pop/keys-title '((t :inherit font-lock-function-name-face :weight bold :height 1.3))
  "Face for the key reference's title.")

(defface pop/keys-heading '((t :inherit font-lock-type-face :weight bold))
  "Face for a group heading in the key reference.")

(defface pop/keys-key '((t :inherit font-lock-keyword-face :weight bold))
  "Face for a key in the key reference.")

(define-derived-mode pop/keys-mode special-mode "Keys"
  "A popup's key reference."
  (setq-local cursor-type nil
              truncate-lines t))

(defvar pop/keys-return nil
  "The popup buffer the key reference was opened from.")

(defun pop/keys-block (section key-width)
  "Lines for SECTION (HEADING KEY TEXT ...), keys padded to KEY-WIDTH."
  (cons (propertize (car section) 'face 'pop/keys-heading)
        (mapcar (lambda (pair)
                  (concat (propertize (string-pad (car pair) key-width)
                                      'face 'pop/keys-key)
                          "  " (cadr pair)))
                (seq-split (cdr section) 2))))

(defun pop/insert-keys (title sections width)
  "Insert TITLE and SECTIONS as a grid of blocks fitting WIDTH columns."
  (let* ((key-width (apply #'max (mapcar (lambda (s)
                                           (apply #'max (mapcar #'length
                                                                (seq-map #'car (seq-split (cdr s) 2)))))
                                         sections)))
         (blocks (mapcar (lambda (s) (pop/keys-block s key-width)) sections))
         (col-width (+ 4 (apply #'max (mapcar #'string-width (apply #'append blocks)))))
         (cols (max 1 (/ (- width 2) col-width))))
    (insert "\n " (propertize title 'face 'pop/keys-title) "\n\n")
    (dolist (row (seq-split blocks cols))
      (dotimes (i (apply #'max (mapcar #'length row)))
        (insert "  ")
        (dolist (block row)
          (insert (string-pad (or (nth i block) "") col-width)))
        (delete-horizontal-space)
        (insert "\n"))
      (insert "\n"))))

(defun pop/show-keys ()
  "Show the current popup's full key reference."
  (interactive)
  (let ((type (pop/current-type)))
    (if-let* ((help (pop/prop type :help)))
        (let ((buf (get-buffer-create "*popup keys*")))
          (setq pop/keys-return (pop/buffer))
          (with-current-buffer buf (pop/keys-mode))
          (pop/display buf nil)
          (pop/focus)
          (with-current-buffer buf
            (let ((inhibit-read-only t))
              (erase-buffer)
              (pop/insert-keys (format "%s keys" (capitalize (symbol-name type)))
                               help
                               (window-body-width (frame-root-window pop/frame))))
            (goto-char (point-min))))
      (message "No key reference for this popup"))))

(defun pop/keys-back ()
  "Leave the key reference for the popup it was opened from."
  (interactive)
  (if (buffer-live-p pop/keys-return)
      (progn (pop/display pop/keys-return nil)
             (pop/focus))
    (pop/hide)))

(pop/define keys
  :match (derived-mode-p 'pop/keys-mode)
  :keys  ("?"        pop/keys-back
          "<escape>" pop/keys-back
          "q"        pop/keys-back)
  :hints ("?/esc" "back"  "j/k" "scroll"))

(provide 'popup)
