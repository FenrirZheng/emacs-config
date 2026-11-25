//! `claude-jobs-scan` -- fast parallel scanner for jobctl sessions,
//! /proc liveness, daemon `state.json`, and JSONL transcript heads.

use std::io::{self, Write};
use std::process;

fn main() -> io::Result<()> {
    let args: Vec<std::ffi::OsString> = std::env::args_os().skip(1).collect();
    let cfg = match claude_jobs_scan::parse_args(&args) {
        Ok(Some(c)) => c,
        Ok(None) => {
            print!("{}", claude_jobs_scan::USAGE);
            return Ok(());
        }
        Err(msg) => {
            eprintln!("claude-jobs-scan: {msg}");
            process::exit(2);
        }
    };

    let mut out = Vec::with_capacity(64 * 1024);
    if let Some(ref uuid) = cfg.uuid {
        let session = claude_jobs_scan::scan_uuid(&cfg, uuid);
        claude_jobs_scan::write_uuid_lisp(&mut out, session.as_ref())?;
    } else {
        let result = claude_jobs_scan::scan_all(&cfg);
        claude_jobs_scan::write_full_lisp(&mut out, &result)?;
    }

    let mut stdout = io::stdout().lock();
    stdout.write_all(&out)?;
    stdout.flush()?;
    process::exit(0)
}
