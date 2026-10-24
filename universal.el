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
  "A binding for COMMAND that steps aside in the minibuffer.
Lets keys like C-j/C-k move through completion candidates there."
  `(menu-item "" ,command :filter ,(lambda (cmd) (unless (minibufferp) cmd))))

(defvar-keymap univ-search-map
  :doc "M-s: search."
  "M-f" #'find-file       ; a file, anywhere in the project
  "M-d" #'consult-line            ; text in this document
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
  "C-x"   #'pop/close-or-delete-window
  "C-<return>" #'univ/spawn-window
  ;; Zoom
  "C-="   #'text-scale-increase
  "C--"   #'text-scale-decrease
  "C-0"   #'univ/zoom-reset
  ;; Popups
  "C-c"   #'pop/compile-toggle
  "C-/"   #'pop/dired-toggle
  ;; Buffer management
  "C-b"   #'pop/ibuffer-toggle
  ;; Searching
  "M-s"   univ-search-map ; M-s M-f file, M-s M-d document, M-s M-p project
  )

;; Escape cancels any prompt immediately (popups handle it in popup.el)
(keymap-set minibuffer-local-map "<escape>" #'abort-minibuffers)

(define-minor-mode univ-keys-mode
  "Global keys that take priority over all other keymaps."
  :global t
  :keymap univ-keys-map)

(univ-keys-mode 1)
(add-to-list 'emulation-mode-map-alists
             `((univ-keys-mode . ,univ-keys-map)))

(provide 'universal)
