;;; editing.el --- evil and editing commands -*- lexical-binding: t -*-

;;; Evil
(use-package evil
  :init
  ;; These must be set before evil loads
  (setq evil-want-keybinding nil      ; leave other modes' maps alone
        evil-want-C-u-scroll t        ; C-u scrolls up, like vim
        evil-want-Y-yank-to-eol t     ; Y behaves like y$
        evil-undo-system 'undo-redo   ; built-in redo for C-r
        evil-split-window-below t     ; :sp opens below
        evil-vsplit-window-right t    ; :vs opens right
        evil-echo-state nil)          ; no -- INSERT -- in the echo area
  :config
  (evil-mode 1)
  (evil-define-key 'visual 'global
    "-"   #'evil-join
    "C"   #'comment-or-uncomment-region
    (kbd "SPC") #'my/cursors-at-line-starts
    "J"   #'my/move-lines-down
    "K"   #'my/move-lines-up
    "f"   #'my/fold-selection
    "F"   #'my/unfold-selection)
  (evil-define-key 'normal 'global
    "-" #'evil-join
    "C" #'comment-line
    "L" #'evil-multiedit-match-and-next
    "F" #'vimish-fold-delete
    ;; Tab toggles the fold under the cursor, in code only, so Tab keeps
    ;; its own job elsewhere (org, popups...)
    (kbd "<tab>") `(menu-item "" vimish-fold-toggle
                              :filter ,(lambda (cmd)
                                         (when (derived-mode-p 'prog-mode)
                                           cmd)))
    ;; f does too, but only on a fold, so f<char> still finds a character
    ;; everywhere else
    "f" `(menu-item "" vimish-fold-toggle
                    :filter ,(lambda (cmd)
                               (when (my/fold-at-point-p)
                                 cmd)))))

(defun my/fold-at-point-p ()
  "Non-nil if the cursor is on a fold, folded or open."
  (seq-some (lambda (ov)
              (memq (overlay-get ov 'type)
                    '(vimish-fold--folded vimish-fold--unfolded)))
            (overlays-at (point))))

(use-package evil-multiedit            ; L: edit every match of the word at once
  :after evil
  :commands evil-multiedit-match-and-next)

;; Multiple cursors: SPC on a visual selection puts a cursor at the start
;; of each line; entering visual mode again collapses back to one
(use-package evil-mc
  :after evil
  :init
  (setq evil-mc-key-map (make-sparse-keymap)) ; none of its default keys
  :config
  (global-evil-mc-mode 1)
  (add-hook 'evil-visual-state-entry-hook
            (lambda ()
              (unless (evil-mc-executing-command-p)
                (evil-mc-undo-all-cursors)))))

(declare-function evil-mc-make-cursor-in-visual-selection "evil-mc-cursor-make")

(evil-define-command my/cursors-at-line-starts ()
  "Put a cursor at the start of every selected line, in normal state."
  :repeat ignore
  :evil-mc t
  (when (evil-visual-state-p)
    (evil-mc-make-cursor-in-visual-selection t)
    (evil-normal-state)))

;; Moving the selected lines with J/K: the whole lines the selection
;; touches move past their neighbour, and the selection moves with them
(defun my/move-lines (n)
  "Move the lines of the visual selection N lines down (up if negative)."
  (let* ((beg (save-excursion (goto-char evil-visual-beginning)
                              (line-beginning-position)))
         (end (save-excursion (goto-char (max beg (1- evil-visual-end)))
                              (line-beginning-position 2)))
         (mark-off (- evil-visual-mark beg))
         (point-off (- evil-visual-point beg))
         (type (evil-visual-type)))
    (unless (= (if (< n 0) beg end) (if (< n 0) (point-min) (point-max)))
      (let ((text (delete-and-extract-region beg end)))
        (goto-char beg)
        ;; The last line has no newline: borrow the one before it
        (unless (string-suffix-p "\n" text)
          (setq text (concat text "\n"))
          (delete-char -1))
        (forward-line n)
        ;; Moving onto the last line, which has no newline: give it one
        (when (and (eobp) (not (bolp)))
          (insert "\n")
          (setq text (substring text 0 -1)))
        (let ((new (point)))
          (insert text)
          (evil-visual-make-selection (+ new mark-off) (+ new point-off) type)
          (setq deactivate-mark nil))))))

(defun my/move-lines-down ()
  "Move the selected lines down one."
  (interactive)
  (my/move-lines 1))

(defun my/move-lines-up ()
  "Move the selected lines up one."
  (interactive)
  (my/move-lines -1))

;; Folding: f folds the selected lines, Tab opens and closes a fold, F
;; removes folds for good.  Folds last until the buffer is closed.
(use-package vimish-fold
  :commands (vimish-fold vimish-fold-toggle vimish-fold-delete))

(declare-function vimish-fold--folds-in "vimish-fold")
(declare-function vimish-fold--delete "vimish-fold")

(defun my/fold-selection ()
  "Fold the lines of the visual selection."
  (interactive)
  ;; A line selection ends just past its last newline, which vimish-fold
  ;; would round up to the whole next line; end on the last line instead
  (vimish-fold evil-visual-beginning
               (max evil-visual-beginning (1- evil-visual-end)))
  (evil-normal-state))

(defun my/unfold-selection ()
  "Remove every fold the visual selection touches."
  (interactive)
  (require 'vimish-fold)
  (mapc #'vimish-fold--delete
        (vimish-fold--folds-in evil-visual-beginning evil-visual-end))
  (evil-normal-state))

(use-package evil-collection
  :after evil
  :config
  (setq evil-collection-mode-list '(dired ibuffer corfu helpful))
  (evil-collection-init))

(provide 'editing)
