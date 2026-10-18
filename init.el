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
