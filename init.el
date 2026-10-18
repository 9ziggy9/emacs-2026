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
