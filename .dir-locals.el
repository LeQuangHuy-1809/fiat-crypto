((coq-mode . ((eval . (let* ((project-root (locate-dominating-file buffer-file-name "_CoqProject"))
                             (coqprime-folder (expand-file-name "coqprime/src" project-root))
                             (rewriter-folder (expand-file-name "rewriter/src" project-root))
                             (rupicola-folder (expand-file-name "rupicola/src" project-root))
                             (bedrock2-folder (expand-file-name "rupicola/bedrock2/bedrock2/src" project-root))
                             (compiler-folder (expand-file-name "rupicola/bedrock2/compiler/src" project-root))
                             (riscvcoq-folder (expand-file-name "rupicola/bedrock2/deps/riscv-coq/src" project-root))
                             (coqutil-folder (expand-file-name "rupicola/bedrock2/deps/coqutil/src" project-root))
                             (coq-path (lambda () (split-string (or (getenv "COQPATH") "") path-separator t))))
                        (unless (member coqutil-folder (funcall coq-path))
                          (setenv "COQPATH" (mapconcat #'identity (cons coqutil-folder (funcall coq-path)) path-separator)))
                        (unless (member rewriter-folder (funcall coq-path))
                          (setenv "COQPATH" (mapconcat #'identity (cons rewriter-folder (funcall coq-path)) path-separator)))
                        (unless (member rupicola-folder (funcall coq-path))
                          (setenv "COQPATH" (mapconcat #'identity (cons rupicola-folder (funcall coq-path)) path-separator)))
                        (unless (member bedrock2-folder (funcall coq-path))
                          (setenv "COQPATH" (mapconcat #'identity (cons bedrock2-folder (funcall coq-path)) path-separator)))
                        (unless (member compiler-folder (funcall coq-path))
                          (setenv "COQPATH" (mapconcat #'identity (cons compiler-folder (funcall coq-path)) path-separator)))
                        (unless (member riscvcoq-folder (funcall coq-path))
                          (setenv "COQPATH" (mapconcat #'identity (cons riscvcoq-folder (funcall coq-path)) path-separator)))
                        (unless (member coqprime-folder (funcall coq-path))
                          (setenv "COQPATH" (mapconcat #'identity (cons coqprime-folder (funcall coq-path)) path-separator))))))))
