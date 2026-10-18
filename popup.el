;;; popup.el --- framework for Quake-style floating popups -*- lexical-binding: t -*-

;; Popup types are declared with `pop/define' (see popups.el).  All types
;; share one centered child frame; showing a different type swaps its
;; content and size.  While a popup has focus, keys are looked up in this
;; order:
;;
;;   1. the popup type's own :keys (beats everything, evil included)
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
:keys (KEY COMMAND ...)  bindings that beat everything in this popup"
  (let ((map (intern (format "pop/%s-map" name)))
        (toggle (intern (format "pop/%s-toggle" name)))
        (keys (plist-get props :keys)))
    `(progn
       (defvar ,map nil)
       (setq ,map (define-keymap
                    ,@(cl-loop for (key cmd) on keys by #'cddr
                               append (list key `#',cmd))))
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
      (set-window-parameter win 'mode-line-format 'none)
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

(provide 'popup)
