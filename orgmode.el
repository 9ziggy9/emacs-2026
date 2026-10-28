;;; orgmode.el --- org: looks and keys (PDF preview: latexmode.el) -*- lexical-binding: t -*-

;;; Org
(use-package org
  :ensure nil
  :defer t
  :custom
  (org-hide-emphasis-markers t)          ; *bold* shows as bold, no stars
  (org-pretty-entities nil)              ; LaTeX shows as typed: \alpha, not α
  (org-ellipsis " ▾")                    ; after a folded heading
  (org-startup-folded 'content)          ; open with every heading shown, bodies folded
  (org-auto-align-tags nil)              ; org-modern draws tags itself
  (org-tags-column 0)
  (org-catch-invisible-edits 'show-and-error) ; no editing folded text unseen
  (org-special-ctrl-a/e t)               ; C-a/C-e skip stars and tags
  (org-insert-heading-respect-content t) ; new headings go after the subtree
  :config
  ;; Bigger headings, and the ellipsis without the underline it gets by
  ;; default; redone after each theme, since themes set them
  (defun my/org-faces (&rest _)
    (set-face-attribute 'org-ellipsis nil :underline nil)
    (pcase-dolist (`(,face . ,height) '((org-document-title . 1.5)
                                        (org-level-1 . 1.3)
                                        (org-level-2 . 1.15)
                                        (org-level-3 . 1.05)))
      (set-face-attribute face nil :height height :weight 'bold)))
  (my/org-faces)
  (add-hook 'enable-theme-functions #'my/org-faces))

;; Symbols for heading stars (▶ folded, ▼ open), list bullets,
;; checkboxes, tags, tables, blocks, timestamps
(use-package org-modern
  :hook (org-mode . org-modern-mode)
  :custom
  (org-modern-list '((?- . "•") (?+ . "◦") (?* . "▹")))
  (org-modern-table-vertical 1))

;; Tab opens and closes the heading at point.  In normal state evil has
;; Tab as C-i, jump forward, which would beat org's
(with-eval-after-load 'evil
  (evil-define-key 'normal org-mode-map
    (kbd "<tab>")     #'org-cycle
    (kbd "TAB")       #'org-cycle
    (kbd "<backtab>") #'org-shifttab))    ; Shift-Tab: every heading at once

(provide 'orgmode)
