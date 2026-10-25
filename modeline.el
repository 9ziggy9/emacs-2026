;;; modeline.el --- the mode line and its F-key slots -*- lexical-binding: t -*-

;; The mode line shows numbered slots on the right: slot N is always F<N>.
;; Each major mode can declare its own slots in `ml/mode-slots'; any other
;; mode gets `ml/default-slots'.  F-keys follow the buffer you're working
;; in, even while a popup has focus, so pressing a popup's key again hides
;; it.  F-keys with no slot keep their usual binding (e.g. F11 fullscreen).

(require 'cl-lib)
(require 'popup)

;;;; Slots

(defvar ml/default-slots
  '(("compile" . pop/compile-toggle)
    ("dired"   . pop/dired-toggle)
    ("ibuffer" . pop/ibuffer-toggle))
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

;; Evil state badges: each borrows a font-lock color, inverted into a pill,
;; so they follow whatever theme is loaded
(defface ml/evil-base     '((t :inverse-video t :weight bold :height 0.85)) "")
(defface ml/evil-normal   '((t :inherit (ml/evil-base font-lock-keyword-face)))  "")
(defface ml/evil-insert   '((t :inherit (ml/evil-base font-lock-string-face)))   "")
(defface ml/evil-visual   '((t :inherit (ml/evil-base font-lock-constant-face))) "")
(defface ml/evil-replace  '((t :inherit (ml/evil-base font-lock-warning-face)))  "")
(defface ml/evil-operator '((t :inherit (ml/evil-base font-lock-type-face)))     "")
(defface ml/evil-other    '((t :inherit (ml/evil-base font-lock-comment-face)))  "")

(defun ml/evil-state-tag ()
  "The current evil state as a colored badge, e.g. \" INSERT \"."
  (when (bound-and-true-p evil-state)
    (propertize (format " %s " (upcase (symbol-name evil-state)))
                'face (pcase evil-state
                        ('normal   'ml/evil-normal)
                        ('insert   'ml/evil-insert)
                        ('visual   'ml/evil-visual)
                        ('replace  'ml/evil-replace)
                        ('operator 'ml/evil-operator)
                        (_         'ml/evil-other)))))

;;;; The mode line

(let ((old (default-value 'mode-line-format)))
  (setq-default mode-line-format
                '(" " (:eval (ml/evil-state-tag))
                  " " mode-line-buffer-identification
                  mode-line-format-right-align
                  (:eval (ml/slots-segment))))
  ;; Buffers made before now (*scratch*, *Messages*...) hold their own copy
  ;; of the old default; bring those along too
  (dolist (buf (buffer-list))
    (with-current-buffer buf
      (when (equal mode-line-format old)
        (setq mode-line-format (default-value 'mode-line-format))))))

(provide 'modeline)
