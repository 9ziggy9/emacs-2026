;;; init.el --- -*- lexical-binding: t -*-

;; UI cleanup, no-litter settings, custom-file
(load (locate-user-emacs-file "clean") nil t)

;; Packages are initialized automatically before init.el
(setq use-package-always-ensure t)

;; Revert buffers when files change on disk (e.g. git branch switch)
(global-auto-revert-mode 1)

;; The rest of the config, in any order: each file requires what it
;; needs, so whichever loads first pulls in its dependencies
(dolist (feature '(editing      ; evil and editing commands
                   completion   ; minibuffer, M-x, autocompletion
                   ui           ; looks, windows, dired/ibuffer, popups
                   langs        ; indentation, C, eglot, compiling
                   popup        ; the popup framework
                   universal    ; keys that override everything
                   modeline))   ; the mode line, with F-key slots
  (require feature (locate-user-emacs-file (symbol-name feature))))
