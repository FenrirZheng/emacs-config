//! `question-queue-core` — an Emacs dynamic module (raw emacs-module ABI via
//! bindgen) backing the `question-queue.el` front-end.
//!
//! Native surface (registered in [`emacs_module_init`]):
//!   - `(qq-core-submit REGION QUESTION LANG SOURCE-FILE INPUT-DIR)` → basename
//!       Assemble a markdown request and atomically drop it into INPUT-DIR.
//!   - `(qq-core-parse-answer OUTPUT-TEXT)` → cleaned answer body string.
//!   - `(qq-core-version)` → version string (used by the Makefile `verify`).
//!
//! The module is pure compute + local file I/O — it never launches a process
//! or watches a directory; that is Elisp's job (region capture, the `output/`
//! `file-notify` watch, and display). Mirrors the C++ junit-core split.

// bindgen output: raw struct layouts + the opaque `emacs_value`. All the unsafe
// marshalling lives in `emacs.rs` on top of these.
mod bindings {
    #![allow(
        non_upper_case_globals,
        non_camel_case_types,
        non_snake_case,
        dead_code
    )]
    include!(concat!(env!("OUT_DIR"), "/bindings.rs"));
}

mod answer;
mod emacs;
mod request;

use bindings::{emacs_env, emacs_runtime, emacs_value};
use emacs::Env;
use std::os::raw::{c_int, c_void};
use std::panic::{catch_unwind, AssertUnwindSafe};

/// Required by Emacs: the symbol's presence asserts a GPL-compatible module.
#[no_mangle]
#[allow(non_upper_case_globals)]
pub static plugin_is_GPL_compatible: c_int = 0;

/// Emacs `module-load` entry point. Registers the subrs and `provide`s the
/// feature. Returns non-zero to refuse loading (incompatible ABI).
///
/// # Safety
/// Called by Emacs with a valid `*mut emacs_runtime`.
#[no_mangle]
pub unsafe extern "C" fn emacs_module_init(runtime: *mut emacs_runtime) -> c_int {
    let env = match Env::from_runtime(runtime) {
        Some(e) => e,
        None => return 1,
    };
    env.defun("qq-core-submit", 5, 5, qq_core_submit, DOC_SUBMIT);
    env.defun("qq-core-parse-answer", 1, 1, qq_core_parse_answer, DOC_PARSE);
    env.defun("qq-core-version", 0, 0, qq_core_version, DOC_VERSION);
    env.provide("question-queue-core");
    0
}

const DOC_SUBMIT: &str = "Assemble a markdown request and atomically write it into INPUT-DIR.\n\
REGION and QUESTION are strings; LANG is a fenced-code language tag; SOURCE-FILE\n\
may be nil. Returns the basename of the file written.\n\
\n(fn REGION QUESTION LANG SOURCE-FILE INPUT-DIR)";

const DOC_PARSE: &str = "Return the cleaned answer body from OUTPUT-TEXT.\n\
Trims whitespace, unwraps a single enclosing code fence, and strips an echoed\n\
YAML front-matter block if present.\n\
\n(fn OUTPUT-TEXT)";

const DOC_VERSION: &str = "Return the question-queue-core module version string.\n\n(fn)";

// ---------------------------------------------------------------------------
// Trampolines. Each one owns a `catch_unwind` so a Rust panic becomes an Elisp
// `error' instead of unwinding across the FFI boundary (UB) and killing Emacs.
// ---------------------------------------------------------------------------

unsafe extern "C" fn qq_core_submit(
    env: *mut emacs_env,
    _nargs: isize,
    args: *mut emacs_value,
    _data: *mut c_void,
) -> emacs_value {
    let e = Env::new(env);
    let out = catch_unwind(AssertUnwindSafe(|| {
        let region = e.extract_string(*args.add(0)).unwrap_or_default();
        let question = e.extract_string(*args.add(1)).unwrap_or_default();
        let lang = e.extract_string(*args.add(2)).unwrap_or_default();
        let source = e.extract_string(*args.add(3)); // nil => None
        let input_dir = match e.extract_string(*args.add(4)) {
            Some(s) if !s.is_empty() => s,
            _ => {
                e.signal_error("qq-core-submit: INPUT-DIR must be a non-empty string");
                return e.nil();
            }
        };
        match request::submit(&region, &question, &lang, source.as_deref(), &input_dir) {
            Ok(filename) => e.make_string(&filename),
            Err(err) => {
                e.signal_error(&format!("qq-core-submit: {err}"));
                e.nil()
            }
        }
    }));
    out.unwrap_or_else(|_| {
        e.signal_error("qq-core-submit: panicked");
        e.nil()
    })
}

unsafe extern "C" fn qq_core_parse_answer(
    env: *mut emacs_env,
    _nargs: isize,
    args: *mut emacs_value,
    _data: *mut c_void,
) -> emacs_value {
    let e = Env::new(env);
    let out = catch_unwind(AssertUnwindSafe(|| {
        let text = e.extract_string(*args.add(0)).unwrap_or_default();
        e.make_string(&answer::parse(&text))
    }));
    out.unwrap_or_else(|_| {
        e.signal_error("qq-core-parse-answer: panicked");
        e.nil()
    })
}

unsafe extern "C" fn qq_core_version(
    env: *mut emacs_env,
    _nargs: isize,
    _args: *mut emacs_value,
    _data: *mut c_void,
) -> emacs_value {
    let e = Env::new(env);
    e.make_string(concat!("question-queue-core ", env!("CARGO_PKG_VERSION")))
}
