pub mod db;
pub mod parser;
pub mod sexpr;

use std::collections::{HashMap, HashSet};
use std::fmt::Write as _;
use std::fs;
use std::path::{Path, PathBuf};
use std::time::SystemTime;

use rayon::prelude::*;
use regex::{Regex, RegexBuilder};
use sha1::{Digest, Sha1};
use walkdir::WalkDir;

use db::{apply_updates, load_existing_file_hashes, open_db, FileUpdate};
use parser::{extract_org_ids_only, parse_org_file};
use sexpr::{
    abbreviate_file_name, format_emacs_time, format_id_locations_alist,
    merge_and_write_id_locations, prin1_string,
};

#[derive(Debug, Clone)]
pub struct SyncConfig {
    pub dir: PathBuf,
    pub db: Option<PathBuf>,
    pub excludes: Vec<String>,
    pub exclude_elisp: Vec<String>,
    pub exts: Vec<String>,
    pub force: bool,
    pub ignore_case: bool,
    pub emit_org_ids: bool,
    pub org_id_out: Option<PathBuf>,
}

#[derive(Debug)]
pub enum SyncError {
    EncryptedFilesPresent(PathBuf),
    Message(String),
}

impl std::fmt::Display for SyncError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            SyncError::EncryptedFilesPresent(p) => {
                write!(f, "encrypted org file requires Emacs fallback: {}", p.display())
            }
            SyncError::Message(m) => f.write_str(m),
        }
    }
}

#[derive(Debug, Clone)]
struct DiscoveredFile {
    /// Lexical path under `dir` (`dir.join(rel)`) matching Emacs `find -L` + `expand-file-name`.
    lexical_path: PathBuf,
    /// Relative path with `/` separators.
    rel_path: String,
    is_encrypted: bool,
}

