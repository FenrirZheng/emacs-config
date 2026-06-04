//! Safe-ish wrappers over the raw Emacs module ABI.
//!
//! bindgen ([`build.rs`](../build.rs)) gives us the struct layouts and opaque
//! `emacs_value`; everything here is the hand-written unsafe marshalling on top
//! — interning symbols, moving strings across the boundary, calling Elisp
//! functions, registering native subrs, and raising Elisp errors.
//!
//! ## Why we transmute the env function pointers
//!
//! Every callable in `emacs_env` is an `Option<unsafe extern "C" fn(...)>`
//! field. For the ones whose signature mentions `ptrdiff_t`, different bindgen
//! versions spell that argument differently (`isize` vs `c_long`), which would
//! make `Some(my_fn)` fail to type-check against the field. Since the ABI is
//! fixed (C calling convention, pointer-width integers), we `transmute` the
//! field to a locally-declared, ABI-stable `fn`-pointer type and call through
//! that — decoupling us from bindgen's exact emission. Fn-pointer transmute is
//! size/ABI-safe here.

use crate::bindings::{emacs_env, emacs_runtime, emacs_value};
use std::ffi::CString;
use std::mem::{size_of, transmute};
use std::os::raw::{c_char, c_void};
use std::ptr;

/// The C type of a native subr: `emacs_value (*)(env, nargs, args, data)`.
/// Our `#[no_mangle]` trampolines in [`lib.rs`](lib.rs) have exactly this type.
pub type SubrFn =
    unsafe extern "C" fn(*mut emacs_env, isize, *mut emacs_value, *mut c_void) -> emacs_value;

// ABI-stable local signatures for the env fn-pointers we call (see module doc).
type FnMakeString = unsafe extern "C" fn(*mut emacs_env, *const c_char, isize) -> emacs_value;
type FnCopyString =
    unsafe extern "C" fn(*mut emacs_env, emacs_value, *mut c_char, *mut isize) -> bool;
type FnFuncall =
    unsafe extern "C" fn(*mut emacs_env, emacs_value, isize, *mut emacs_value) -> emacs_value;
type FnMakeFunction = unsafe extern "C" fn(
    *mut emacs_env,
    isize,
    isize,
    Option<SubrFn>,
    *const c_char,
    *mut c_void,
) -> emacs_value;

/// A live `emacs_env` for the duration of one module call.
#[derive(Clone, Copy)]
pub struct Env {
    env: *mut emacs_env,
}

impl Env {
    /// Wrap a raw env pointer handed to a subr trampoline.
    pub fn new(env: *mut emacs_env) -> Self {
        Env { env }
    }

    /// Extract the env from the runtime at `emacs_module_init`, refusing to run
    /// against an Emacs older than the headers we compiled against (the leading
    /// `size` field is the ABI version guard — mirrors junit-core's check).
    ///
    /// # Safety
    /// `rt` must be the valid runtime pointer Emacs passed to the init fn.
    pub unsafe fn from_runtime(rt: *mut emacs_runtime) -> Option<Self> {
        if rt.is_null() || ((*rt).size as usize) < size_of::<emacs_runtime>() {
            return None;
        }
        let get_env = (*rt).get_environment?;
        let env = get_env(rt);
        if env.is_null() || ((*env).size as usize) < size_of::<emacs_env>() {
            return None;
        }
        Some(Env { env })
    }

    // ---- core value operations --------------------------------------------

    /// `(intern NAME)` — never NUL-bearing for our fixed call sites.
    pub unsafe fn intern(&self, name: &str) -> emacs_value {
        let c = CString::new(name).expect("intern: interior NUL in symbol name");
        ((*self.env).intern.expect("env->intern is null"))(self.env, c.as_ptr())
    }

    /// `nil`.
    pub unsafe fn nil(&self) -> emacs_value {
        self.intern("nil")
    }

    /// Build an Elisp multibyte string from UTF-8 bytes.
    pub unsafe fn make_string(&self, s: &str) -> emacs_value {
        let f: FnMakeString = transmute((*self.env).make_string.expect("env->make_string is null"));
        f(self.env, s.as_ptr() as *const c_char, s.len() as isize)
    }

    /// Pull a Rust `String` out of an Elisp value, or `None` if it is not a
    /// string (the failed `copy_string_contents` sets a non-local exit, which
    /// we clear so the caller can decide what to do).
    pub unsafe fn extract_string(&self, val: emacs_value) -> Option<String> {
        let f: FnCopyString =
            transmute((*self.env).copy_string_contents.expect("env->copy_string_contents is null"));
        let mut len: isize = 0;
        // First call: NULL buffer => Emacs writes the required size (incl. NUL).
        if !f(self.env, val, ptr::null_mut(), &mut len) {
            self.clear_exit();
            return None;
        }
        if len <= 1 {
            return Some(String::new());
        }
        let mut buf = vec![0 as c_char; len as usize];
        if !f(self.env, val, buf.as_mut_ptr(), &mut len) {
            self.clear_exit();
            return None;
        }
        // `len` now counts the trailing NUL; the payload is the first len-1 bytes.
        let bytes =
            std::slice::from_raw_parts(buf.as_ptr() as *const u8, (len as usize).saturating_sub(1));
        Some(String::from_utf8_lossy(bytes).into_owned())
    }

    /// `(funcall FUNC ARGS...)`. FUNC may be a symbol (Emacs resolves it).
    pub unsafe fn funcall(&self, func: emacs_value, args: &[emacs_value]) -> emacs_value {
        let f: FnFuncall = transmute((*self.env).funcall.expect("env->funcall is null"));
        f(
            self.env,
            func,
            args.len() as isize,
            args.as_ptr() as *mut emacs_value,
        )
    }

    // ---- registration ------------------------------------------------------

    /// Register NAME as a native function: `(fset 'NAME (make-function ...))`.
    pub unsafe fn defun(&self, name: &str, min: isize, max: isize, func: SubrFn, doc: &str) {
        let mkfn: FnMakeFunction =
            transmute((*self.env).make_function.expect("env->make_function is null"));
        let doc_c = CString::new(doc).unwrap_or_else(|_| CString::new("").unwrap());
        let fnval = mkfn(self.env, min, max, Some(func), doc_c.as_ptr(), ptr::null_mut());
        let fset = self.intern("fset");
        let sym = self.intern(name);
        self.funcall(fset, &[sym, fnval]);
    }

    /// `(provide 'FEATURE)`.
    pub unsafe fn provide(&self, feature: &str) {
        let provide_fn = self.intern("provide");
        let sym = self.intern(feature);
        self.funcall(provide_fn, &[sym]);
    }

    // ---- error / exit handling --------------------------------------------

    /// Raise `(error MSG)` in the calling Elisp. After this the env is in a
    /// pending-exit state; subsequent env calls no-op and the trampoline's
    /// return value is ignored by Emacs, so returning `nil()` afterwards is fine.
    pub unsafe fn signal_error(&self, msg: &str) {
        let err_sym = self.intern("error");
        let s = self.make_string(msg);
        let list_fn = self.intern("list");
        let data = self.funcall(list_fn, &[s]);
        if let Some(sig) = (*self.env).non_local_exit_signal {
            sig(self.env, err_sym, data);
        }
    }

    /// Clear a pending non-local exit (used after a probed type mismatch).
    unsafe fn clear_exit(&self) {
        if let Some(clear) = (*self.env).non_local_exit_clear {
            clear(self.env);
        }
    }
}
