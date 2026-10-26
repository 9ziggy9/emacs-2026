;;; modeline.el --- the mode line and its F-key slots -*- lexical-binding: t -*-

;; The mode line shows numbered slots on the right: slot N is always F<N>.
;; Each major mode can declare its own slots in `ml/mode-slots'; any other
;; mode gets `ml/default-slots'.  F-keys follow the buffer you're working
;; in, even while a popup has focus, so pressing a popup's key again hides
;; it.  F-keys with no slot keep their usual binding (e.g. F11 fullscreen).

(require 'cl-lib)
(require 'popup (locate-user-emacs-file "popup"))
(require 'universal (locate-user-emacs-file "universal"))

;;;; Slots

(defvar ml/default-slots
  '(("compile" . pop/compile-toggle)
    ("dired"   . pop/dired-toggle)
    ("ibuffer" . pop/ibuffer-toggle)
    ("tree"    . univ/toggle-treemacs)
    ("readme"  . pop/readme-toggle)
    ("wm"      . pop/wm-toggle))
  "Slots (LABEL . COMMAND) for modes without their own; the first is F1.
A nil entry leaves that slot empty.")

(defvar ml/mode-slots nil
  "Alist of (MODE . SLOTS); the first MODE the buffer derives from wins.
Its SLOTS replace `ml/default-slots', e.g.

  (add-to-list \\='ml/mode-slots
               `(c-ts-mode ,@ml/default-slots (\"format\" . eglot-format)))")

(defun ml/slots (&optional buffer)
  "The slots for BUFFER (default: the current buffer)."
  (with-current-buffer (or buffer (current-buffer))
    (or (cdr (cl-find-if (lambda (entry) (derived-mode-p (car entry)))
                         ml/mode-slots))
        ml/default-slots)))

(defun ml/slot-command (n)
  "The command in slot N (1-based) for the buffer you're working in."
  (cdr (nth (1- n) (ml/slots (pop/main-buffer)))))

;; F1..F12 run their slot; an empty slot makes the binding vanish, so the
;; key falls through to whatever it normally does
(dotimes (i 12)
  (let ((n (1+ i)))
    (keymap-set univ-keys-map (format "<f%d>" n)
                `(menu-item "" ignore
                            :filter ,(lambda (_) (ml/slot-command n))))))

;; Popups are isolated from the universal keys; let the F-keys through
(setq pop/always-keep
      (append pop/always-keep
              (cl-loop for n from 1 to 12 collect (format "<f%d>" n))))
(pop/reset-keys)

;;;; Segments

;; The slots sit in their own band, a shade off the mode line's background;
;; padding keeps full height so the band fills the bar, labels are smaller
(defface ml/slots-band '((t)) "Background band behind the slots.")
(defface ml/slot '((t :inherit ml/slots-band :height 0.85)) "A slot's label.")

(defun ml/update-slots-band (&rest _)
  "Shade the slots band from the current theme's mode-line background."
  (let ((bg (face-background 'mode-line nil t)))
    (when (color-defined-p bg)
      (set-face-background 'ml/slots-band
                           (if (color-dark-p (color-name-to-rgb bg))
                               (color-lighten-name bg 12)
                             (color-darken-name bg 6))))))

(ml/update-slots-band)
(add-hook 'enable-theme-functions #'ml/update-slots-band)

;; A slimmer bar: smaller text makes the whole line thinner.  Themes reset
;; the mode-line faces when they load, so redo it after each one.
(defvar ml/height 0.85 "Mode-line text size, relative to buffer text.")

(defun ml/shrink-mode-line (&rest _)
  "Apply `ml/height' to the mode-line faces."
  (dolist (face '(mode-line mode-line-inactive))
    (set-face-attribute face nil :height ml/height)))

(ml/shrink-mode-line)
(add-hook 'enable-theme-functions #'ml/shrink-mode-line)

(defun ml/click-map (command)
  "A mode-line keymap running COMMAND on mouse-1."
  (let ((map (make-sparse-keymap)))
    (keymap-set map "<mode-line> <mouse-1>" command)
    map))

(defun ml/slots-segment ()
  "The current buffer's slot labels, e.g. \"compile  dired\", clickable."
  (let ((pad (propertize "  " 'face 'ml/slots-band)))
    (concat
     pad
     (string-join
      (cl-loop for (label . cmd) in (ml/slots)
               for n from 1
               when label
               collect (propertize label
                                   'face 'ml/slot
                                   'mouse-face 'mode-line-highlight
                                   'help-echo (format "F%d or mouse-1: %s" n cmd)
                                   'local-map (ml/click-map cmd)))
      pad)
     pad)))

;; Unsaved changes: a dot after the file name
(defun ml/modified-marker ()
  "\" ●\" while a file-visiting buffer has unsaved changes."
  (when (and buffer-file-name (buffer-modified-p))
    (propertize " ●" 'face 'warning)))

;; Git branch, from vc-mode's " Git-main" / " Git:main"
(defvar vc-mode)

(defun ml/git-branch ()
  "The current git branch, dimmed, e.g. \"    main\"."
  (when (and vc-mode (string-match "Git[-:!?@]\\(.+\\)" vc-mode))
    (propertize (concat "    " (match-string 1 vc-mode))
                'face 'shadow)))

;; Diagnostics: error and warning counts wherever flymake is checking
;; (eglot turns it on), or a check mark when there are none
(declare-function flymake-diagnostics "flymake")
(declare-function flymake-diagnostic-type "flymake")
(declare-function flymake--severity "flymake")

(defun ml/diagnostics ()
  "E.g. \"✗ 2  ⚠ 3  \", colored; nil where flymake isn't on."
  (when (bound-and-true-p flymake-mode)
    (let ((errors 0) (warnings 0))
      (dolist (diag (flymake-diagnostics))
        (let ((severity (flymake--severity (flymake-diagnostic-type diag))))
          (cond ((>= severity (warning-numeric-level :error))   (cl-incf errors))
                ((>= severity (warning-numeric-level :warning)) (cl-incf warnings)))))
      (if (= 0 errors warnings)
          (propertize "✓  " 'face 'success)
        (concat (if (> errors 0) (propertize (format "✗ %d  " errors) 'face 'error) "")
                (if (> warnings 0) (propertize (format "⚠ %d  " warnings) 'face 'warning) ""))))))

;;;; The mode line

(let ((old (default-value 'mode-line-format)))
  (setq-default mode-line-format
                '(" " mode-line-buffer-identification
                  (:eval (ml/modified-marker))
                  (:eval (ml/git-branch))
                  mode-line-format-right-align
                  (:eval (ml/diagnostics))
                  (:propertize "%l:%C  " face shadow)   ; line:column
                  (:eval (ml/slots-segment))))
  ;; Buffers made before now (*scratch*, *Messages*...) hold their own copy
  ;; of the old default; bring those along too
  (dolist (buf (buffer-list))
    (with-current-buffer buf
      (when (equal mode-line-format old)
        (setq mode-line-format (default-value 'mode-line-format))))))

(provide 'modeline)