#[derive(Debug)]
struct ScannedEntry {
    lexical_path_str: String,
    raw_bytes: Vec<u8>,
    hash: String,
    atime: String,
    mtime: String,
    canonical_abbrev: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
enum ClassToken {
    Posix(String),
    Char(char),
}

fn push_class_char(out: &mut String, ch: char) {
    if matches!(ch, '\\' | '[' | ']' | '-' | '&' | '~' | '^') {
        out.push('\\');
    }
    out.push(ch);
}

/// Convert an Elisp regexp to Rust `regex` syntax for `--exclude-elisp`.
pub fn translate_elisp_regex(re: &str) -> Result<String, SyncError> {
    let mut out = String::with_capacity(re.len());
    let bytes = re.as_bytes();
    let mut i = 0;
    let mut at_anchor_start = true;
    let mut at_quantifier_start = true;
    let mut after_interval = false;

    while i < bytes.len() {
        let b = bytes[i];
        if b == b'\\' {
            if i + 1 >= bytes.len() {
                return Err(SyncError::Message(format!(
                    "trailing backslash in Elisp exclude regex {:?}",
                    re
                )));
            }
            match bytes[i + 1] {
                b'`' => {
                    out.push('^');
                    i += 2;
                    at_anchor_start = false;
                    at_quantifier_start = true;
                    after_interval = false;
                }
                b'\'' => {
                    out.push('$');
                    i += 2;
                    at_anchor_start = false;
                    at_quantifier_start = true;
                    after_interval = false;
                }
                b'(' => {
                    // Only `\(?:...\)` shy groups are supported after `\(?`; reject numbered `(?1:...)` and flags `(?i:...)`.
                    if bytes.get(i + 2) == Some(&b'?') {
                        if bytes.get(i + 3) == Some(&b':') {
                            out.push_str("(?:");
                            i += 4;
                        } else {
                            return Err(SyncError::Message(format!(
                                "unsupported Elisp group construct in {:?}",
                                re
                            )));
                        }
                    } else {
                        out.push('(');
                        i += 2;
                    }
                    at_anchor_start = true;
                    at_quantifier_start = true;
                    after_interval = false;
                }
                b')' => {
                    out.push(')');
                    i += 2;
                    at_anchor_start = false;
                    at_quantifier_start = false;
                    after_interval = false;
                }
                b'|' => {
                    out.push('|');
                    i += 2;
                    at_anchor_start = true;
                    at_quantifier_start = true;
                    after_interval = false;
                }
                b'{' => {
                    let Some(end_rel) = re[i + 2..].find("\\}") else {
                        return Err(SyncError::Message(format!(
                            "unclosed \\{{...\\}} in Elisp exclude regex {:?}",
                            re
                        )));
                    };
                    let inner = &re[i + 2..i + 2 + end_rel];
                    let valid_interval = inner.is_empty()
                        || (inner.bytes().all(|c| c.is_ascii_digit() || c == b',')
                            && inner.bytes().filter(|&c| c == b',').count() <= 1);
                    if !valid_interval {
                        return Err(SyncError::Message(format!(
                            "invalid \\{{...\\}} content in Elisp exclude regex {:?}",
                            re
                        )));
                    }
                    if at_quantifier_start {
                        out.push_str("\\{");
                        out.push_str(inner);
                        out.push_str("\\}");
                        after_interval = false;
                    } else {
                        if inner.is_empty() {
                            out.push_str("{0,0}");
                        } else if let Some((lo, hi)) = inner.split_once(',') {
                            out.push('{');
                            if lo.is_empty() {
                                out.push('0');
                            } else {
                                out.push_str(lo);
                            }
                            out.push(',');
                            out.push_str(hi);
                            out.push('}');
                        } else {
                            out.push('{');
                            out.push_str(inner);
                            out.push('}');
                        }
                        after_interval = true;
                    }
                    i = i + 2 + end_rel + 2;
                    at_anchor_start = false;
                    at_quantifier_start = false;
                }
                b'}' => {
                    out.push_str("\\}");
                    i += 2;
                    at_anchor_start = false;
                    at_quantifier_start = false;
                    after_interval = false;
                }
                b'\\' => {
                    out.push_str("\\\\");
                    i += 2;
                    at_anchor_start = false;
                    at_quantifier_start = false;
                    after_interval = false;
                }
                b'=' | b'_' | b's' | b'S' | b'c' | b'C' | b'w' | b'W' | b'<' | b'>' | b'b'
                | b'B' | b'1'..=b'9' => {
                    return Err(SyncError::Message(format!(
                        "unsupported Elisp regexp escape \\{} in {:?}",
                        bytes[i + 1] as char, re
                    )));
                }
                _ => {
                    let ch = re[i + 1..].chars().next().unwrap();
                    if matches!(
                        ch,
                        '^' | '$'
                            | '.'
                            | '*'
                            | '+'
                            | '?'
                            | '['
                            | ']'
                            | '\\'
                            | '('
                            | ')'
                            | '|'
                            | '{'
                            | '}'
                            | '-'
                            | '/'
                    ) {
                        out.push('\\');
                    }
                    out.push(ch);
                    i += 1 + ch.len_utf8();
                    at_anchor_start = false;
                    at_quantifier_start = false;
                    after_interval = false;
                }
            }
            continue;
        }

        if b == b'[' {
            out.push('[');
            i += 1;
            if i < bytes.len() && bytes[i] == b'^' {
                out.push('^');
                i += 1;
            }
            let mut tokens: Vec<ClassToken> = Vec::new();
            let mut closed = false;
            let mut first_in_class = true;
            while i < bytes.len() {
                let cb = bytes[i];
                if cb == b']' && !first_in_class {
                    i += 1;
                    closed = true;
                    break;
                }
                first_in_class = false;
                if cb == b'[' && i + 1 < bytes.len() && bytes[i + 1] == b':' {
                    if let Some(end_rel) = re[i + 2..].find(":]") {
                        let cls_name = &re[i + 2..i + 2 + end_rel];
                        if matches!(cls_name, "word" | "unibyte" | "multibyte" | "nonascii") {
                            return Err(SyncError::Message(format!(
                                "unsupported Elisp POSIX class [:{}:] in {:?}",
                                cls_name, re
                            )));
                        }
                        tokens.push(ClassToken::Posix(cls_name.to_string()));
                        i = i + 2 + end_rel + 2;
                        continue;
                    }
                }
                let ch = re[i..].chars().next().unwrap();
                tokens.push(ClassToken::Char(ch));
                i += ch.len_utf8();
            }
            if !closed {
                return Err(SyncError::Message(format!(
                    "unclosed character class in Elisp exclude regex {:?}",
                    re
                )));
            }
            for (idx_t, tok) in tokens.iter().enumerate() {
                if *tok == ClassToken::Char('-') {
                    let prev_posix =
                        idx_t > 0 && matches!(tokens[idx_t - 1], ClassToken::Posix(_));
                    let next_posix =
                        idx_t + 1 < tokens.len() && matches!(tokens[idx_t + 1], ClassToken::Posix(_));
                    if prev_posix || next_posix {
                        return Err(SyncError::Message(format!(
                            "unsupported POSIX class dash combination in Elisp exclude regex {:?}",
                            re
                        )));
                    }
                }
            }
            let mut emitted = 0usize;
            let mut k = 0usize;
            while k < tokens.len() {
                if k + 2 < tokens.len() {
                    if let (
                        ClassToken::Char(start_ch),
                        ClassToken::Char('-'),
                        ClassToken::Char(end_ch),
                    ) = (&tokens[k], &tokens[k + 1], &tokens[k + 2])
                    {
                        if start_ch <= end_ch {
                            push_class_char(&mut out, *start_ch);
                            out.push('-');
                            push_class_char(&mut out, *end_ch);
                            emitted += 1;
                        }
                        k += 3;
                        continue;
                    }
                }
                match &tokens[k] {
                    ClassToken::Posix(cls) => {
                        out.push_str("[:");
                        out.push_str(cls);
                        out.push_str(":]");
                        emitted += 1;
                    }
                    ClassToken::Char(ch) => {
                        push_class_char(&mut out, *ch);
                        emitted += 1;
                    }
                }
                k += 1;
            }
            if emitted == 0 {
                return Err(SyncError::Message(format!(
                    "empty character class in Elisp exclude regex {:?}",
                    re
                )));
            }
            out.push(']');
            at_anchor_start = false;
            at_quantifier_start = false;
            after_interval = false;
            continue;
        }

        if b == b'^' {
            if at_anchor_start {
                out.push('^');
                at_quantifier_start = true;
            } else {
                out.push_str("\\^");
                at_quantifier_start = false;
            }
            i += 1;
            at_anchor_start = false;
            after_interval = false;
            continue;
        }

        if b == b'$' {
            let is_anchor = i + 1 == bytes.len()
                || (i + 2 < bytes.len()
                    && bytes[i + 1] == b'\\'
                    && (bytes[i + 2] == b')' || bytes[i + 2] == b'|'));
            if is_anchor {
                out.push('$');
                at_quantifier_start = true;
            } else {
                out.push_str("\\$");
                at_quantifier_start = false;
            }
            i += 1;
            at_anchor_start = false;
            after_interval = false;
            continue;
        }

        if matches!(b, b'*' | b'+' | b'?') {
            if after_interval && b == b'?' {
                return Err(SyncError::Message(format!(
                    "unsupported interval+optional quantifier \\{{...\\}}? in Elisp exclude regex {:?}",
                    re
                )));
            }
            if at_quantifier_start {
                out.push('\\');
            }
            out.push(b as char);
            i += 1;
            at_anchor_start = false;
            at_quantifier_start = false;
            after_interval = false;
            continue;
        }

        if matches!(b, b'(' | b')' | b'|' | b'{' | b'}') {
            out.push('\\');
            out.push(b as char);
            i += 1;
            at_anchor_start = false;
            at_quantifier_start = false;
            after_interval = false;
            continue;
        }

        let ch = re[i..].chars().next().unwrap();
        out.push(ch);
        i += ch.len_utf8();
        at_anchor_start = false;
        at_quantifier_start = false;
        after_interval = false;
    }

    Ok(out)
}

fn compile_excludes(
    rust_patterns: &[String],
    elisp_patterns: &[String],
    ignore_case: bool,
) -> Result<Vec<Regex>, SyncError> {
    let mut compiled = Vec::with_capacity(rust_patterns.len() + elisp_patterns.len());
    for pat in rust_patterns {
        let rx = RegexBuilder::new(pat)
            .case_insensitive(ignore_case)
            .build()
            .map_err(|e| SyncError::Message(format!("invalid exclude regex {:?}: {}", pat, e)))?;
        compiled.push(rx);
    }
    for pat in elisp_patterns {
        let translated = translate_elisp_regex(pat)?;
        let rx = RegexBuilder::new(&translated)
            .case_insensitive(ignore_case)
            .build()
            .map_err(|e| {
                SyncError::Message(format!("invalid exclude-elisp regex {:?}: {}", pat, e))
            })?;
        compiled.push(rx);
    }
    Ok(compiled)
}

fn strip_encrypted_ext(file_name: &str) -> (&str, bool) {
    if let Some(stem) = file_name.strip_suffix(".gpg") {
        (stem, true)
    } else if let Some(stem) = file_name.strip_suffix(".age") {
        (stem, true)
    } else {
        (file_name, false)
    }
}

fn has_matching_extension(path: &Path, exts: &[String]) -> (bool, bool) {
    let Some(name) = path.file_name().and_then(|s| s.to_str()) else {
        return (false, false);
    };
    let (base_name, is_enc) = strip_encrypted_ext(name);
    let Some(dot) = base_name.rfind('.') else {
        return (false, is_enc);
    };
    if dot == 0 {
        return (false, is_enc);
    }
    let ext = &base_name[dot + 1..];
    (exts.iter().any(|e| e == ext), is_enc)
}

fn normalize_dir(dir: &Path) -> Result<PathBuf, SyncError> {
    let abs = if dir.is_absolute() {
        dir.to_path_buf()
    } else {
        std::env::current_dir()
            .map_err(|e| SyncError::Message(format!("getcwd failed: {}", e)))?
            .join(dir)
    };
    // Strip trailing slashes except root `/`
    let s = abs.to_string_lossy();
    let trimmed = s.trim_end_matches('/');
    if trimmed.is_empty() {
        Ok(PathBuf::from("/"))
    } else {
        Ok(PathBuf::from(trimmed))
    }
}

fn is_ignored_walkdir_error(err: &walkdir::Error) -> bool {
    if err.loop_ancestor().is_some() {
        return true;
    }
    err.io_error().map_or(false, |io| {
        if io.kind() == std::io::ErrorKind::NotFound {
            return true;
        }
        #[cfg(target_os = "linux")]
        {
            if io.raw_os_error() == Some(40) {
                return true;
            }
        }
        #[cfg(all(unix, not(target_os = "linux")))]
        {
            if matches!(io.raw_os_error(), Some(40) | Some(62)) {
                return true;
            }
        }
        false
    })
}

fn discover_files(
    dir: &Path,
    exts: &[String],
    excludes: &[Regex],
) -> Result<Vec<DiscoveredFile>, SyncError> {
    if !dir.is_dir() {
        return Err(SyncError::Message(format!(
            "directory does not exist: {}",
            dir.display()
        )));
    }

    let mut files = Vec::new();
    for entry in WalkDir::new(dir).follow_links(true) {
        let entry = match entry {
            Ok(e) => e,
            Err(e) => {
                // Skip broken symlinks and symlink loops (directory cycles and ELOOP file loops),
                // matching Elisp `org-roam-list-files`.
                if is_ignored_walkdir_error(&e) {
                    continue;
                }
                return Err(SyncError::Message(format!("walkdir error: {}", e)));
            }
        };
        if !entry.file_type().is_file() {
            continue;
        }
        let path = entry.path();
        let Ok(rel) = path.strip_prefix(dir) else {
            continue;
        };
        if rel.as_os_str().is_empty() {
            continue;
        }
        let (ext_ok, is_encrypted) = has_matching_extension(path, exts);
        if !ext_ok {
            continue;
        }
        let rel_str = rel.to_string_lossy().into_owned();
        if excludes.iter().any(|rx| rx.is_match(&rel_str)) {
            continue;
        }
        files.push(DiscoveredFile {
            lexical_path: path.to_path_buf(),
            rel_path: rel_str,
            is_encrypted,
        });
    }

    files.sort_by(|a, b| a.rel_path.cmp(&b.rel_path));
    Ok(files)
}

fn sha1_hex(bytes: &[u8]) -> String {
    let mut hasher = Sha1::new();
    hasher.update(bytes);
    let digest = hasher.finalize();
    let mut hex = String::with_capacity(40);
    for b in digest.as_slice() {
        let _ = write!(&mut hex, "{:02x}", b);
    }
    hex
}

pub fn run_sync(cfg: &SyncConfig) -> Result<(), SyncError> {
    if cfg.db.is_none() && !cfg.emit_org_ids && cfg.org_id_out.is_none() {
        return Err(SyncError::Message(
            "must pass --db PATH, --emit-org-ids, or --org-id-out PATH".to_string(),
        ));
    }

    let dir = normalize_dir(&cfg.dir)?;
    let exts = if cfg.exts.is_empty() {
        vec!["org".to_string()]
    } else {
        cfg.exts.clone()
    };
    let excludes = compile_excludes(&cfg.excludes, &cfg.exclude_elisp, cfg.ignore_case)?;
    let want_org_ids = cfg.emit_org_ids || cfg.org_id_out.is_some();

    let discovered = discover_files(&dir, &exts, &excludes)?;

    // If DB sync is requested and any matching non-excluded file is .gpg/.age,
    // return exit code 2 BEFORE touching the DB so Elisp falls back cleanly.
    if cfg.db.is_some() {
        if let Some(enc) = discovered.iter().find(|f| f.is_encrypted) {
            return Err(SyncError::EncryptedFilesPresent(enc.lexical_path.clone()));
        }
    }

    let home = std::env::var_os("HOME").map(PathBuf::from);

    // Parallel read + hash + stat (+ canonical path when org-id output requested)
    let scanned: Vec<ScannedEntry> = discovered
        .par_iter()
        .filter(|f| !f.is_encrypted)
        .map(|f| -> Result<ScannedEntry, SyncError> {
            let meta = fs::metadata(&f.lexical_path).map_err(|e| {
                SyncError::Message(format!("stat {} failed: {}", f.lexical_path.display(), e))
            })?;
            let atime = format_emacs_time(meta.accessed().unwrap_or(SystemTime::UNIX_EPOCH));
            let mtime = format_emacs_time(meta.modified().unwrap_or(SystemTime::UNIX_EPOCH));
            let raw_bytes = fs::read(&f.lexical_path).map_err(|e| {
                SyncError::Message(format!("read {} failed: {}", f.lexical_path.display(), e))
            })?;
            let hash = sha1_hex(&raw_bytes);
            let canonical_abbrev = if want_org_ids {
                let canon = fs::canonicalize(&f.lexical_path)
                    .unwrap_or_else(|_| f.lexical_path.clone());
                Some(abbreviate_file_name(&canon, home.as_deref()))
            } else {
                None
            };
            Ok(ScannedEntry {
                lexical_path_str: f.lexical_path.to_string_lossy().into_owned(),
                raw_bytes,
                hash,
                atime,
                mtime,
                canonical_abbrev,
            })
        })
        .collect::<Result<Vec<_>, _>>()?;

    // Handle DB sync if `--db` was provided
    if let Some(ref db_path) = cfg.db {
        let mut conn = open_db(db_path, cfg.force).map_err(SyncError::Message)?;
        let existing_hashes = load_existing_file_hashes(&conn).map_err(SyncError::Message)?;

        let mut disk_prin1_set: HashSet<String> = HashSet::with_capacity(scanned.len());
        let mut to_parse: Vec<&ScannedEntry> = Vec::new();

        for entry in &scanned {
            let f_prin1 = prin1_string(&entry.lexical_path_str);
            let h_prin1 = prin1_string(&entry.hash);
            disk_prin1_set.insert(f_prin1.clone());
            let unchanged = existing_hashes
                .get(&f_prin1)
                .map_or(false, |db_h| db_h == &h_prin1);
            if !unchanged {
                to_parse.push(entry);
            }
        }

        let deleted_prin1_files: Vec<String> = existing_hashes
            .keys()
            .filter(|k| !disk_prin1_set.contains(*k))
            .cloned()
            .collect();

        let updates: Vec<FileUpdate> = to_parse
            .par_iter()
            .map(|entry| {
                let text = String::from_utf8_lossy(&entry.raw_bytes);
                let parsed = parse_org_file(&entry.lexical_path_str, &text);
                FileUpdate {
                    file: entry.lexical_path_str.clone(),
                    hash: entry.hash.clone(),
                    atime: entry.atime.clone(),
                    mtime: entry.mtime.clone(),
                    parsed,
                }
            })
            .collect();

        apply_updates(&mut conn, &deleted_prin1_files, &updates).map_err(SyncError::Message)?;
    }

    // Handle org-id output if requested
    if want_org_ids {
        // Note: if `--db` was NOT given, we might also need to ensure `excludes` wasn't supposed to
        // apply unless explicitly requested; here `discovered` already applied whatever `--exclude`
        // flags were passed (none when called from `fenrir/org-id-index-directory`).
        let mut id_entries: Vec<(String, Vec<String>)> = scanned
            .par_iter()
            .filter_map(|entry| {
                let text = String::from_utf8_lossy(&entry.raw_bytes);
                let ids = extract_org_ids_only(&text);
                if ids.is_empty() {
                    None
                } else {
                    let abbrev = entry.canonical_abbrev.clone()?;
                    Some((abbrev, ids))
                }
            })
            .collect();

        // Deduplicate by abbreviated canonical path (in case symlinks pointed to same target)
        let mut seen_paths: HashMap<String, usize> = HashMap::new();
        let mut deduped: Vec<(String, Vec<String>)> = Vec::with_capacity(id_entries.len());
        for (path, ids) in id_entries.drain(..) {
            if let Some(&idx) = seen_paths.get(&path) {
                for id in ids {
                    if !deduped[idx].1.contains(&id) {
                        deduped[idx].1.push(id);
                    }
                }
            } else {
                seen_paths.insert(path.clone(), deduped.len());
                deduped.push((path, ids));
            }
        }

        if let Some(ref out_path) = cfg.org_id_out {
            merge_and_write_id_locations(out_path, &dir, &deduped).map_err(SyncError::Message)?;
        }
        if cfg.emit_org_ids {
            print!("{}", format_id_locations_alist(&deduped));
        }
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_compile_excludes_rust_regex_no_double_translation() {
        let rxs = compile_excludes(
            &[
                r"dir\(1\)/".to_string(),
                r"a\|b/".to_string(),
                r"\\\(".to_string(),
                r"[[:digit:]\\`a]".to_string(),
            ],
            &[],
            false,
        )
        .unwrap();
        assert!(rxs[0].is_match("dir(1)/note.org"));
        assert!(!rxs[0].is_match("dir1/note.org"));
        assert!(rxs[1].is_match("a|b/note.org"));
        assert!(!rxs[1].is_match("a/note.org"));
        assert!(rxs[2].is_match(r"\(note.org"));
        assert!(rxs[3].is_match("1.org"));
        assert!(rxs[3].is_match(r"\.org"));
        assert!(rxs[3].is_match("`.org"));
        assert!(rxs[3].is_match("a.org"));
        assert!(!rxs[3].is_match("^.org"));
    }

    #[test]
    fn test_translate_elisp_regex_edge_cases() {
        assert_eq!(translate_elisp_regex(r"\`records/").unwrap(), "^records/");
        assert_eq!(translate_elisp_regex(r"\\(").unwrap(), r"\\\(");
        assert_eq!(
            translate_elisp_regex(r"[[:digit:]\`a]").unwrap(),
            r"[[:digit:]\\`a]"
        );
        assert_eq!(
            translate_elisp_regex("[[:digit:]()]").unwrap(),
            "[[:digit:]()]"
        );
        assert_eq!(translate_elisp_regex("foo^bar").unwrap(), r"foo\^bar");
        assert_eq!(translate_elisp_regex("baz$qux").unwrap(), r"baz\$qux");
        assert_eq!(
            translate_elisp_regex(r"\(foo\|^bar\)").unwrap(),
            "(foo|^bar)"
        );
        assert_eq!(
            translate_elisp_regex("(a|^b)").unwrap(),
            r"\(a\|\^b\)"
        );
        assert_eq!(
            translate_elisp_regex(r"\(a$\|b\)").unwrap(),
            "(a$|b)"
        );
        assert_eq!(
            translate_elisp_regex(r"\(?:^bar\)").unwrap(),
            "(?:^bar)"
        );
        assert_eq!(translate_elisp_regex("[[]").unwrap(), r"[\[]");
        assert_eq!(translate_elisp_regex("[a&&b]").unwrap(), r"[a\&\&b]");
        assert_eq!(translate_elisp_regex("[a~~b]").unwrap(), r"[a\~\~b]");
        assert_eq!(translate_elisp_regex("[a--b]").unwrap(), "[b]");
        assert_eq!(translate_elisp_regex("[!--b]").unwrap(), r"[!-\-b]");
        assert_eq!(translate_elisp_regex("[a-z]+/").unwrap(), "[a-z]+/");

        let compiled = compile_excludes(
            &[],
            &[
                "foo^bar".to_string(),
                "baz$qux".to_string(),
                r"\(foo\|^bar\)".to_string(),
                "(a|^b)".to_string(),
                r"\(a$\|b\)".to_string(),
                "[[]".to_string(),
                "[a&&b]".to_string(),
                "[a--b]".to_string(),
                "[a~~b]".to_string(),
            ],
            false,
        )
        .unwrap();
        assert!(compiled[0].is_match("foo^bar.org"));
        assert!(compiled[1].is_match("baz$qux.org"));
        assert!(compiled[2].is_match("bar.org"));
        assert!(!compiled[2].is_match("xbar.org"));
        assert!(compiled[3].is_match("(a|^b).org"));
        assert!(!compiled[3].is_match("b.org"));
        assert!(compiled[4].is_match("a"));
        assert!(!compiled[4].is_match("ax"));
        assert!(compiled[5].is_match("[.org"));
        assert!(compiled[6].is_match("&.org"));
        assert!(!compiled[7].is_match("a.org"));
        assert!(!compiled[7].is_match("-.org"));
        assert!(compiled[7].is_match("b.org"));
        assert!(compiled[8].is_match("~.org"));

        assert!(translate_elisp_regex(r"\(?1:foo\)").is_err());
        assert!(translate_elisp_regex(r"\1").is_err());
    }

    #[test]
    fn test_translate_elisp_regex_iter4_fixes() {
        // 1. POSIX + dash combinations reject cleanly for Elisp fallback
        assert!(translate_elisp_regex("[[:alpha:]--[:digit:]]").is_err());
        assert!(translate_elisp_regex("[a-[:digit:]]").is_err());
        assert!(translate_elisp_regex("[[:alpha:]-z]").is_err());
        assert!(translate_elisp_regex("[-[:digit:]]").is_err());
        assert!(translate_elisp_regex("[[:digit:]-]").is_err());
        assert_eq!(
            translate_elisp_regex("[[:alpha:]a-z]").unwrap(),
            "[[:alpha:]a-z]"
        );

        // 2. Reject `\(?...` unless `\(?:`
        assert!(translate_elisp_regex(r"\(?i:A\)").is_err());
        assert!(translate_elisp_regex(r"\(?x:foo\)").is_err());
        assert!(translate_elisp_regex(r"\(?").is_err());

        // 3. Unknown `\c` outside `[...]`: bare literal for non-metacharacters, keep `\` for metacharacters
        assert_eq!(translate_elisp_regex(r"\d").unwrap(), "d");
        assert_eq!(translate_elisp_regex(r"\D").unwrap(), "D");
        assert_eq!(translate_elisp_regex(r"\n").unwrap(), "n");
        assert_eq!(translate_elisp_regex(r"\t").unwrap(), "t");
        assert_eq!(translate_elisp_regex(r"\A").unwrap(), "A");
        assert_eq!(translate_elisp_regex(r"\z").unwrap(), "z");
        assert_eq!(translate_elisp_regex(r"\p").unwrap(), "p");
        assert_eq!(translate_elisp_regex(r"\x").unwrap(), "x");
        assert_eq!(translate_elisp_regex(r"\0").unwrap(), "0");
        assert_eq!(translate_elisp_regex(r"\*foo\.\+").unwrap(), r"\*foo\.\+");
        assert_eq!(translate_elisp_regex(r"a\/b\-c\^d\$").unwrap(), r"a\/b\-c\^d\$");

        let lit_rxs = compile_excludes(
            &[],
            &[r"\d".to_string(), r"\n".to_string(), r"\A".to_string(), r"\z".to_string()],
            false,
        )
        .unwrap();
        assert!(lit_rxs[0].is_match("d.org"));
        assert!(!lit_rxs[0].is_match("0.org"));
        assert!(lit_rxs[1].is_match("n.org"));
        assert!(!lit_rxs[1].is_match("\n"));
        assert!(lit_rxs[2].is_match("A.org"));
        assert!(!lit_rxs[2].is_match("keep.org"));
        assert!(lit_rxs[3].is_match("z.org"));
        assert!(!lit_rxs[3].is_match("keep.org"));

        // 4. Case-insensitive matching (`--ignore-case` / Emacs `case-fold-search`)
        let ci_rxs = compile_excludes(
            &[],
            &["FOO".to_string(), "[a-z]".to_string(), "[[:lower:]]".to_string()],
            true,
        )
        .unwrap();
        assert!(ci_rxs[0].is_match("foo.org"));
        assert!(ci_rxs[1].is_match("A.org"));
        assert!(ci_rxs[2].is_match("A.org"));

        let cs_rxs = compile_excludes(&[], &["FOO".to_string()], false).unwrap();
        assert!(!cs_rxs[0].is_match("foo.org"));
        assert!(cs_rxs[0].is_match("FOO.org"));

        // 5. Reject `[[:word:]]` so Emacs syntax-table `_` mismatch falls back to Elisp
        assert!(translate_elisp_regex(r"\`[[:word:]]\.").is_err());
        assert!(translate_elisp_regex("[^[:word:]]").is_err());
        assert!(translate_elisp_regex("[[:word:]0-9]").is_err());
        assert!(compile_excludes(&[], &[r"\`[[:word:]]\.".to_string()], false).is_err());
    }

    #[test]
    fn test_has_matching_extension_dotfiles() {
        let exts = vec!["org".to_string()];
        assert_eq!(has_matching_extension(Path::new("/v/.org"), &exts), (false, false));
        assert_eq!(
            has_matching_extension(Path::new("/v/.org.gpg"), &exts),
            (false, true)
        );
        assert_eq!(
            has_matching_extension(Path::new("/v/.hidden.org"), &exts),
            (true, false)
        );
        assert_eq!(
            has_matching_extension(Path::new("/v/note.org"), &exts),
            (true, false)
        );
        assert_eq!(
            has_matching_extension(Path::new("/v/note.org.age"), &exts),
            (true, true)
        );
    }

    #[test]
    fn test_broken_symlink_does_not_abort_discover_files() {
        use std::os::unix::fs::symlink;
        let root = std::env::temp_dir().join(format!("orst-sym-{}", std::process::id()));
        let _ = fs::remove_dir_all(&root);
        fs::create_dir_all(&root).unwrap();
        fs::write(
            root.join("ok.org"),
            ":PROPERTIES:\n:ID: ok-1\n:END:\n#+title: OK\n",
        )
        .unwrap();
        symlink("/nonexistent/missing.org", root.join("broken.org")).unwrap();

        let files = discover_files(&root, &["org".to_string()], &[]).unwrap();
        assert_eq!(files.len(), 1);
        assert_eq!(files[0].rel_path, "ok.org");
        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn test_translate_elisp_regex_leading_quantifiers_and_upper_brace() {
        let rxs = compile_excludes(
            &[],
            &[
                r"^*".to_string(),
                r"^?".to_string(),
                r"\`*".to_string(),
                r"\(*foo\)".to_string(),
                r"^a\{,3\}b".to_string(),
            ],
            false,
        )
        .unwrap();
        assert!(rxs[0].is_match("*foo.org"));
        assert!(!rxs[0].is_match("normal.org"));
        assert!(rxs[1].is_match("?q.org"));
        assert!(!rxs[1].is_match("normal.org"));
        assert!(rxs[2].is_match("*foo.org"));
        assert!(!rxs[2].is_match("normal.org"));
        assert!(rxs[3].is_match("*foo.org"));
        assert!(!rxs[3].is_match("foo.org"));
        assert!(rxs[4].is_match("b.org"));
        assert!(rxs[4].is_match("aaab.org"));
        assert!(!rxs[4].is_match("aaaab.org"));
    }

    #[test]
    fn test_file_symlink_loop_does_not_abort_discover_files_or_run_sync() {
        use std::os::unix::fs::symlink;
        let root = std::env::temp_dir().join(format!("orst-eloop-{}", std::process::id()));
        let _ = fs::remove_dir_all(&root);
        let vault = root.join("vault");
        let db = root.join("roam.db");
        let idfile = root.join("id-locations.el");
        fs::create_dir_all(&vault).unwrap();
        fs::write(
            vault.join("ok.org"),
            ":PROPERTIES:\n:ID: ok-eloop\n:END:\n#+title: OK\n",
        )
        .unwrap();
        symlink(vault.join("selfloop.org"), vault.join("selfloop.org")).unwrap();
        symlink(vault.join("cyc_b.org"), vault.join("cyc_a.org")).unwrap();
        symlink(vault.join("cyc_a.org"), vault.join("cyc_b.org")).unwrap();
        symlink(".", vault.join("dir_loop")).unwrap();

        let files = discover_files(&vault, &["org".to_string()], &[]).unwrap();
        assert_eq!(files.len(), 1);
        assert_eq!(files[0].rel_path, "ok.org");

        let cfg = SyncConfig {
            dir: vault.clone(),
            db: Some(db.clone()),
            excludes: vec![],
            exclude_elisp: vec![],
            exts: vec!["org".to_string()],
            force: true,
            ignore_case: false,
            emit_org_ids: false,
            org_id_out: Some(idfile.clone()),
        };
        run_sync(&cfg).unwrap();
        let conn = rusqlite::Connection::open(&db).unwrap();
        let count: i64 = conn
            .query_row("SELECT count(*) FROM nodes", [], |r| r.get(0))
            .unwrap();
        assert_eq!(count, 1);
        let id_text = fs::read_to_string(&idfile).unwrap();
        assert!(id_text.contains("ok-eloop"));
        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn test_translate_elisp_regex_empty_brace_and_interval_question() {
        // Leading `\{\}` stays literal `{}`
        assert_eq!(translate_elisp_regex(r"\{\}").unwrap(), r"\{\}");
        assert_eq!(translate_elisp_regex(r"^\{\}").unwrap(), r"^\{\}");
        assert_eq!(translate_elisp_regex(r"\`\{\}").unwrap(), r"^\{\}");
        assert_eq!(translate_elisp_regex(r"\{\}?b").unwrap(), r"\{\}?b");

        // Non-leading `\{\}` is `{0,0}`
        assert_eq!(translate_elisp_regex(r"a\{\}b").unwrap(), "a{0,0}b");
        assert_eq!(translate_elisp_regex(r"\(a\)\{\}b").unwrap(), "(a){0,0}b");
        assert_eq!(translate_elisp_regex(r"[a-z]\{\}b").unwrap(), "[a-z]{0,0}b");
        assert_eq!(translate_elisp_regex(r"a$\{\}").unwrap(), r"a\${0,0}");

        // Interval followed by `?` is rejected so Elisp handles `(atom{m,n})?`
        assert!(translate_elisp_regex(r"a\{\}?").is_err());
        assert!(translate_elisp_regex(r"a\{\}?b").is_err());
        assert!(translate_elisp_regex(r"a\{1,2\}?").is_err());
        assert!(translate_elisp_regex(r"a\{1,2\}?b").is_err());
        assert!(translate_elisp_regex(r"a\{1,2\}\{1,2\}?").is_err());

        // Escaped `\?` after interval is a literal `?`
        assert_eq!(translate_elisp_regex(r"a\{1,2\}\?").unwrap(), r"a{1,2}\?");
        assert_eq!(translate_elisp_regex(r"a\{\}\?").unwrap(), r"a{0,0}\?");

        let rxs = compile_excludes(
            &[],
            &[
                r"^\{\}".to_string(),
                r"a\{\}b".to_string(),
                r"\(a\)\{\}b".to_string(),
            ],
            false,
        )
        .unwrap();
        assert!(rxs[0].is_match("{}note.org"));
        assert!(!rxs[0].is_match("a{}note.org"));
        assert!(rxs[1].is_match("b.org"));
        assert!(rxs[1].is_match("ab.org"));
        assert!(rxs[1].is_match("a{}b.org"));
        assert!(!rxs[1].is_match("a{}.org"));
        assert!(rxs[2].is_match("b.org"));
        assert!(rxs[2].is_match("ab.org"));
    }
}
