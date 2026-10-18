;;; clean.el --- -*- lexical-binding: t -*-

;; Minimal UI improvements
(setq inhibit-startup-screen t)
(setq initial-scratch-message nil)

;; Disable ALL backup and temporary files
(setq make-backup-files nil)              ; Disable backup files (#...#)
(setq auto-save-default nil)              ; Disable auto-save files
(setq auto-save-list-file-prefix nil)     ; Disable auto-save session files
(setq create-lockfiles nil)               ; Disable lock files (.#...)

;; Send Custom's auto-generated settings to their own file
(setq custom-file (locate-user-emacs-file "custom.el"))
(load custom-file 'noerror 'nomessage)

(provide 'clean)
