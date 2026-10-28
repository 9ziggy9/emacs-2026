;;; latexmode.el --- LaTeX, snippets, live PDF preview -*- lexical-binding: t -*-

(require 'popup (locate-user-emacs-file "popup"))

;;; LaTeX

;; .tex files, as plain text with colours: nothing is drawn as symbols,
;; raised or shrunk; \partial, x^2 and \frac{a}{b} stay exactly as typed
(use-package tex-mode
  :ensure nil
  :defer t
  :custom
  (tex-default-mode 'latex-mode)        ; a new, empty .tex is LaTeX too
  (tex-fontify-script nil))             ; x^2, x_i: no raised or smaller text

;;; Snippets

;; Type a snippet's name, e.g. <dm, and pick it from the completion
;; popup; Tab and S-Tab then move between its blanks.  The names all
;; start with <, so words like al, sum or item never bring them up.
;; The snippets are in templates.eld; the math ones work in org too.
(use-package tempel
  :custom
  (tempel-path (locate-user-emacs-file "templates.eld"))
  :hook
  ((latex-mode org-mode) . my/tempel-setup)
  :bind (:map tempel-map
         ("<tab>"     . tempel-next)
         ("TAB"       . tempel-next)
         ("<backtab>" . tempel-previous)))

(defun my/tempel-complete ()
  "Snippets for the word before point, if it starts with <."
  (when (looking-back "<[[:alpha:]]*" (line-beginning-position))
    (tempel-complete)))

(defvar corfu-on-exact-match)

(defun my/tempel-setup ()
  "Offer snippets in the completion popup, ahead of other completions."
  (add-hook 'completion-at-point-functions #'my/tempel-complete -90 t)
  ;; A complete name (<dm) matches just itself; show it anyway, so RET
  ;; can expand it, rather than the popup staying away
  (setq-local corfu-on-exact-match 'show))

;;; Live PDF preview

;; The pdf slot shows the document as a PDF in a split on its right,
;; rebuilt by LaTeX in the background every time you save; the slot
;; again stops it.  A .tex file is built as it is; an org file is first
;; exported to a .tex next to it, as with export.  The PDF and LaTeX's
;; other files go to a temporary directory.

(use-package pdf-tools                  ; PDFs open in pdf-view-mode
  :defer t
  :init (pdf-loader-install)            ; builds its helper the first time
  :custom (pdf-view-display-size 'fit-width)
  :config
  ;; Its page-prefetch timer can fire while a PDF is still opening, before
  ;; the window has a page, and errors; it repeats, so just wait for one
  (advice-add 'pdf-cache--prefetch-start :before-while
              (lambda (&rest _) (pdf-view-current-page))))

(declare-function org-latex-export-to-latex "ox-latex")

(defvar-local my/pdf-process nil "The running LaTeX build, if any.")
(defvar-local my/pdf-again nil "Saved during a build: build once more after.")

(defun my/pdf-file ()
  "Where the current document's preview PDF goes."
  (expand-file-name (concat (file-name-base buffer-file-name) ".pdf")
                    (file-name-concat temporary-file-directory "pdf-preview"
                                      (md5 buffer-file-name))))

(defun my/pdf-tex-file ()
  "The .tex file to build: this file, or an org file's export."
  (if (derived-mode-p 'org-mode)
      (expand-file-name (org-latex-export-to-latex))
    buffer-file-name))

(defun my/pdf-build ()
  "Build the PDF in the background."
  (if (process-live-p my/pdf-process)
      (setq my/pdf-again t)
    (unless (executable-find "latexmk")
      (user-error "No latexmk: install TeX Live (see README)"))
    (let ((tex (my/pdf-tex-file))
          (pdf (my/pdf-file))
          (buf (current-buffer)))
      (make-directory (file-name-directory pdf) t)
      (with-current-buffer (get-buffer-create "*pdf build*")
        (erase-buffer))
      (setq my/pdf-process
            (make-process
             :name "pdf-build"
             :buffer "*pdf build*"
             :command (list "latexmk" "-pdf" "-interaction=nonstopmode"
                            "-halt-on-error"
                            (concat "-outdir=" (file-name-directory pdf))
                            (file-name-nondirectory tex))
             :sentinel (lambda (proc _)
                         (unless (process-live-p proc)
                           (my/pdf-done buf pdf (process-exit-status proc)))))))))

(defun my/pdf-error ()
  "LaTeX's first error, from the build log, e.g. \"! Undefined control sequence\"."
  (with-current-buffer "*pdf build*"
    (goto-char (point-min))
    (if (re-search-forward "^! .*" nil t)
        (match-string 0)
      "see *pdf build*")))

(defun my/pdf-done (buf pdf status)
  "Show the new PDF beside BUF, or say why LaTeX failed."
  (when (buffer-live-p buf)
    (with-current-buffer buf
      (if (/= status 0)
          (message "LaTeX failed: %s" (my/pdf-error))
        (let ((view (find-buffer-visiting pdf))
              (win (get-buffer-window buf)))
          (cond (view (with-current-buffer view (revert-buffer t t t)))
                ;; Opened from inside its window, so pdf-tools sizes the
                ;; pages for that window from the start
                (win (with-selected-window (split-window win nil 'right)
                       (find-file pdf)))))
        (message "PDF updated"))
      (when my/pdf-again
        (setq my/pdf-again nil)
        (my/pdf-build)))))

(define-minor-mode my/pdf-mode
  "Keep a PDF of this document beside it, rebuilt on every save."
  :lighter nil
  (if my/pdf-mode
      (progn
        (add-hook 'after-save-hook #'my/pdf-build nil t)
        (condition-case err
            (my/pdf-build)
          (error (my/pdf-mode -1)
                 (signal (car err) (cdr err)))))
    (remove-hook 'after-save-hook #'my/pdf-build t)
    (when-let* ((view (and buffer-file-name (find-buffer-visiting (my/pdf-file)))))
      (dolist (win (get-buffer-window-list view nil t))
        (delete-window win))
      (kill-buffer view))))

(defun my/pdf-toggle ()
  "Start or stop the live PDF preview of the org or LaTeX file you're in."
  (interactive)
  (when (eq (selected-frame) pop/frame)
    (pop/hide))
  (unless (and (derived-mode-p 'org-mode 'latex-mode) buffer-file-name)
    (user-error "The PDF preview is for org and LaTeX files"))
  (my/pdf-mode 'toggle))

;; Org and LaTeX files get the pdf slot after the usual ones
(with-eval-after-load 'modeline
  (dolist (mode '(org-mode latex-mode))
    (add-to-list 'ml/mode-slots
                 `(,mode ,@ml/default-slots ("pdf" . my/pdf-toggle)))))

(provide 'latexmode)
