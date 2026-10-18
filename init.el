;;; init.el --- -*- lexical-binding: t -*-

;; UI cleanup, no-litter settings, custom-file
(load (locate-user-emacs-file "clean") nil t)

;; Packages are initialized automatically before init.el
(setq use-package-always-ensure t)

;; Revert buffers when files change on disk (e.g. git branch switch)
(global-auto-revert-mode 1)

;; Indentation
(setq-default indent-tabs-mode nil
              tab-width 2
              c-basic-offset 2
              standard-indent 2)

;; Fill column
(setq-default fill-column 80)
(global-display-fill-column-indicator-mode 1)

;; Line numbers
(setq display-line-numbers-type 'relative)
(add-hook 'prog-mode-hook #'display-line-numbers-mode)

;;; Evil
(use-package evil
  :init
  ;; These must be set before evil loads
  (setq evil-want-keybinding nil      ; leave other modes' maps alone
        evil-want-C-u-scroll t        ; C-u scrolls up, like vim
        evil-want-Y-yank-to-eol t     ; Y behaves like y$
        evil-undo-system 'undo-redo   ; built-in redo for C-r
        evil-split-window-below t     ; :sp opens below
        evil-vsplit-window-right t)   ; :vs opens right
  :config
  (evil-mode 1))

(use-package evil-collection
  :after evil
  :config
  (setq evil-collection-mode-list '(dired))
  (evil-collection-init))

;;; Windows
(use-package window
  :ensure nil
  :preface
  (defun my/spawn-window ()
    "Split to the right and open dired in the new window."
    (interactive)
    (select-window (split-window-right))
    (dired default-directory))
  :custom
  (window-combination-resize t))

;;; Dired
(use-package dired
  :ensure nil
  :custom
  (dired-kill-when-opening-new-dired-buffer t))

;;; Zoom
(use-package face-remap
  :ensure nil
  :preface
  (defun my/zoom-reset () (interactive) (text-scale-set 0))
  :bind
  (("C-=" . text-scale-increase)
   ("C--" . text-scale-decrease)
   ("C-0" . my/zoom-reset)))

;;; Priority keys: beat every mode map and evil state
(defvar-keymap my-keys-map
  "C-h"   #'windmove-left
  "C-j"   #'windmove-down
  "C-k"   #'windmove-up
  "C-l"   #'windmove-right
  "C-S-h" #'windmove-swap-states-left
  "C-S-j" #'windmove-swap-states-down
  "C-S-k" #'windmove-swap-states-up
  "C-S-l" #'windmove-swap-states-right
  "C-q"   #'delete-window
  "C-RET" #'my/spawn-window)

(define-minor-mode my-keys-mode
  "Global keys that take priority over all other keymaps."
  :global t
  :keymap my-keys-map)

(my-keys-mode 1)
(add-to-list 'emulation-mode-map-alists
             `((my-keys-mode . ,my-keys-map)))
