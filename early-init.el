;;; early-init.el --- -*- lexical-binding: t -*-

;; Set before the first frame exists: no bar flash, no font resize jump
(setq default-frame-alist
      '((menu-bar-lines . 0)
        (tool-bar-lines . 0)
        (vertical-scroll-bars)
        (font . "Iosevka Nerd Font-14")))
(setq frame-inhibit-implied-resize t)

;; New frames open in the theme's colors instead of flashing white until the
;; theme is applied; theme-select writes them as ("#background" . "#text")
(let ((colors (ignore-errors (with-temp-buffer
                               (insert-file-contents (locate-user-emacs-file "theme-colors"))
                               (read (current-buffer))))))
  (when (and (consp colors) (stringp (car colors)) (stringp (cdr colors)))
    (push (cons 'background-color (car colors)) default-frame-alist)
    (push (cons 'foreground-color (cdr colors)) default-frame-alist)))

;; Fewer garbage collections during startup, restored afterward
(setq gc-cons-threshold most-positive-fixnum)
(add-hook 'emacs-startup-hook
          (lambda () (setq gc-cons-threshold (* 16 1024 1024))))

(setq package-archives '(("melpa" . "https://melpa.org/packages/")
                         ("gnu"   . "https://elpa.gnu.org/packages/"))
      load-prefer-newer t
      warning-suppress-types '((files missing-lexbind-cookie))
      native-comp-async-report-warnings-errors 'silent)
