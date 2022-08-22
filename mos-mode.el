;;; mos-mode.el --- MOS toolkit usage in Emacs

;; URL: https://github.com/themkat/mos-mode
;; Version: 0.0.1
;; Package-Requires: ((emacs "24.4") (lsp-mode "8.0.0") (dap-mode "0.7") (dash "2.19.1") (s "1.12.0") (ht "2.3"))

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; Glue code and helpers to make the MOS toolkit (lsp-server, dap-adapter and more) work inside Emacs.
;; This is used to work with MOS 6502 assembly programming projects.
;; https://github.com/datatrash/mos
;; Provides a minor mode for assembly language programs that provide the functionality from MOS if in a MOS project.

;;; Code:

(require 'lsp-mode)
(require 'dap-mode)
(require 'dash)
(require 's)
(require 'ht)

(defcustom mos-executable-path (executable-find "mos")
  "Path to the mos executable"
  :group 'mos-mode
  :type 'string)

;; TODO: better names for this and the above?
(defcustom mos-vice-executable-path (executable-find "x64sc")
  "Path to the VICE executable (either x64 or x64sc)"
  :group 'mos-mode
  :type 'string)

;; simple major mode based on assembly mode that can be activated
(define-derived-mode mos-mode
  asm-mode "MOS mode"
  "Major mode for use with the MOS toolkit for 6502 processors")

(add-to-list 'lsp-language-id-configuration '(mos-mode . "mos"))
(add-to-list 'mos-mode-hook #'lsp)

;; todo: dry!
(defun mos-build ()
  (interactive)
  (let ((default-directory (locate-dominating-file default-directory "mos.toml")))
    (compile (string-join (list mos-mode-executable-path " build")))))

(defun mos-run-all-tests ()
  (interactive)
  (let ((default-directory (locate-dominating-file default-directory "mos.toml")))
    (compile (string-join (list mos-executable-path " test")))))

(defun mos-run-program ()
  (interactive)
  ;; TODO: build. preLaunchTask is probably a vscode thing. 
  (dap-debug (list :type "mos"
                   :request "launch"
                   :name "MOS Run program"
                   :vicePath mos-vice-executable-path
                   :noDebug t)))

(defun mos-debug-program ()
  (interactive)
  ;; TODO: build. preLaunchTask is probably a vscode thing. 
  (dap-debug (list :type "mos"
                   :request "launch"
                   :name "MOS Debug program"
                   :vicePath mos-vice-executable-path
                   :noDebug nil)))

(defun mos-debug-test (no-debug)
  `(lambda (arguments)
     (-let [(&hash "arguments" [test-name]) arguments]
       (dap-debug (list :type "mos"
                        :request "launch"
                        :name (string-join (list "Test " test-name))
                        :testRunner (list :testCaseName test-name)
                        :noDebug ,no-debug)))))
;; TODO: maybe some sort of support if we don't have lenses active?


;; download if dependency not present
(defcustom mos-download-url
  (string-join (list "https://github.com/datatrash/mos/releases/download/0.7.5/mos-0.7.5-x86_64-"
                     (cond ((string-equal "darwin" system-type) "apple-darwin.tar.gz")
                     ((string-equal "gnu/linux" system-type) "unknown-linux-musl.tar.gz")
                     ((string-equal "windows-nt" system-type) "pc-windows-msvc.zip"))))
  
  "Download URL for the mos executable"
  :group 'mos-mode
  :type 'string)

(defvar mos-lsp-download-path (f-join lsp-server-install-dir "mos" "mos"))

(lsp-dependency
 'mos
 (list :system mos-lsp-download-path)
 (list :download
       :url mos-download-url
       ;; TODO: should there be a way to unpack tar.gz in lsp-mode? maybe make a pr for that instead fo hacky shit here...
       :decompress (if (string-equal "windows-nt" system-type) :zip :tgz)
       :store-path (f-join lsp-server-install-dir
                           "mos"
                           "mos")
       :binary-path mos-lsp-download-path
       :set-executable? t))

(lsp-register-client
 (make-lsp-client
  :new-connection (lsp-stdio-connection (lambda () (list (or mos-executable-path
                                                        mos-lsp-download-path) "-v" "lsp")))
  :activation-fn (lsp-activate-on "mos")
  :major-modes '(mos-mode)
  :priority -1
  :server-id 'mos-ls
  :action-handlers (ht ("mos.runSingleTest" (mos-debug-test t))
                       ("mos.debugSingleTest" (mos-debug-test nil)))
  :download-server-fn (lambda (_client callback error-callback _update?)
                        (lsp-package-ensure 'mos callback error-callback))))

(defun mos-mode-populate-debug-args (conf)
  (-> conf
      (dap--put-if-absent :type "mos")
      (dap--put-if-absent :request "launch")
      (dap--put-if-absent :workspace (lsp-workspace-root))
      (dap--put-if-absent :host "127.0.0.1")
      (dap--put-if-absent :debugServer 6503)))

(dap-register-debug-provider "mos" #'mos-mode-populate-debug-args)

(provide 'mos-mode)
;;; mos-mode.el ends here
