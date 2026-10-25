;;; universal.el --- keys that work everywhere -*- lexical-binding: t -*-

(defun univ/spawn-window ()
  "Split to the right and open dired in the new window."
  (interactive)
  (select-window (split-window-right))
  (dired default-directory))

(defun univ/zoom-reset ()
  "Reset text scale in the current buffer."
  (interactive)
  (text-scale-set 0))

(defun univ/outside-minibuffer (command)
  "A binding for COMMAND that steps aside while completing.
That is, in the minibuffer and while an autocompletion popup is up,
so keys like C-j/C-k move through candidates there instead."
  `(menu-item "" ,command
              :filter ,(lambda (cmd)
                         (unless (or (minibufferp)
                                     (bound-and-true-p completion-in-region-mode))
                           cmd))))

(defun univ/grow-window ()
  "Make the current window wider."
  (interactive)
  (enlarge-window-horizontally 4))

(defun univ/shrink-window ()
  "Make the current window narrower."
  (interactive)
  (shrink-window-horizontally 4))

(defun univ/grow-window-tall ()
  "Make the current window taller."
  (interactive)
  (enlarge-window 2))

(defun univ/shrink-window-tall ()
  "Make the current window shorter."
  (interactive)
  (shrink-window 2))

(defvar-keymap univ-search-map
  :doc "M-s: search."
  "M-f" #'find-file       ; a file, anywhere in the project
  "M-d" #'consult-line            ; text in this document
  "M-i" #'consult-imenu           ; search defined fns
  "M-I" #'consult-eglot-symbols   ; search project symbols
  "M-p" #'consult-ripgrep)        ; text anywhere in the project

(defvar-keymap univ-keys-map
  ;; Windows
  "C-h"   (univ/outside-minibuffer #'windmove-left)
  "C-j"   (univ/outside-minibuffer #'windmove-down)
  "C-k"   (univ/outside-minibuffer #'windmove-up)
  "C-l"   (univ/outside-minibuffer #'windmove-right)
  "C-S-h" #'windmove-swap-states-left
  "C-S-j" #'windmove-swap-states-down
  "C-S-k" #'windmove-swap-states-up
  "C-S-l" #'windmove-swap-states-right
  "C-]"   #'window-layout-transpose  ; side-by-side <-> stacked
  "C-<right>" (univ/outside-minibuffer #'univ/grow-window)
  "C-<left>"  (univ/outside-minibuffer #'univ/shrink-window)
  "C-<up>"    (univ/outside-minibuffer #'univ/grow-window-tall)
  "C-<down>"  (univ/outside-minibuffer #'univ/shrink-window-tall)
  "C-x"   #'pop/close-or-delete-window
  "C-<return>" #'univ/spawn-window
  ;; Zoom
  "C-="   #'text-scale-increase
  "C--"   #'text-scale-decrease
  "C-0"   #'univ/zoom-reset
  ;; Searching
  "M-s"   univ-search-map ; M-s M-f file, M-s M-d document, M-s M-p project
  )

;; Escape cancels any prompt immediately (popups handle it in popup.el)
;; Popups are on F-keys; see modeline.el
(keymap-set minibuffer-local-map "<escape>" #'abort-minibuffers)

(define-minor-mode univ-keys-mode
  "Global keys that take priority over all other keymaps."
  :global t
  :keymap univ-keys-map)

(univ-keys-mode 1)
(add-to-list 'emulation-mode-map-alists
             `((univ-keys-mode . ,univ-keys-map)))

(provide 'universal)
