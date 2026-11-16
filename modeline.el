;;; modeline.el --- the mode line and its F-key slots -*- lexical-binding: t -*-

;; The mode line shows numbered slots on the right: slot N is always F<N>.
;; Each major mode can declare its own slots in `ml/mode-slots'; any other
;; mode gets `ml/default-slots'.  F-keys follow the buffer you're working
;; in, even while a popup has focus, so pressing a popup's key again hides
;; it.  F-keys with no slot keep their usual binding (e.g. F11 fullscreen).

(require 'cl-lib)
(require 'popup (locate-user-emacs-file "popup"))
(require 'universal (locate-user-emacs-file "universal"))

;;;; Slots

(defvar ml/default-slots
  '(("compile" . pop/compile-toggle)
    ("dired"   . pop/dired-toggle)
    ("ibuffer" . pop/ibuffer-toggle)
    ("git"     . my/git-toggle)
    ("about"   . pop/about-toggle))
  "Slots (LABEL . COMMAND) for modes without their own; the first is F1.
A nil entry leaves that slot empty.")

(defvar ml/mode-slots nil
  "Alist of (MODE . SLOTS); the first MODE the buffer derives from wins.
Its SLOTS replace `ml/default-slots', e.g.

  (add-to-list \\='ml/mode-slots
               `(c-ts-mode ,@ml/default-slots (\"format\" . eglot-format)))")

(defun ml/slots (&optional buffer)
  "The slots for BUFFER (default: the current buffer)."
  (with-current-buffer (or buffer (current-buffer))
    (or (cdr (cl-find-if (lambda (entry) (derived-mode-p (car entry)))
                         ml/mode-slots))
        ml/default-slots)))

(defun ml/slot-command (n)
  "The command in slot N (1-based) for the buffer you're working in."
  (cdr (nth (1- n) (ml/slots (pop/main-buffer)))))

;; F1..F12 run their slot; an empty slot makes the binding vanish, so the
;; key falls through to whatever it normally does
(dotimes (i 12)
  (let ((n (1+ i)))
    (keymap-set univ-keys-map (format "<f%d>" n)
                `(menu-item "" ignore
                            :filter ,(lambda (_) (ml/slot-command n))))))

;; Popups are isolated from the universal keys; let the F-keys through
(setq pop/always-keep
      (append pop/always-keep
              (cl-loop for n from 1 to 12 collect (format "<f%d>" n))))
(pop/reset-keys)

;;;; Segments

;; base16 themes draw the mode line as base04 text on base02, which in some
;; schemes (atelier-sulphurpool: 1.7:1 contrast) is barely readable.  Use the
;; scheme's normal text (base05) on its second-darkest shade (base01), and
;; for windows you're not in, base04 on the background (base00).
(defun ml/base16-mode-line (&optional theme)
  "Readable mode-line colors when THEME is a base16 scheme."
  (let*((var (and theme (intern-soft (format "%s-theme-colors" theme))))
         (colors (and var (boundp var) (symbol-value var))))
    (when (and colors (string-prefix-p "base16-" (symbol-name theme)))
      (set-face-attribute 'mode-line nil
                          :background (plist-get colors :base01)
                          :foreground (plist-get colors :base05))
      (set-face-attribute 'mode-line-inactive nil
                          :background (plist-get colors :base00)
                          :foreground (plist-get colors :base04)))))

(dolist (theme custom-enabled-themes)
  (ml/base16-mode-line theme))
;; Early (-50), so the powerline segments below are colored from these
(add-hook 'enable-theme-functions #'ml/base16-mode-line -50)

;; The right side is powerline segments, like the i3 status bar: they
;; alternate between the bar's own colors and a lighter shade (30% of the
;; way to the text color, with brighter text), with arrows () between.
;; Colors come from the theme's mode line, so they follow every theme.
(defface ml/seg-a '((t)) "Powerline segment in the bar's own colors.")
(defface ml/seg-b '((t)) "Powerline segment in the lighter shade.")
(defface ml/arrow-into-a '((t)) "Arrow from a lighter segment into a plain one.")
(defface ml/arrow-into-b '((t)) "Arrow from a plain segment into a lighter one.")
(defface ml/name '((t :weight bold)) "The buffer name: the theme's darkest color.")

(defun ml/darkest-color ()
  "The darkest color among the theme's main text and background colors."
  (car (sort (seq-filter #'color-defined-p
                         (cl-loop for face in '(default mode-line mode-line-inactive)
                                  append (list (face-background face nil t)
                                               (face-foreground face nil t))))
             :key (lambda (c) (apply #'+ (color-name-to-rgb c))))))

(defun ml/mix (a b frac)
  "Color A with FRAC of color B mixed in."
  (apply #'color-rgb-to-hex
         (append (cl-mapcar (lambda (x y) (+ x (* frac (- y x))))
                            (color-name-to-rgb a) (color-name-to-rgb b))
                 '(2))))

(defun ml/update-segment-faces (&rest _)
  "Color the segments and arrows from the current theme's mode line."
  (let ((bg (face-background 'mode-line nil t))
        (fg (face-foreground 'mode-line nil t)))
    (when (and (color-defined-p bg) (color-defined-p fg))
      (let* ((dark (color-dark-p (color-name-to-rgb bg)))
             (b-bg (ml/mix bg fg 0.3))
             (b-fg (ml/mix fg (if dark "#ffffff" "#000000") 0.5))
             ;; Arrows at the editor font's full size, so they fill the bar
             (tall (face-attribute 'default :height nil t)))
        (set-face-attribute 'ml/name nil :foreground (ml/darkest-color))
        (set-face-attribute 'ml/seg-a nil :background bg :foreground fg)
        (set-face-attribute 'ml/seg-b nil :background b-bg :foreground b-fg)
        (set-face-attribute 'ml/arrow-into-a nil :background b-bg :foreground bg
                            :height tall)
        (set-face-attribute 'ml/arrow-into-b nil :background bg :foreground b-bg
                            :height tall)))))

(ml/update-segment-faces)
(add-hook 'enable-theme-functions #'ml/update-segment-faces)

;; A slimmer bar: smaller text makes the whole line thinner.  Themes reset
;; the mode-line faces when they load, so redo it after each one.
(defvar ml/height 0.85 "Mode-line text size, relative to buffer text.")

(defun ml/shrink-mode-line (&rest _)
  "Apply `ml/height' to the mode-line faces."
  (dolist (face '(mode-line mode-line-inactive))
    (set-face-attribute face nil :height ml/height)))

(ml/shrink-mode-line)
(add-hook 'enable-theme-functions #'ml/shrink-mode-line)

(defun ml/click-map (command)
  "A mode-line keymap running COMMAND on mouse-1."
  (let ((map (make-sparse-keymap)))
    (keymap-set map "<mode-line> <mouse-1>" command)
    (keymap-set map "<mouse-1>" command)       ; in the shared bar (below)
    map))

(defun ml/segments (parts)
  "PARTS (strings) as powerline segments, alternating colors, arrows between.
The first is the lighter shade, so its arrow shows against the bar."
  (let ((out nil))
    (cl-loop for part in parts
             for i from 0
             for face = (if (cl-evenp i) 'ml/seg-b 'ml/seg-a)
             do (let ((text (concat " " part " ")))
                  ;; the segment's background under the part's own colors
                  (add-face-text-property 0 (length text) face t text)
                  (push (propertize "" 'face
                                    (if (eq face 'ml/seg-b) 'ml/arrow-into-b
                                      'ml/arrow-into-a))
                        out)
                  (push text out)))
    (apply #'concat (nreverse out))))

(defun ml/right-side ()
  "Diagnostics and line:column as plain text, then the slots as powerline
segments.  Slot labels are clickable."
  (concat
   (or (ml/diagnostics) "")
   (propertize (format-mode-line "%l:%C") 'face 'shadow)
   " "
   (ml/segments
    (cl-loop for (label . cmd) in (ml/slots)
             for n from 1
             when label
             collect (propertize label
                                 'mouse-face 'mode-line-highlight
                                 'help-echo (format "F%d or mouse-1: %s" n cmd)
                                 'local-map (ml/click-map cmd))))))

;; The buffer name: a powerline segment from the left edge, in bold and the
;; theme's darkest color, ending
;; in a right-pointing arrow (), the unsaved-changes dot inside it
(defun ml/left-side ()
  ;; (Emacs pads the name to 12 characters; trimmed, so the arrow follows it)
  (let* ((name (string-trim-right
                (format-mode-line mode-line-buffer-identification)))
         (text (concat " " name (or (ml/modified-marker) "") " ")))
    ;; the name in the theme's darkest color, bold, over its usual color
    (add-face-text-property 1 (1+ (length name)) 'ml/name nil text)
    (add-face-text-property 0 (length text) 'ml/seg-b t text)
    ;; same colors as an arrow into a lighter segment, pointing the other way
    (concat text (propertize "" 'face 'ml/arrow-into-b))))

;; Unsaved changes: a dot after the file name
(defun ml/modified-marker ()
  "\" ●\" while a file-visiting buffer has unsaved changes."
  (when (and buffer-file-name (buffer-modified-p))
    (propertize " ●" 'face 'warning)))

;; Diagnostics: error and warning counts wherever flymake is checking
;; (eglot turns it on), or a check mark when there are none
(declare-function flymake-diagnostics "flymake")
(declare-function flymake-diagnostic-type "flymake")
(declare-function flymake--severity "flymake")

(defun ml/diagnostics ()
  "E.g. \"✗ 2  ⚠ 3  \", colored; nil where flymake isn't on."
  (when (bound-and-true-p flymake-mode)
    (let ((errors 0) (warnings 0))
      (dolist (diag (flymake-diagnostics))
        (let ((severity (flymake--severity (flymake-diagnostic-type diag))))
          (cond ((>= severity (warning-numeric-level :error))   (cl-incf errors))
                ((>= severity (warning-numeric-level :warning)) (cl-incf warnings)))))
      (if (= 0 errors warnings)
          (propertize "✓  " 'face 'success)
        (concat (if (> errors 0) (propertize (format "✗ %d  " errors) 'face 'error) "")
                (if (> warnings 0) (propertize (format "⚠ %d  " warnings) 'face 'warning) ""))))))

;;;; The mode line

(let ((old (default-value 'mode-line-format)))
  (setq-default mode-line-format
                '((:eval (ml/left-side))   ; the buffer name, as a segment
                  (:eval (ml/echo))         ; messages (the echo area)
                  mode-line-format-right-align
                  (:eval (ml/right-side))))
  ;; Buffers made before now (*scratch*, *Messages*...) hold their own copy
  ;; of the old default; bring those along too
  (dolist (buf (buffer-list))
    (with-current-buffer buf
      (when (equal mode-line-format old)
        (setq mode-line-format (default-value 'mode-line-format))))))

;;;; One mode line for the whole frame, in the echo area's line

;; Windows don't draw their own mode lines.  Instead, the echo area's line
;; at the bottom of the frame (as wide as the frame, under treemacs too)
;; shows the mode line of the window you're in, and messages ("Saved
;; file", errors...) appear in it after the buffer name, until your next
;; key.  So the bottom of the frame is one line, not a mode line plus an
;; echo area.  A prompt (M-x, :, y/n...) takes the line over while you
;; answer it.  Popups (child frames) are left alone.

;; Right-aligned parts line up with the edge of the line showing them, not
;; a fixed width taken from the source window
(setq mode-line-right-align-edge 'right-fringe)

;;; Messages

(defvar ml/message nil "The message the bar is showing, or nil.")

(defun ml/echo ()
  "The current message, for the mode line, with room before it."
  (when ml/message
    (propertize (concat "   " ml/message) 'ml/message t)))

(defun ml/take-message (message)
  "Show MESSAGE in the bar, unless a prompt is open (then the echo area
handles it as usual).  For `set-message-functions'."
  (unless (active-minibuffer-window)
    (setq ml/message (car (split-string (substring-no-properties message) "\n")))
    (ml/render-all)
    t))                                 ; handled: not in the echo area

(defun ml/clear-message (&rest _)
  (when ml/message
    (setq ml/message nil)
    (ml/render-all)))

;; After Emacs's own handler, which deals with messages during prompts
(setq set-message-functions
      (append (remq 'ml/take-message set-message-functions)
              '(ml/take-message)))
;; A message lasts until your next key, as in the echo area
(add-hook 'pre-command-hook #'ml/clear-message)

;; Some things write to the echo area without `message' (M-: printing its
;; result, for one); after each command, move whatever is there to the bar
(defun ml/catch-echo ()
  (when-let* (((not (active-minibuffer-window)))
              (text (current-message)))
    (setq ml/message (car (split-string (substring-no-properties text) "\n")))
    (let ((message-log-max nil))        ; already logged; don't log the clear
      (message nil))))
(add-hook 'post-command-hook #'ml/catch-echo -10)

;; Errors from commands go through `message' too, so they land in the bar
(defun ml/command-error (data context signal)
  (ignore signal)
  (discard-input)
  (ding)
  (message "%s%s" (if context (format "%s" context) "")
           (error-message-string data)))
(setq command-error-function #'ml/command-error)

;;; The bar

(defun ml/main-frame-p (frame)
  "Non-nil if FRAME gets the bar: a normal graphical frame with its own
echo area."
  (and (frame-live-p frame)
       (display-graphic-p frame)
       (not (frame-parameter frame 'parent-frame))
       (eq (window-frame (minibuffer-window frame)) frame)))

(defun ml/bar-buffer (frame)
  "FRAME's bar buffer, made on first use."
  (let ((buf (frame-parameter frame 'ml/bar-buffer)))
    (if (buffer-live-p buf)
        buf
      (with-current-buffer (generate-new-buffer " *mode-line*")
        (setq-local mode-line-format nil
                    header-line-format nil
                    cursor-type nil
                    truncate-lines t
                    buffer-read-only t)
        ;; The whole line in the mode-line face, text size included
        (face-remap-add-relative 'default 'mode-line)
        ;; The text ends right at the edge, where Emacs would draw a "$"
        ;; (line cut off) mark: that becomes a blank in the last segment's
        ;; color (see `ml/render')
        (setq-local buffer-display-table (make-display-table))
        (set-frame-parameter frame 'ml/bar-buffer (current-buffer))
        (current-buffer)))))

(defun ml/bar-window (frame)
  "FRAME's echo area line, if it's showing the bar."
  (let ((mini (minibuffer-window frame)))
    (and (eq (window-buffer mini) (frame-parameter frame 'ml/bar-buffer))
         mini)))

(defun ml/show-bar (frame)
  "Put the bar in FRAME's echo area line, unless a prompt is using it.
After a prompt Emacs puts its own empty buffer back, so this runs again."
  (let ((mini (minibuffer-window frame)))
    (unless (or (minibuffer-window-active-p mini) (ml/bar-window frame))
      (set-window-buffer mini (ml/bar-buffer frame))
      (set-window-fringes mini 0 0)
      (set-window-margins mini 0 0))))

(defun ml/hide-window-mode-lines (frame)
  "No mode lines on FRAME's windows; the bar shows the selected one's."
  (dolist (w (window-list frame 'never))
    (set-window-parameter w 'mode-line-format 'none)))

(defun ml/target-window (frame)
  "The window in FRAME whose mode line the bar shows: the one you're in."
  (let ((w (frame-selected-window frame)))
    (if (window-minibuffer-p w)
        (let ((last (frame-parameter frame 'ml/last)))
          (if (and (window-live-p last) (eq (window-frame last) frame))
              last
            (get-mru-window frame nil t)))
      (set-frame-parameter frame 'ml/last w)
      w)))

(defun ml/fit-message (bar gap right-width)
  "Shorten the message in BAR's buffer until the left side ends before
the right side (RIGHT-WIDTH pixels) with a column to spare.  GAP is the
marker before the right side."
  (when-let* ((msg (save-excursion
                     (goto-char (point-min))
                     (text-property-search-forward 'ml/message t t))))
    (let ((room (- (window-body-width bar t) right-width
                   (* 2 (frame-char-width))))
          (start (+ (prop-match-beginning msg) 3))   ; after the room before it
          (end (copy-marker (prop-match-end msg)))
          (cut nil))
      (while (and (> (car (window-text-pixel-size bar (point-min) gap 100000)) room)
                  (> (- end start) 1))
        ;; a few characters at a time, measuring again each time
        (delete-region (max start (- end (if cut 3 1))) end)
        (setq cut t))
      (when cut
        (goto-char end)
        (insert (propertize "…" 'face (get-text-property (max (point-min) (1- end)) 'face)))))))

(defun ml/render (frame)
  "Redraw FRAME's bar from the mode line of the window you're in."
  (ml/show-bar frame)
  (when-let* ((bar (ml/bar-window frame))
              (win (ml/target-window frame)))
    (let* ((buf (window-buffer win))
           (text (format-mode-line (buffer-local-value 'mode-line-format buf)
                                   nil win buf)))
      (with-current-buffer (window-buffer bar)
        ;; Skip redrawing when the text and the line's width are unchanged
        (unless (equal-including-properties (cons (window-body-width bar t) text)
                                            (get-text-property 1 'ml/source))
          (let ((inhibit-read-only t))
            (erase-buffer)
            (insert text)
            (goto-char (point-min))
            ;; Right-align by the right side's real width, measured here
            ;; (Emacs's estimate is off with the full-size arrows).  The
            ;; gap is the (space :align-to ...) that
            ;; `mode-line-format-right-align' puts before the right side.
            ;; With no fringe, Emacs keeps the last column for its "line
            ;; cut off" mark, so the segments end one column early, and one
            ;; more blank spills into that column, where the mark is drawn
            ;; as a blank in the last segment's color (below).
            (when-let* ((gap (text-property-search-forward
                              'display nil
                              (lambda (_ v) (eq (car-safe (cdr-safe v)) :align-to))))
                        (from (prop-match-end gap))
                        ;; no width limit, or the measure is cut at the edge
                        (width (car (window-text-pixel-size bar from (point-max)
                                                            100000))))
              (put-text-property (prop-match-beginning gap) from 'display
                                 `(space :align-to (- right-fringe
                                                      (,(+ width (frame-char-width))))))
              (goto-char (point-max))
              (insert (propertize " " 'face (get-text-property (1- (point)) 'face)))
              (ml/fit-message bar (copy-marker (prop-match-beginning gap)) width))
            (let ((face (get-text-property (max 1 (1- (point-max))) 'face)))
              (set-display-table-slot
               buffer-display-table 'truncation
               (make-glyph-code ?\s (if (consp face) (car (last face)) face))))
            ;; what this was drawn from, to skip redrawing the same thing
            (put-text-property 1 (min 2 (point-max)) 'ml/source
                               (cons (window-body-width bar t) text))
            (goto-char (point-min))))))))

(defun ml/render-all (&rest _)
  "Redraw the bar of every main frame."
  (dolist (frame (frame-list))
    (when (ml/main-frame-p frame)
      (ignore-errors (ml/render frame)))))

(defun ml/on-window-change (&rest _)
  "After windows change: hide their mode lines, keep the bar."
  (let ((frame (selected-frame)))
    (when (ml/main-frame-p frame)
      (ml/hide-window-mode-lines frame)
      (ml/render frame))))

;;; Prompts in a centered popup (M-x) keep the bar

;; A prompt still lives in the bottom line (that's where your typing goes);
;; vertico-posframe shows it in the popup and scrolls it out of sight down
;; there.  Instead, in the bottom line only (overlays limited to that
;; window), the prompt's text is hidden and a copy of the bar is shown in
;; its place, so the popup still shows the prompt as usual.  Prompts
;; without a popup (M-s M-f...) take the line over as before.
(defvar-local ml/prompt-cover nil
  "Overlays over this prompt, in the bottom line only: (HIDE . BAR).")

(defvar-local ml/prompt-cursor nil
  "The prompt's own cursor, (TYPE), while the bottom line hides it.")

(defvar-local ml/prompt-display-table nil
  "The prompt's own display table, (TABLE), while the bar covers it.")

(defun ml/cover-prompt (&rest _)
  "Show the bar in the bottom line while a popup shows the prompt."
  (when-let* ((mini (active-minibuffer-window))
              (frame (window-frame mini))
              ((ml/main-frame-p frame)))
    (set-window-vscroll mini 0)
    (set-window-hscroll mini 0)
    (set-window-fringes mini 0 0)         ; the prompt brings them back
    (with-current-buffer (window-buffer mini)
      (unless ml/prompt-cover
        (setq ml/prompt-cover (cons (make-overlay 1 1) (make-overlay 1 1)))
        (add-hook 'minibuffer-exit-hook #'ml/uncover-prompt nil t))
      (let ((hide (car ml/prompt-cover)) (bar (cdr ml/prompt-cover)))
        ;; the prompt and what you've typed: not shown down there
        (move-overlay hide (point-min) (point-max))
        (overlay-put hide 'window mini)
        (overlay-put hide 'display "")
        ;; the bar, where the cursor is (the end), with the cursor put on
        ;; its first character, so the line never scrolls sideways
        (move-overlay bar (point-max) (point-max))
        (overlay-put bar 'window mini)
        (overlay-put bar 'priority 1000)
        (overlay-put bar 'before-string (ml/bar-copy frame)))
      ;; The bar ends right at the edge, where Emacs draws a "$" (line cut
      ;; off) mark: a blank in the last segment's color instead, as in the bar
      (unless ml/prompt-display-table
        (setq ml/prompt-display-table (list buffer-display-table))
        (setq-local buffer-display-table
                    (copy-sequence (with-current-buffer (ml/bar-buffer frame)
                                     buffer-display-table))))
      ;; No cursor down there: the popup draws its own
      (unless ml/prompt-cursor
        (setq ml/prompt-cursor (list cursor-type)))
      (setq-local cursor-type nil)
      ;; vertico's "1/127" count and candidate list: only in the popup
      ;; (in the bottom line the list would scroll the bar out of sight)
      (when-let* ((popup (seq-find (lambda (w) (not (eq w mini)))
                                   (get-buffer-window-list (current-buffer) nil t))))
        (dolist (ov (list (bound-and-true-p vertico--count-ov)
                          (bound-and-true-p vertico--candidates-ov)))
          (when (overlayp ov)
            (overlay-put ov 'window popup)))))))

(defun ml/uncover-prompt ()
  (when ml/prompt-cover
    (delete-overlay (car ml/prompt-cover))
    (delete-overlay (cdr ml/prompt-cover))
    (setq ml/prompt-cover nil))
  (when ml/prompt-cursor
    (setq-local cursor-type (car ml/prompt-cursor))
    (setq ml/prompt-cursor nil))
  (when ml/prompt-display-table
    (setq-local buffer-display-table (car ml/prompt-display-table))
    (setq ml/prompt-display-table nil)))

(defun ml/popup-keeps-cursor (show buffer &rest args)
  "Run vertico-posframe's SHOW with the prompt's own cursor type, which it
gives the popup; the bottom line hides its cursor again afterwards."
  (when-let* ((saved (buffer-local-value 'ml/prompt-cursor buffer)))
    (with-current-buffer buffer (setq-local cursor-type (car saved))))
  (apply show buffer args))

(defun ml/bar-copy (frame)
  "FRAME's bar as a string to show in a prompt's place.
The prompt's text is scaled (M-x is at 75%), so sizes are made absolute:
the bar's own size, unless a part has its own (the arrows); anything
without a background gets the bar's."
  (let* ((text (with-current-buffer (ml/bar-buffer frame) (buffer-string)))
         (size (round (* (face-attribute 'default :height nil t) ml/height))))
    (add-face-text-property 0 (length text) `(:height ,size) t text)
    (add-face-text-property 0 (length text) 'mode-line t text)
    (when (> (length text) 0)
      (put-text-property 0 1 'cursor t text))
    text))

(with-eval-after-load 'vertico-posframe
  (advice-add 'vertico-posframe--handle-minibuffer-window :after #'ml/cover-prompt)
  ;; again once the popup shows, to find its window for the count
  (advice-add 'vertico-posframe--show :after #'ml/cover-prompt)
  (advice-add 'vertico-posframe--show :around #'ml/popup-keeps-cursor))

(defun ml/forget-frame (frame)
  (let ((buf (frame-parameter frame 'ml/bar-buffer)))
    (when (buffer-live-p buf) (kill-buffer buf))))

(add-hook 'window-configuration-change-hook #'ml/on-window-change)
(add-hook 'post-command-hook #'ml/render-all)
(add-hook 'minibuffer-exit-hook (lambda () (run-at-time 0 nil #'ml/render-all)))
(add-hook 'window-selection-change-functions #'ml/render-all)
(add-hook 'window-buffer-change-functions #'ml/render-all)
(add-hook 'delete-frame-functions #'ml/forget-frame)
;; Things that change while you're idle (diagnostics, compile...)
(defvar ml/idle-timer nil)
(when (timerp ml/idle-timer) (cancel-timer ml/idle-timer))
(setq ml/idle-timer (run-with-idle-timer 1 t #'ml/render-all))

(dolist (frame (frame-list))
  (with-selected-frame frame (ml/on-window-change)))

(provide 'modeline)
