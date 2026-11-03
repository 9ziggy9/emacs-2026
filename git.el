;;; git.el --- magit, and GitHub through the gh CLI -*- lexical-binding: t -*-

(require 'popup (locate-user-emacs-file "popup"))
(require 'transient)

;;; Magit

;; The status buffer takes the whole frame, not a popup; q (or the git
;; slot again) puts the old layout back.  Evil keys come from
;; evil-collection (see editing.el).
(use-package magit
  :commands (magit-status magit-mode-bury-buffer)
  :custom
  (magit-display-buffer-function #'magit-display-buffer-fullframe-status-v1)
  (magit-bury-buffer-function #'magit-restore-window-configuration)
  :config
  ;; @ opens the gh menu, from magit's own menu (? or H) or directly
  (transient-append-suffix 'magit-dispatch "!" '("@" "GitHub (gh)" my/gh))
  (with-eval-after-load 'evil
    (evil-define-key* '(normal visual) magit-mode-map "@" #'my/gh)))

(declare-function magit-mode-bury-buffer "magit-mode")
(declare-function magit-status-setup-buffer "magit-status")
(declare-function evil-define-key* "evil-core")
(declare-function magit-refresh-all "magit-mode")
(declare-function magit-toplevel "magit-git")
(declare-function magit-get "magit-git")
(declare-function magit-rev-verify "magit-git")

(defun my/git-toggle ()
  "Open magit's status for this repo, or close it if it's showing.
From a popup, the popup closes and this acts on the main frame."
  (interactive)
  (when (eq (selected-frame) pop/frame)
    (pop/hide))
  (with-current-buffer (window-buffer (selected-window))
    (if (derived-mode-p 'magit-mode)
        (magit-mode-bury-buffer)
      (call-interactively #'magit-status))))

;;; GitHub (gh)

;; gh runs in the background; its output collects in *gh*, which opens
;; in a popup for listings and whenever gh fails.  gh never prompts here,
;; so every command asks for what it needs first.

(pop/define gh
  :match   (equal (buffer-name) "*gh*")
  :open    #'my/gh-buffer
  :setup   (pop/text-scale 0.8)
  :keys    ("q" pop/hide))

(defun my/gh-buffer ()
  "The *gh* output buffer, at its end."
  (with-current-buffer (get-buffer-create "*gh*")
    (goto-char (point-max))
    (current-buffer)))

(defun my/gh-show ()
  "Show the *gh* output in its popup."
  (pop/display (my/gh-buffer) nil)
  (pop/focus))

(defun my/gh-run (args &optional show then)
  "Run gh with ARGS in the background, output to *gh*.
With SHOW, open the output when gh is done; it opens anyway if gh
fails.  THEN, if given, is called after gh succeeds."
  (unless (executable-find "gh")
    (user-error "The gh command isn't installed"))
  (let ((buf (my/gh-buffer))
        (process-environment (append '("GH_PROMPT_DISABLED=1" "NO_COLOR=1")
                                     process-environment)))
    (with-current-buffer buf
      (insert (format "\n$ gh %s\n" (mapconcat #'shell-quote-argument args " "))))
    (message "gh %s..." (string-join (seq-take args 2) " "))
    (make-process
     :name "gh"
     :buffer buf
     :command (cons "gh" args)
     :connection-type 'pipe
     :sentinel
     (lambda (proc _event)
       (when (memq (process-status proc) '(exit signal))
         (if (zerop (process-exit-status proc))
             (progn
               (message "gh %s: done" (string-join (seq-take args 2) " "))
               (when then (funcall then))
               (when (fboundp 'magit-refresh-all) (magit-refresh-all))
               (when show (my/gh-show)))
           (message "gh %s failed" (string-join (seq-take args 2) " "))
           (my/gh-show)))))))

(defun my/gh-repo-create (name visibility description)
  "Create the GitHub repo NAME for this repo, as its origin, and push.
VISIBILITY is \"private\" or \"public\".  Outside a git repo, offers to
make this directory one first."
  (interactive
   (progn
     (require 'magit)
     (unless (magit-toplevel)
       (unless (y-or-n-p (format "%s isn't a git repo; make it one? "
                                 (abbreviate-file-name default-directory)))
         (user-error "Cancelled"))
       (call-process "git" nil nil nil "init"))
     (when (magit-get "remote.origin.url")
       (user-error "This repo already has an origin: %s"
                   (magit-get "remote.origin.url")))
     (list (read-string "Repo name: "
                        (file-name-nondirectory
                         (directory-file-name (magit-toplevel))))
           (completing-read "Visibility: " '("private" "public") nil t
                            nil nil "private")
           (read-string "Description (optional): "))))
  (my/gh-run (append (list "repo" "create" name (concat "--" visibility)
                           "--source" (magit-toplevel) "--remote" "origin")
                     (unless (string-empty-p description)
                       (list "--description" description))
                     ;; Pushing needs a commit to push
                     (when (magit-rev-verify "HEAD")
                       (list "--push")))
             t))

(defun my/gh-repo-clone (repo directory)
  "Clone the GitHub REPO (owner/name, or just name for your own) into DIRECTORY."
  (interactive
   (let ((repo (read-string "Clone (owner/name): ")))
     (list repo
           (read-directory-name "Into: " "~/" nil nil
                                (file-name-nondirectory repo)))))
  (let ((dir (expand-file-name directory)))
    (my/gh-run (list "repo" "clone" repo dir) nil
               (lambda () (magit-status-setup-buffer dir)))))

(defun my/gh-browse ()
  "Open this repo on GitHub in the browser."
  (interactive)
  (my/gh-run '("browse")))

(defun my/gh-pr-create ()
  "Start a pull request for this branch, in the browser."
  (interactive)
  (my/gh-run '("pr" "create" "--web")))

(defun my/gh-pr-view ()
  "Open this branch's pull request in the browser."
  (interactive)
  (my/gh-run '("pr" "view" "--web")))

(defun my/gh-pr-list ()
  "List the repo's open pull requests."
  (interactive)
  (my/gh-run '("pr" "list") t))

(defun my/gh-issue-create ()
  "Start an issue, in the browser."
  (interactive)
  (my/gh-run '("issue" "create" "--web")))

(defun my/gh-issue-list ()
  "List the repo's open issues."
  (interactive)
  (my/gh-run '("issue" "list") t))

(defun my/gh-repo-list ()
  "List your GitHub repos."
  (interactive)
  (my/gh-run '("repo" "list") t))

(transient-define-prefix my/gh ()
  "GitHub, through the gh command line tool."
  [["Repo"
    ("c" "Create on GitHub" my/gh-repo-create)
    ("C" "Clone"            my/gh-repo-clone)
    ("r" "Your repos"       my/gh-repo-list)
    ("b" "Open in browser"  my/gh-browse)]
   ["Pull requests"
    ("p" "Create"           my/gh-pr-create)
    ("v" "This branch's"    my/gh-pr-view)
    ("l" "List"             my/gh-pr-list)]
   ["Issues"
    ("i" "Create"           my/gh-issue-create)
    ("I" "List"             my/gh-issue-list)]
   ["Output"
    ("o" "Show *gh*"        pop/gh-toggle)]])

(provide 'git)
