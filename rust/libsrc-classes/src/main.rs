//! `libsrc-classes JAR...` -- print the class index of JARs as one Lisp form.
//!
//! Run by `fenrir/libsrc--index-classes` (lisp/languages/fenrir-libsrc.el).
//! Exit 0 whenever the form was written, even when some or all jars were
//! unreadable: those are listed under `:unreadable` and the Elisp side decides.

use std::io::{self, Write};

fn main() -> io::Result<()> {
    let jars: Vec<String> = std::env::args_os()
        .skip(1)
        .map(|a| a.to_string_lossy().into_owned())
        .collect();
    let listing = libsrc_classes::list_jars(&jars);
    // Build the whole form (~2.7 MB for 35k classes) and write it at once:
    // far fewer pipe writes than an 8 KiB BufWriter.
    let mut out = Vec::with_capacity(4 << 20);
    libsrc_classes::write_lisp(&mut out, &listing)?;
    let mut stdout = io::stdout().lock();
    stdout.write_all(&out)?;
    stdout.flush()?;
    // Exit without dropping ~35k index strings: the OS reclaims them faster.
    std::process::exit(0)
}
