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

(defun univ/popper-center (buffer alist)
  "Show popups in a centered floating frame, half the size of the main one."
  (display-buffer-in-child-frame
   buffer
   (append alist
           '((child-frame-parameters
              . ((left . 0.25) (top . 0.25)       ; centered
                 (width . 0.5) (height . 0.5)     ; 50% of the frame
                 (keep-ratio . t)                 ; follow frame resizes
                 (minibuffer . nil)               ; use the main minibuffer
                 (unsplittable . t)
                 (no-other-frame . t)
                 (child-frame-border-width . 2)))))))

(defvar-keymap univ-keys-map
  ;; Windows
  "C-h"   #'windmove-left
  "C-j"   #'windmove-down
  "C-k"   #'windmove-up
  "C-l"   #'windmove-right
  "C-S-h" #'windmove-swap-states-left
  "C-S-j" #'windmove-swap-states-down
  "C-S-k" #'windmove-swap-states-up
  "C-S-l" #'windmove-swap-states-right
  "C-x"   #'delete-window
  "C-<return>" #'univ/spawn-window
  ;; Zoom
  "C-="   #'text-scale-increase
  "C--"   #'text-scale-decrease
  "C-0"   #'univ/zoom-reset
  ;; Popups
  "C-'"   #'popper-toggle        ; show/hide the dropdown
  "M-'"   #'popper-cycle         ; next popup buffer
  "C-M-'" #'popper-toggle-type   ; promote a popup to a normal window, or back
  )

(define-minor-mode univ-keys-mode
  "Global keys that take priority over all other keymaps."
  :global t
  :keymap univ-keys-map)

(univ-keys-mode 1)
(add-to-list 'emulation-mode-map-alists
             `((univ-keys-mode . ,univ-keys-map)))

(provide 'universal)
