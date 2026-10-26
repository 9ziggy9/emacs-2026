;;; init.el --- -*- lexical-binding: t -*-

;; UI cleanup, no-litter settings, custom-file
(load (locate-user-emacs-file "clean") nil t)

;; Packages are initialized automatically before init.el
(setq use-package-always-ensure t)

;; Revert buffers when files change on disk (e.g. git branch switch)
(global-auto-revert-mode 1)

;; Order matters: universal.el must come after evil (editing), and the
;; mode line after universal; files that define popups come after popup
(dolist (file '("editing"      ; evil and editing commands
                "completion"   ; minibuffer, M-x, autocompletion
                "popup"        ; the popup framework
                "universal"    ; keys that override everything
                "modeline"     ; the mode line, with F-key slots
                "ui"           ; looks, windows, dired/ibuffer, popups
                "langs"))      ; indentation, C, eglot, compiling
  (load (locate-user-emacs-file file) nil t))
