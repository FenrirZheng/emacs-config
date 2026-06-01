;;; init-go.el --- Go: go-ts-mode + gopls -*- lexical-binding: t; -*-

;;; Commentary:
;; Go language support, split out of the monolithic init-languages.el.
;; The language-agnostic Eglot / tree-sitter / combobulate infrastructure lives
;; in [`lisp/init-languages.el'](../init-languages.el); this module only adds
;; the Go mode hooks and gopls' per-server workspace configuration.
;;
;; See also [`_doc/GO.md'](../../_doc/GO.md) for the full Go workflow.

;;; Code:

;; `eglot-ensure' (autoloaded from the eglot package in init-languages.el) and
;; `combobulate-mode' (`:commands' autoload from the combobulate block there)
;; attach on `go-ts-mode'.  treesit-auto remaps .go files to `go-ts-mode'.
(add-hook 'go-ts-mode-hook #'eglot-ensure)
(add-hook 'go-ts-mode-hook #'combobulate-mode)

;; gopls: extra static analyses + the full inlay-hint set VSCode's Go
;; extension enables by default.  `staticcheck' folds the standalone tool's
;; checks into LSP diagnostics; `gofumpt' is stricter `gofmt' (apheleia /
;; `M-x eglot-format-buffer' both pick this up automatically).  Registered via
;; `with-eval-after-load' so the key is present in the shared
;; `eglot-workspace-configuration' alist before gopls connects.
(with-eval-after-load 'eglot
  (setf (alist-get :gopls eglot-workspace-configuration)
        '(:staticcheck t
          :gofumpt t
          :analyses (:unusedparams t
                     :shadow t
                     :unusedwrite t
                     :nilness t)
          :hints (:assignVariableTypes t
                  :compositeLiteralFields t
                  :compositeLiteralTypes t
                  :constantValues t
                  :functionTypeParameters t
                  :parameterNames t
                  :rangeVariableTypes t))))

;; dape recipe: debug the Go test in the current package.  dape ships a generic
;; `dlv' entry but not a `go test'-shaped one; this `go-test' config makes
;; `M-x dape' offer a one-pick "debug current test" launch (delve's `--mode
;; test').  The launcher key (`C-x C-a d') already comes from dape's own
;; `dape-key-prefix' (see the dape block in init-languages.el) -- only the recipe
;; is new.  `dlv' must be on PATH; it is the one DAP adapter installed today.
;; Registered via `with-eval-after-load' so `dape-configs' exists when we append.
(with-eval-after-load 'dape
  (add-to-list 'dape-configs
               `(go-test
                 modes (go-ts-mode)
                 ensure dape-ensure-command
                 command "dlv"
                 command-args ("dap" "--listen" "127.0.0.1:55878")
                 command-cwd dape-cwd
                 port 55878
                 :type "debug"
                 :request "launch"
                 :mode "test"
                 :program dape-cwd)))

(provide 'init-go)
;;; init-go.el ends here
