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
        evil-vsplit-window-right t)   ; :vs opens right
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
  (c-ts-mode . electric-pair-local-mode))

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
