;;; early-init.el --- -*- lexical-binding: t -*-

;; Set before the first frame exists: no bar flash, no font resize jump
(setq default-frame-alist
      '((menu-bar-lines . 0)
        (tool-bar-lines . 0)
        (vertical-scroll-bars)
        (font . "Iosevka Nerd Font-14")))
(setq frame-inhibit-implied-resize t)

;; Fewer garbage collections during startup, restored afterward
(setq gc-cons-threshold most-positive-fixnum)
(add-hook 'emacs-startup-hook
          (lambda () (setq gc-cons-threshold (* 16 1024 1024))))

(setq package-archives '(("melpa" . "https://melpa.org/packages/")
                         ("gnu"   . "https://elpa.gnu.org/packages/"))
      load-prefer-newer t)
