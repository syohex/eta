;;; eta.el --- Standard and multi dispatch key bind; -*-

;; Copyright (C) Chris Zheng

;; Author: Chris Zheng
;; Keywords: convenience, usability
;; Homepage: https://www.github.com/zcaudate/eta
;; Package-Requires: ((emacs "25.1"))
;; Version: 0.01

;;; License:

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;;; Commentary:
;;
;; call docker build on org babel block
;;

;;; Requirements:
(require 's)     ;; string
(require 'dash)  ;; list
(require 'ht)    ;; maps

;;; Code:

(defvar eta-*lock* nil)
(defvar eta-*commands*       (ht-create))
(defvar eta-*mode-bindings*  (ht-create))
(defvar eta-*mode-functions* (ht-create))
(defvar eta-*mode-lookup*    (ht-create))

;; Macro Definitions
(defun eta-let-fn (bindings body)
  "Function to create the let macro form.
Argument BINDINGS let bindings.
Optional argument BODY the let body."
  (let ((bargs (seq-reverse (seq-partition bindings 2))))
    (seq-reduce (lambda (body barg)
                  (list '-let barg body))
                bargs
                (cons 'progn body))))

(defmacro eta-let (bindings &rest body)
  "Let with multiple BINDINGS.
Optional argument BODY the let body."
  (declare (indent 1))
  (eta-let-fn bindings body))

(defun eta-put-command (key fn)
  "Gets a command from hashtable.
Argument KEY the command key.
Argument FN the command function."
  (if (and eta-*lock*
           (ht-get eta-*commands* key))
      (error (s-concat "key " (symbol-name key) " already exists"))
    (ht-set eta-*commands* key fn)))

(defun eta-get-command (key)
  "Gets a command function given KEY."
  (gethash key eta-*commands*))

;;
;; eta-bind
;;

(defun eta-bind-fn (declaration &rest specs)
  "Function to generate bind form.
Argument DECLARATION either *, <map> or empty.
Optional argument SPECS the actual bindings."
  (eta-let [bind-map (if (seq-empty-p declaration)
                      nil
                    (seq-elt declaration 0))
         body (seq-mapcat (lambda (spec)
                            (eta-let [(key bindings fn) spec]
                              (if fn
                                  (progn (eta-put-command key (cadr fn))
                                         (seq-map (lambda (binding)
                                                    `(progn ,(if bind-map
                                                                 `(bind-key ,binding ,fn ,bind-map)
                                                               `(bind-key* ,binding ,fn))
                                                            (vector ,key ,binding ,fn)))
                                                  bindings)))))
                          (seq-partition specs 3))]
    (cons 'list body)))

(defmacro eta-bind (declaration &rest specs)
  "Actual binding macro.
Argument DECLARATION ethier [*], <map> or [].
Optional argument SPECS the actual bindings."
  (declare (indent 1))
  (apply 'eta-bind-fn declaration specs))

;;
;; setup for eta-mode
;;
(defun eta-mode-key ()
  "The keys for a mode."
  (ht-get eta-*mode-lookup* major-mode))


(defun eta-mode-dispatch (fn-key &rest args)
  "Function for mode dispatch.
Argument FN-KEY the function key.
Optional argument ARGS function arguments."
  (eta-let [mode-key (ht-get eta-*mode-lookup* major-mode)
         fn-table (if mode-key
                      (ht-get eta-*mode-functions* mode-key))
         fn       (if fn-table
                      (ht-get fn-table fn-key))]
    (if fn
        (apply 'funcall fn args)
      (error (s-concat "Function unavailable ("
                       (symbol-name mode-key)
                       " "
                       (symbol-name fn-key) ")")))))

;;
;; eta-mode-init
;;

(defun eta-mode-init-create-mode-fn (fn-key bindings params)
  "Create a multi function.
Argument FN-KEY the function key.
Argument BINDINGS the bindings for the key.
Argument PARAMS function params."
  (eta-let [fn-name (intern (s-concat "eta-mode-fn"
                                   (symbol-name fn-key)))
         args    (seq-map 'intern params)]
    (ht-set eta-*mode-bindings* fn-key bindings)
    `(progn (defun ,fn-name (,@args)
              (interactive ,@params)
              (eta-mode-dispatch ,fn-key ,@args))
            (eta-bind nil ,fn-key ,bindings (quote ,fn-name)))))

(defun eta-mode-init-form (declaration &rest specs)
  "Initialises the mode form.
Argument DECLARATION The mode form.
Optional argument SPECS the mode specs."
  (eta-let [body (seq-map (lambda (args)
                         (apply 'eta-mode-init-create-mode-fn args))
                       (seq-partition specs 3))]
    (cons 'progn body)))

(defmacro eta-mode-init (declaration &rest specs)
  "The init macro.
Argument DECLARATION The mode-init-macro.
Optional argument SPECS the mode specs."
  (declare (indent 1))
  (apply 'eta-mode-init-form declaration specs))

;;
;; eta-mode
;;

(defun eta-mode-create-config-fn (mode-key mode-name mode-config)
  "The associated config file.
Argument MODE-KEY the key of the mode.
Argument MODE-NAME the mode name.
Argument MODE-CONFIG the mode config."
  (eta-let [fn-name   (intern (s-concat "eta-mode-config"
                                        (symbol-name mode-key)))
         mode-map  (intern (s-concat (symbol-name mode-name) "-map"))]
    `(progn
       (defun ,fn-name ()
         (interactive)
         (eta-jump-to-config ,mode-config))
       (bind-key eta-*meta-config* (quote ,fn-name) ,mode-map))))

(defun eta-mode-form (declaration &rest specs)
  "The mode form.
Argument DECLARATION mode declaration.
Optional argument SPECS mode specs."
  (eta-let [[mode-key mode-name &rest more] declaration
         mode-file-name (if (not (seq-empty-p more)) (seq-elt more 0))
         mode-table (ht-create)
         _    (ht-set eta-*mode-functions* mode-key mode-table)
         _    (ht-set eta-*mode-lookup* mode-name mode-key)
         conf-body (eta-mode-create-config-fn mode-key mode-name (or mode-file-name load-file-name))
         body      (seq-map (lambda (spec)
                              (eta-let [(fn-key fn) spec
                                     mode-fn-key (intern (s-concat (symbol-name fn-key) (symbol-name mode-key)))]
                                (ht-set mode-table fn-key (cadr fn))))
                            (seq-partition specs 2))]
    conf-body))

(defmacro eta-mode (declaration config &rest specs)
  "The eta mode macro.
Argument DECLARATION The mode declaration.
Argument CONFIG the config.
Optional argument SPECS mode specs."
  (declare (indent 1))
  (apply 'eta-mode-form declaration config specs))

(provide 'eta)
;;; eta.el ends here
