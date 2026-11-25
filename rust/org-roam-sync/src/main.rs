use std::path::PathBuf;
use std::process;

use org_roam_sync::{run_sync, SyncConfig, SyncError};

fn print_usage() {
    eprintln!(
        "Usage: org-roam-sync --dir DIR [--db PATH] [--exclude REGEX]... [--exclude-elisp REGEX]... [--ext EXT]... [--force] [--ignore-case] [--emit-org-ids | --org-id-out PATH]"
    );
}

fn parse_args() -> Result<SyncConfig, String> {
    let mut args = std::env::args().skip(1);
    let mut dir: Option<PathBuf> = None;
    let mut db: Option<PathBuf> = None;
    let mut excludes: Vec<String> = Vec::new();
    let mut exclude_elisp: Vec<String> = Vec::new();
    let mut exts: Vec<String> = Vec::new();
    let mut force = false;
    let mut ignore_case = false;
    let mut emit_org_ids = false;
    let mut org_id_out: Option<PathBuf> = None;

    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--dir" => {
                let v = args
                    .next()
                    .ok_or_else(|| "--dir requires a value".to_string())?;
                dir = Some(PathBuf::from(v));
            }
            "--db" => {
                let v = args
                    .next()
                    .ok_or_else(|| "--db requires a value".to_string())?;
                db = Some(PathBuf::from(v));
            }
            "--exclude" => {
                let v = args
                    .next()
                    .ok_or_else(|| "--exclude requires a value".to_string())?;
                excludes.push(v);
            }
            "--exclude-elisp" => {
                let v = args
                    .next()
                    .ok_or_else(|| "--exclude-elisp requires a value".to_string())?;
                exclude_elisp.push(v);
            }
            "--ext" => {
                let v = args
                    .next()
                    .ok_or_else(|| "--ext requires a value".to_string())?;
                exts.push(v);
            }
            "--force" => {
                force = true;
            }
            "--ignore-case" => {
                ignore_case = true;
            }
            "--emit-org-ids" => {
                emit_org_ids = true;
            }
            "--org-id-out" => {
                let v = args
                    .next()
                    .ok_or_else(|| "--org-id-out requires a value".to_string())?;
                org_id_out = Some(PathBuf::from(v));
            }
            "-h" | "--help" => {
                print_usage();
                process::exit(0);
            }
            other => {
                return Err(format!("unknown argument: {}", other));
            }
        }
    }

    let dir = dir.ok_or_else(|| "--dir DIR is required".to_string())?;
    Ok(SyncConfig {
        dir,
        db,
        excludes,
        exclude_elisp,
        exts,
        force,
        ignore_case,
        emit_org_ids,
        org_id_out,
    })
}

fn main() {
    let cfg = match parse_args() {
        Ok(c) => c,
        Err(e) => {
            eprintln!("org-roam-sync: {}", e);
            print_usage();
            process::exit(1);
        }
    };

    match run_sync(&cfg) {
        Ok(()) => {}
        Err(SyncError::EncryptedFilesPresent(p)) => {
            eprintln!("org-roam-sync: encrypted file requires Emacs fallback: {}", p.display());
            process::exit(2);
        }
        Err(SyncError::Message(m)) => {
            eprintln!("org-roam-sync: {}", m);
            process::exit(1);
        }
    }
}
