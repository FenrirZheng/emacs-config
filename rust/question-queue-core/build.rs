//! Build script: generate raw FFI bindings for the Emacs module ABI.
//!
//! This is the "codegen" half of the module — bindgen reads
//! [`wrapper.h`](wrapper.h) (which `#include`s the system `<emacs-module.h>`)
//! and emits `$OUT_DIR/bindings.rs`, pulled into the crate by
//! [`src/lib.rs`](src/lib.rs)'s `mod bindings`. We hand-write the unsafe
//! marshalling on top (see [`src/emacs.rs`](src/emacs.rs)); bindgen only
//! produces the struct layouts (`emacs_runtime`, `emacs_env`), the
//! `emacs_value` opaque pointer, and the function-pointer field types.

use std::env;
use std::path::PathBuf;

fn main() {
    println!("cargo:rerun-if-changed=wrapper.h");

    let bindings = bindgen::Builder::default()
        .header("wrapper.h")
        // Only the Emacs ABI symbols — don't drag in all of libc's headers.
        .allowlist_type("emacs_.*")
        .allowlist_type("__va_list_tag") // referenced by some env fn-pointers
        .allowlist_var("emacs_.*")
        // The env/runtime structs are versioned by a leading `size` field; keep
        // their layout exactly as the header declares it.
        .layout_tests(false)
        .generate()
        .expect("bindgen: failed to generate emacs-module bindings (is /usr/include/emacs-module.h present? `apt install` an Emacs that ships it)");

    let out = PathBuf::from(env::var("OUT_DIR").expect("OUT_DIR unset"));
    bindings
        .write_to_file(out.join("bindings.rs"))
        .expect("bindgen: failed to write bindings.rs");
}
