;;; universal.el --- keys that work everywhere -*- lexical-binding: t -*-

(require 'popup (locate-user-emacs-file "popup"))

(defun univ/spawn-window ()
  "Split to the right, showing the current buffer in the new window too."
  (interactive)
  (select-window (split-window-right)))

(declare-function pdf-view-enlarge "pdf-view")
(declare-function pdf-view-shrink "pdf-view")
(declare-function pdf-view-fit-width-to-window "pdf-view")
(defvar pdf-view-resize-factor)

;; Zoom: text size, or in a PDF, the page
(defun univ/zoom-in ()
  "Make the text bigger, or zoom into the PDF."
  (interactive)
  (if (derived-mode-p 'pdf-view-mode)
      (pdf-view-enlarge pdf-view-resize-factor)
    (text-scale-increase 1)))

(defun univ/zoom-out ()
  "Make the text smaller, or zoom out of the PDF."
  (interactive)
  (if (derived-mode-p 'pdf-view-mode)
      (pdf-view-shrink pdf-view-resize-factor)
    (text-scale-decrease 1)))

(defun univ/zoom-reset ()
  "Reset text scale in the current buffer, or fit the PDF to the width."
  (interactive)
  (if (derived-mode-p 'pdf-view-mode)
      (pdf-view-fit-width-to-window)
    (text-scale-set 0)))

(defun univ/outside-minibuffer (command)
  "A binding for COMMAND that steps aside while completing.
That is, in the minibuffer and while an autocompletion popup is up,
so keys like C-j/C-k move through candidates there instead."
  `(menu-item "" ,command
              :filter ,(lambda (cmd)
                         (unless (or (minibufferp)
                                     (bound-and-true-p completion-in-region-mode))
                           cmd))))

(defun univ/in-file-buffer (command)
  "A binding for COMMAND only in buffers visiting a file, and treemacs.
Anywhere else (popups, the minibuffer, *scratch*...) the key falls
through to its usual binding."
  `(menu-item "" ,command
              :filter ,(lambda (cmd)
                         (when (or buffer-file-name
                                   (derived-mode-p 'treemacs-mode))
                           cmd))))

(declare-function treemacs-current-visibility "treemacs")
(declare-function treemacs-get-local-window "treemacs")
(declare-function treemacs-add-and-display-current-project-exclusively "treemacs")

(defun univ/toggle-treemacs ()
  "Show this file's project in treemacs, or hide treemacs if it's showing.
From a popup, the popup closes and this acts on the main frame."
  (interactive)
  (require 'treemacs)
  (when (eq (selected-frame) pop/frame)
    (pop/hide))
  (with-current-buffer (window-buffer (selected-window))
    (cond ((eq (treemacs-current-visibility) 'visible)
           (delete-window (treemacs-get-local-window)))
          ((not buffer-file-name)
           (user-error "Treemacs opens from a buffer visiting a file"))
          (t
           (treemacs-add-and-display-current-project-exclusively)))))

;; Buffer cycling skips anything not visiting a file (compilation,
;; dired, *Warnings*...), so it only steps through your code
(defun univ/skip-non-file-buffer (_window buffer _bury-or-kill)
  (not (buffer-file-name buffer)))

(defun univ/previous-file-buffer ()
  "Switch to the previous buffer that visits a file."
  (interactive)
  (let ((switch-to-prev-buffer-skip #'univ/skip-non-file-buffer))
    (previous-buffer)))

(defun univ/next-file-buffer ()
  "Switch to the next buffer that visits a file."
  (interactive)
  (let ((switch-to-prev-buffer-skip #'univ/skip-non-file-buffer))
    (next-buffer)))

;; Fullscreen, tiling-WM style: the window takes the whole frame (treemacs
;; too), and toggling again puts the old layout back.  Whatever you did in
;; the window meanwhile (moving point, switching buffer) carries over.

(defun univ/toggle-fullscreen-window ()
  "Make the selected window fill the frame, or restore the previous layout."
  (interactive)
  (let ((saved (frame-parameter nil 'univ/fullscreen-config)))
    (cond (saved
           (let ((buf (current-buffer))
                 (pt (point)))
             (set-frame-parameter nil 'univ/fullscreen-config nil)
             (set-window-configuration saved)
             (switch-to-buffer buf nil t)
             (goto-char pt)))
          ((one-window-p t)
           (message "Already the only window"))
          (t
           (set-frame-parameter nil 'univ/fullscreen-config
                                (current-window-configuration))
           (let ((ignore-window-parameters t)) ; side windows too
             (delete-other-windows))))))

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
  "C-f"   (univ/outside-minibuffer #'univ/toggle-fullscreen-window)
  "C-<right>" (univ/outside-minibuffer #'univ/grow-window)
  "C-<left>"  (univ/outside-minibuffer #'univ/shrink-window)
  "C-<up>"    (univ/outside-minibuffer #'univ/grow-window-tall)
  "C-<down>"  (univ/outside-minibuffer #'univ/shrink-window-tall)
  "C-x"   #'pop/close-or-delete-window
  ;; In treemacs, C-<return> opens the file at point in a split instead
  "C-<return>" `(menu-item "" univ/spawn-window
                           :filter ,(lambda (cmd)
                                      (unless (derived-mode-p 'treemacs-mode)
                                        cmd)))
  "C-t"   (univ/in-file-buffer #'univ/toggle-treemacs)
  ;; Buffers
  "C-,"   (univ/outside-minibuffer #'univ/previous-file-buffer)
  "C-."   (univ/outside-minibuffer #'univ/next-file-buffer)
  ;; Zoom
  "C-="   #'univ/zoom-in
  "C--"   #'univ/zoom-out
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

;; These keys must come before evil's in `emulation-mode-map-alists'.
;; Evil puts its own in front the first time it's turned on in a
;; buffer, so move ours back in front whenever it is; then it doesn't
;; matter whether this file loads before or after evil
(defvar univ-keys-alist `((univ-keys-mode . ,univ-keys-map)))

(defun univ/keys-first ()
  "Put the universal keys at the front of `emulation-mode-map-alists'."
  (setq emulation-mode-map-alists
        (cons univ-keys-alist (delq univ-keys-alist emulation-mode-map-alists))))

(univ/keys-first)
(add-hook 'evil-local-mode-hook #'univ/keys-first)

(provide 'universal)
