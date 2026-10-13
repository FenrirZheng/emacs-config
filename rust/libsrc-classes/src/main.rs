//! `libsrc-classes JAR...` -- print the class index of JARs as one Lisp form.
//!
//! Run by `fenrir/libsrc--index-classes` (lisp/languages/fenrir-libsrc.el).
//! Exit 0 whenever the form was written, even when some or all jars were
//! unreadable: those are listed under `:unreadable` and the Elisp side decides.

use std::io::{self, BufWriter, Write};

fn main() -> io::Result<()> {
    let jars: Vec<String> = std::env::args_os()
        .skip(1)
        .map(|a| a.to_string_lossy().into_owned())
        .collect();
    let listing = libsrc_classes::list_jars(&jars);
    let stdout = io::stdout();
    let mut w = BufWriter::new(stdout.lock());
    libsrc_classes::write_lisp(&mut w, &listing)?;
    w.flush()
}
