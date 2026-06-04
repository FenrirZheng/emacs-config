/* bindgen entry header. The system header lives at /usr/include/emacs-module.h
 * on this machine (Debian trixie) — the same one cpp/junit-core compiles
 * against. build.rs points bindgen at this wrapper so the include path is the
 * default system one; if Emacs is ever installed to a non-standard prefix, add
 * a -I<prefix>/include via clang_arg in build.rs. */
#include <emacs-module.h>
