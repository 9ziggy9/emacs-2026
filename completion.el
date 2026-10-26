;;; completion.el --- minibuffer completion, M-x, autocompletion -*- lexical-binding: t -*-

(require 'popup (locate-user-emacs-file "popup"))  ; the hint faces

;;; Completion: fzf-style fuzzy finding in the minibuffer
(use-package vertico              ; vertical candidate list
  :init (vertico-mode 1)
  :custom (vertico-cycle t)
  :bind (:map vertico-map
         ("C-j" . vertico-next)
         ("C-k" . vertico-previous)))

(use-package orderless            ; fzf-like matching
  :custom
  (completion-styles '(orderless basic))
  (completion-category-overrides '((file (styles basic partial-completion))))
  ;; Each space-separated term matches literally, as a regexp, or
  ;; fuzzily (letters in order, like fzf); terms can come in any order
  (orderless-matching-styles '(orderless-literal orderless-regexp orderless-flex)))

(use-package consult              ; buffer switcher and searches
  :init
  (recentf-mode 1))               ; lets consult-buffer offer recent files too

(use-package marginalia           ; a description beside each candidate
  :init (marginalia-mode 1))

;;; M-x: a centered box, bordered like the popups, at 75% text.  M-m
;;; and M-p inside narrow it (see below).
(use-package vertico-posframe
  :custom
  (vertico-posframe-border-width 3)
  :custom-face
  (vertico-posframe-border ((t (:background "#cc7833"))))) ; popup orange

(use-package vertico-multiform    ; per-command looks, part of vertico
  :ensure nil
  :after vertico
  :custom
  (vertico-multiform-commands
   '((execute-extended-command
      posframe
      (vertico-count . 16)
      (vertico-posframe-min-height . 16)))) ; 20 lines at 75% text, hints included
  :config
  (vertico-multiform-mode 1))

;; Two filters, on and off independently, and combinable:
;;   M-m  commands from the modes active in your buffer
;;   M-p  commands with a key binding there
(defvar-local my/mx-filters nil
  "The M-x filters switched on: `active' and/or `bound'.")

(defvar-local my/mx-all-predicate nil
  "M-x's own predicate, which the filters narrow.")

(defvar-local my/mx-mode-prefixes nil
  "Name prefixes of the modes active where M-x was called, e.g. \"evil-\".")

(defvar-local my/mx-bound nil
  "Commands with a key binding where M-x was called, worked out on first M-p.")

(defun my/mx-active-modes (buffer)
  "Prefixes for BUFFER's major mode (and parents) and its minor modes."
  (with-current-buffer buffer
    (delete-dups
     (mapcar (lambda (mode)
               (concat (string-remove-suffix
                        "-mode" (string-remove-prefix "global-" (symbol-name mode)))
                       "-"))
             (append (derived-mode-all-parents major-mode)
                     local-minor-modes global-minor-modes)))))

(defun my/mx-bound-commands (buffer)
  "A set of the commands bound to a key in BUFFER (menus don't count).
Walks BUFFER's keymaps for candidates, then keeps those `where-is'
can still reach, so a key another map shadows doesn't count."
  (let ((seen (make-hash-table :test #'eq))
        (set (make-hash-table :test #'eq)))
    (with-current-buffer buffer
      (named-let walk ((maps (current-active-maps)) (depth 0))
        (dolist (map maps)
          (map-keymap
           (lambda (event def)
             (unless (memq event '(menu-bar tool-bar tab-bar remap))
               (when (eq (car-safe def) 'menu-item)
                 (setq def (nth 2 def)))
               (cond ((and (symbolp def) (commandp def))
                      (puthash def t seen))
                     ((and (keymapp def) (< depth 4))
                      (walk (list def) (1+ depth))))))
           map)))
      (maphash (lambda (sym _)
                 (when (seq-some (lambda (key)
                                   (not (memq (aref key 0)
                                              '(menu-bar tool-bar tab-bar remap))))
                                 (where-is-internal sym))
                   (puthash sym t set)))
               seen))
    set))

(defun my/mx-setup ()
  "Shrink M-x's text and note the active modes, for M-m."
  (when (eq current-minibuffer-command 'execute-extended-command)
    (face-remap-add-relative 'default :height 0.75)
    (setq my/mx-all-predicate minibuffer-completion-predicate
          my/mx-mode-prefixes (my/mx-active-modes
                               (window-buffer (minibuffer-selected-window))))
    ;; The box's first sizing cuts off the hint line; redraw it once
    ;; it's up, as any later keypress would
    (run-at-time 0 nil #'my/mx-redraw (current-buffer))))

(add-hook 'minibuffer-setup-hook #'my/mx-setup)

(defvar vertico--input)
(declare-function vertico--exhibit "vertico")

(defun my/mx-redraw (minibuffer)
  "Recompute and redisplay M-x's candidates in MINIBUFFER."
  (when (buffer-live-p minibuffer)
    (with-current-buffer minibuffer
      (setq vertico--input t)
      (vertico--exhibit))))

(defun my/mx-toggle (filter)
  "Switch FILTER on or off, and narrow the candidates to match."
  (setq my/mx-filters (if (memq filter my/mx-filters)
                          (delq filter my/mx-filters)
                        (cons filter my/mx-filters)))
  (let ((buffer (window-buffer (minibuffer-selected-window)))
        (all my/mx-all-predicate)
        (prefixes my/mx-mode-prefixes)
        (bound (and (memq 'bound my/mx-filters)
                    (or my/mx-bound
                        (setq my/mx-bound (my/mx-bound-commands
                                           (window-buffer (minibuffer-selected-window)))))))
        (active (memq 'active my/mx-filters)))
    (setq minibuffer-completion-predicate
          (if (not my/mx-filters)
              all
            (lambda (sym)
              (and (funcall all sym)
                   (or (not bound) (gethash sym bound))
                   (or (not active)
                       (let ((name (symbol-name sym)))
                         (seq-some (lambda (p) (string-prefix-p p name)) prefixes))
                       (command-completion-using-modes-and-keymaps-p sym buffer)))))))
  (setq vertico--input t))                ; recompute the candidates

(defun my/mx-toggle-active ()
  "In M-x, show only commands from the active modes (or stop).
A command counts if its name starts with an active mode's (evil-...,
c-ts-...), it's bound in the buffer's mode keymaps, or it's declared
for one of the buffer's modes."
  (interactive)
  (my/mx-toggle 'active))

(defun my/mx-toggle-bound ()
  "In M-x, show only commands with a key binding (or stop)."
  (interactive)
  (my/mx-toggle 'bound))

;; Hint lines under the candidates, like the popups': the filter keys
;; (one that's on is lit up), then the orderless prefixes that narrow
;; what a single search term matches
(defun my/mx-hints ()
  (cl-flet ((hint (key text filter)
              (concat (propertize key 'face 'pop/hint-key) " "
                      (propertize text 'face (if (memq filter my/mx-filters)
                                                 'pop/hint-key
                                               'pop/hint-text))))
            (prefix (char text)        ; a size down from the keys above
              (concat (propertize char 'face '(:inherit pop/hint-key :height 0.85))
                      (propertize "x " 'face '(:inherit shadow :height 0.85))
                      (propertize text 'face '(:inherit pop/hint-text :height 0.85)))))
    (concat " " (hint "M-m" "active modes" 'active) "  "
            (hint "M-p" "has a key" 'bound) "\n "
            (mapconcat (lambda (p) (prefix (car p) (cdr p)))
                       '(("!" . "not") ("&" . "in docs")
                         ("^" . "start") ("," . "initials")
                         ("=" . "exact"))
                       "  "))))

(defun my/mx-add-hints (args)
  "Add the hint lines to M-x's candidate LINES (the first of ARGS)."
  (if (eq current-minibuffer-command 'execute-extended-command)
      (list (append (car args) (list (concat "\n" (my/mx-hints)))))
    args))

(advice-add 'vertico--display-candidates :filter-args #'my/mx-add-hints)

(with-eval-after-load 'vertico
  (pcase-dolist (`(,key . ,cmd) '(("M-m" . my/mx-toggle-active)
                                  ("M-p" . my/mx-toggle-bound)))
    (keymap-set vertico-map key
                `(menu-item "" ,cmd
                            :filter ,(lambda (cmd)
                                       (and (eq current-minibuffer-command
                                                'execute-extended-command)
                                            cmd))))))

;;; Autocompletion: a popup of candidates as you type
(use-package corfu
  :init (global-corfu-mode 1)
  :custom
  (corfu-auto t)             ; show candidates automatically while typing
  (corfu-auto-prefix 2)      ; ...after 3 characters
  (corfu-auto-delay 0.4)     ; ...and a short pause
  (corfu-cycle t)            ; wrap around at the ends of the list
  :config
  ;; Popup text at 75% of the buffer's (text scaling included); redone
  ;; after each theme, since loading one resets the face
  (defun my/corfu-text-size (&rest _)
    (set-face-attribute 'corfu-default nil :height 0.75))
  (my/corfu-text-size)
  (add-hook 'enable-theme-functions #'my/corfu-text-size))

(provide 'completion)
