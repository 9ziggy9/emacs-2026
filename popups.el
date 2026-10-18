;;; popups.el --- popup type definitions -*- lexical-binding: t -*-

;; Each popup is a `pop/define' declaration plus the few commands it
;; needs.  Toggle keys live in universal.el.

(require 'popup)

(declare-function face-remap-remove-relative "face-remap")
(defvar-local pop/text-scale-cookie nil)

(defun pop/text-scale (factor)
  "Scale the current buffer's text by FACTOR, replacing any earlier scale."
  (when pop/text-scale-cookie
    (face-remap-remove-relative pop/text-scale-cookie))
  (setq-local pop/text-scale-cookie
              (face-remap-add-relative 'default :height factor)))

;;;; Compilation

(defvar compilation-always-kill)
(defvar compilation-scroll-output)
(defvar compile-command)
(defvar compile-history)
(declare-function compile-goto-error "compile")
(declare-function compilation-mode "compile")

(setq compilation-always-kill t               ; new compile kills old, no prompt
      compilation-scroll-output 'first-error) ; follow output, stop at 1st error

;; Render gcc's colored output instead of showing raw escape codes
(add-hook 'compilation-filter-hook #'ansi-color-compilation-filter)

;; No column indicator in compilation buffers
(setq global-display-fill-column-indicator-modes
      '((not special-mode compilation-mode) t))

(defun pop/compile-buffer ()
  "The compilation buffer, created in the current file's directory if needed."
  (or (get-buffer "*compilation*")
      (let ((dir (buffer-local-value 'default-directory (pop/main-buffer))))
        (with-current-buffer (get-buffer-create "*compilation*")
          (setq default-directory dir)
          (compilation-mode)
          (let ((inhibit-read-only t))
            (insert "C-<return> to enter a compile command\n"))
          (current-buffer)))))

(defun pop/compile-prompt ()
  "Prompt for a compile command in the popup's minibuffer and run it.
The prompt starts with the last command, so C-<return> twice reruns it."
  (interactive)
  (compile (read-shell-command "Compile: " compile-command 'compile-history))
  (pop/focus))

(defun pop/compile-goto-error ()
  "Hide the popup and jump to the error at point in the main frame."
  (interactive)
  (let ((buf (current-buffer))
        (pos (point))
        ;; Jumping makes compile re-display its buffer; keep the popup hidden
        (pop/suppress t))
    (pop/hide)
    (with-current-buffer buf
      (goto-char pos)
      (compile-goto-error))
    (pop/hide)))

(pop/define compile
  :match   (derived-mode-p 'compilation-mode)
  :open    #'pop/compile-buffer
  :capture t
  :setup   (pop/text-scale 0.8)
  :keys    ("RET"        pop/compile-goto-error
            "C-<return>" pop/compile-prompt
            "q"          pop/hide))

;;;; Dired

(declare-function dired-get-file-for-visit "dired")
(declare-function dired-find-file "dired")
(declare-function dired-goto-file "dired")
(declare-function dired-noselect "dired")

(defun pop/dired-here ()
  "A dired buffer at the main buffer's directory, on the file you came from."
  (let* ((main (pop/main-buffer))
         (file (buffer-file-name main))
         (buf (dired-noselect (buffer-local-value 'default-directory main))))
    (when file
      (with-current-buffer buf (dired-goto-file file)))
    buf))

(defun pop/dired-find-file ()
  "Enter directories in place; open files in the main frame."
  (interactive)
  (let ((file (dired-get-file-for-visit)))
    (if (file-directory-p file)
        (dired-find-file)
      (pop/hide)
      (find-file file))))

(defun pop/dired-open-in-split ()
  "Hide the popup and open the file at point in a new split in the main frame."
  (interactive)
  (let ((file (dired-get-file-for-visit)))
    (pop/hide)
    (select-window (split-window-right))
    (find-file file)))

(pop/define dired
  :match   (derived-mode-p 'dired-mode)
  :open    #'pop/dired-here
  :size    (0.8 . 0.8)
  :keys    ("RET"        pop/dired-find-file
            "C-<return>" pop/dired-open-in-split
            "q"          pop/hide))

(provide 'popups)
