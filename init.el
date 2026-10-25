;;; init.el --- -*- lexical-binding: t -*-

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

;; Echo area text at 60% of the buffer text size
(dolist (buf '(" *Echo Area 0*" " *Echo Area 1*"))
  (with-current-buffer (get-buffer-create buf)
    (face-remap-add-relative 'default :height 0.6)))

;;; Theme
(use-package railscasts-reloaded-theme
  :config
  (load-theme 'railscasts-reloaded t))

(use-package base16-theme :defer t)     ; ~360 schemes: base16-<name>
(use-package ef-themes :defer t)        ; ~34 polished light/dark themes
(use-package doom-themes :defer t)      ; ~60 themes: doom-<name>

;;; Evil
(use-package evil
  :init
  ;; These must be set before evil loads
  (setq evil-want-keybinding nil      ; leave other modes' maps alone
        evil-want-C-u-scroll t        ; C-u scrolls up, like vim
        evil-want-Y-yank-to-eol t     ; Y behaves like y$
        evil-undo-system 'undo-redo   ; built-in redo for C-r
        evil-split-window-below t     ; :sp opens below
        evil-vsplit-window-right t    ; :vs opens right
        evil-echo-state nil)          ; no -- INSERT -- in the echo area
  :config
  (evil-mode 1))

(use-package evil-collection
  :after evil
  :config
  (setq evil-collection-mode-list '(dired ibuffer corfu helpful))
  (evil-collection-init))

;;; Windows
(use-package window
  :ensure nil
  :custom
  (window-combination-resize t))

;;; Dired
(use-package dired
  :ensure nil
  :custom
  (dired-kill-when-opening-new-dired-buffer t)
  :config
  (evil-define-key 'normal dired-mode-map
    "=" #'dired-create-empty-file     ; the +/= key on its own
    "+" #'dired-create-directory))    ; with Shift

(use-package ibuffer
  :ensure nil
  :custom
  (ibuffer-expert t))

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
  (recentf-mode 1)                ; lets consult-buffer offer recent files too
  :config
  ;; Hide non-color "themes" from consult-theme: newcomers-presets changes
  ;; settings (turns on the tab bar), light-blue is obsolete, and base16 is
  ;; just the base16 package's helper file
  (setq consult-themes
        (seq-difference (custom-available-themes)
                        '(newcomers-presets light-blue base16))))

(use-package consult-eglot              ; project-wide symbols, via clangd
  :after (consult eglot))

;; LANGS
(use-package c-ts-mode
  :ensure nil
  :init
  ;; Use the tree-sitter modes for .c and .h files
  (add-to-list 'major-mode-remap-alist '(c-mode . c-ts-mode))
  (add-to-list 'major-mode-remap-alist '(c-or-c++-mode . c-or-c++-ts-mode))
  :config
  ;; Where to fetch the C grammar from
  (add-to-list 'treesit-language-source-alist
               '(c "https://github.com/tree-sitter/tree-sitter-c"))
  :custom
  (c-ts-mode-indent-offset 2)
  (c-ts-mode-indent-style 'k&r)
  :hook
  (c-ts-mode . electric-pair-local-mode)
  (c-ts-mode . my/c-mode-line))

(defun my/c-mode-line ()
  "Strip the mode line down to the evil state, file name and a modes button."
  (setq-local mode-line-format
              '(" " (:eval (my/evil-state-tag))
                " " mode-line-buffer-identification
                mode-line-format-right-align
                (:eval (my/mode-line-modes-button)) " ")))

;; Evil state badges: each borrows a font-lock color, inverted into a pill,
;; so they follow whatever theme is loaded
(defface my/evil-base     '((t :inverse-video t :weight bold :height 0.85)) "")
(defface my/evil-normal   '((t :inherit (my/evil-base font-lock-keyword-face)))  "")
(defface my/evil-insert   '((t :inherit (my/evil-base font-lock-string-face)))   "")
(defface my/evil-visual   '((t :inherit (my/evil-base font-lock-constant-face))) "")
(defface my/evil-replace  '((t :inherit (my/evil-base font-lock-warning-face)))  "")
(defface my/evil-operator '((t :inherit (my/evil-base font-lock-type-face)))     "")
(defface my/evil-other    '((t :inherit (my/evil-base font-lock-comment-face)))  "")

;; Modes button: shows the major mode and how many minor modes are on;
;; clicking it lists them in the minibuffer, and picking one opens its help
(defun my/mode-line-modes-button ()
  "The major mode name and minor-mode count, clickable."
  (propertize (format "%s +%d" (format-mode-line mode-name)
                      (length (my/enabled-minor-modes)))
              'mouse-face 'mode-line-highlight
              'help-echo "mouse-1: list enabled modes"
              'local-map (let ((map (make-sparse-keymap)))
                           (keymap-set map "<mode-line> <mouse-1>"
                                       #'my/mode-line-modes-menu)
                           map)))

(defun my/enabled-minor-modes ()
  "Minor modes on in the current buffer, local and global, sorted."
  (sort (seq-uniq (append local-minor-modes global-minor-modes))))

(defun my/mode-line-modes-menu (event)
  "List the enabled modes of the clicked window's buffer; open help on one."
  (interactive "e")
  (let* ((modes (with-selected-window (posn-window (event-start event))
                  (cons major-mode (my/enabled-minor-modes))))
         (names (mapcar #'symbol-name modes))
         ;; Keep the major mode first and the rest alphabetical
         (table (lambda (str pred action)
                  (if (eq action 'metadata)
                      '(metadata (display-sort-function . identity))
                    (complete-with-action action names str pred)))))
    (describe-function
     (intern (completing-read "Enabled modes: " table nil t)))))

(defun my/evil-state-tag ()
  "The current evil state as a colored badge, e.g. \" INSERT \"."
  (when (bound-and-true-p evil-state)
    (propertize (format " %s " (upcase (symbol-name evil-state)))
                'face (pcase evil-state
                        ('normal   'my/evil-normal)
                        ('insert   'my/evil-insert)
                        ('visual   'my/evil-visual)
                        ('replace  'my/evil-replace)
                        ('operator 'my/evil-operator)
                        (_         'my/evil-other)))))

;;; Autocompletion: a popup of candidates as you type
(use-package corfu
  :init (global-corfu-mode 1)
  :custom
  (corfu-auto t)             ; show candidates automatically while typing
  (corfu-auto-prefix 2)      ; ...after 3 characters
  (corfu-auto-delay 0.4)     ; ...and a short pause
  (corfu-cycle t))           ; wrap around at the ends of the list

;;; Command log: a live side buffer of every key and the command it ran
(use-package command-log-mode
  :commands clm/toggle-command-log-buffer
  :custom
  (command-log-mode-key-binding-open-log nil)   ; don't grab C-c o
  (command-log-mode-open-log-turns-on-mode t)   ; opening the log starts logging
  (command-log-mode-is-global t))               ; ...in every buffer

;;; Key hints: pause after a prefix to see what can follow it
(use-package which-key
  :ensure nil                          ; built in since Emacs 30
  :init (which-key-mode 1))

;;; Richer help buffers (source, references, keybindings)
(use-package helpful
  :bind
  (([remap describe-function] . helpful-callable)
   ([remap describe-variable] . helpful-variable)
   ([remap describe-command]  . helpful-command)
   ([remap describe-key]      . helpful-key)
   ([remap describe-symbol]   . helpful-symbol)))

(use-package eldoc
  :ensure nil
  :custom
  (eldoc-idle-delay 0.2)                 ; pause before docs appear (default 0.5)
  (eldoc-echo-area-use-multiline-p t)    ; let the echo area grow to fit
  (eldoc-echo-area-prefer-doc-buffer t)) ; if *eldoc* is open, show docs there instead

(use-package eglot
  :ensure nil
  :hook (c-ts-mode . eglot-ensure)     ; start clangd in every C buffer
  :init
  (setq eglot-stay-out-of '(eldoc))    ; keep eglot out of the echo area
  :custom
  (eglot-ignored-server-capabilities '(:inlayHintProvider)) ; no inline hints
  (eglot-autoshutdown t)               ; stop it when the last C buffer closes
  (eglot-extend-to-xref t)             ; headers you jump into reuse that clangd
  :config
  ;; clangd marks inactive #ifdef branches (e.g. an stb-style
  ;; #ifdef FOO_IMPLEMENTATION block) as "comment" tokens, greying them out;
  ;; tree-sitter already highlights real comments
  (setq eglot-semantic-token-types
        (delete "comment" eglot-semantic-token-types)))

;;; Popups
(load (locate-user-emacs-file "popup") nil t)  ;; API
(load (locate-user-emacs-file "popups") nil t) ;; Implementations

;; Keys that override everything; must load after evil
(load (locate-user-emacs-file "universal") nil t)
