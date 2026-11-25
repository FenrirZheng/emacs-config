use std::fmt::Write as _;
use std::fs;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

/// Format a UTF-8 string using Emacs `prin1-to-string` with
/// `print-escape-newlines = t` and `print-escape-control-characters = t`.
pub fn prin1_string(s: &str) -> String {
    let bytes = s.as_bytes();
    let mut out = String::with_capacity(bytes.len() + 2);
    out.push('"');
    let mut i = 0;
    while i < bytes.len() {
        let b = bytes[i];
        match b {
            b'"' => {
                out.push_str("\\\"");
                i += 1;
            }
            b'\\' => {
                out.push_str("\\\\");
                i += 1;
            }
            b'\n' => {
                out.push_str("\\n");
                i += 1;
            }
            b'\x0c' => {
                out.push_str("\\f");
                i += 1;
            }
            0x00..=0x1f | 0x7f => {
                let next_is_octal = matches!(bytes.get(i + 1), Some(b'0'..=b'7'));
                if next_is_octal {
                    let _ = write!(out, "\\{:03o}", b);
                } else {
                    let _ = write!(out, "\\{:o}", b);
                }
                i += 1;
            }
            0x20..=0x7e => {
                out.push(b as char);
                i += 1;
            }
            _ => {
                // Copy valid UTF-8 multibyte scalar verbatim.
                let ch = s[i..].chars().next().unwrap();
                out.push(ch);
                i += ch.len_utf8();
            }
        }
    }
    out.push('"');
    out
}

/// Format an optional string with `prin1_string` (`None` stays `None` for SQL `NULL`).
pub fn opt_prin1_string(s: Option<&str>) -> Option<String> {
    s.map(prin1_string)
}

/// Format an Emacs `(HIGH LOW USEC PSEC)` timestamp tuple from `SystemTime`.
pub fn format_emacs_time(t: SystemTime) -> String {
    let (secs, nanos): (i64, u32) = match t.duration_since(UNIX_EPOCH) {
        Ok(d) => (d.as_secs() as i64, d.subsec_nanos()),
        Err(e) => {
            let d = e.duration();
            let s = d.as_secs() as i64;
            let n = d.subsec_nanos();
            if n == 0 {
                (-s, 0)
            } else {
                (-s - 1, 1_000_000_000 - n)
            }
        }
    };
    let high = secs.div_euclid(65_536);
    let low = secs.rem_euclid(65_536);
    let usec = nanos / 1_000;
    let psec = (nanos % 1_000) * 1_000;
    format!("({} {} {} {})", high, low, usec, psec)
}

/// Format an alist of `(KEY . VAL)` string pairs for EmacSQL `nodes.properties`.
pub fn format_alist(pairs: &[(String, String)]) -> Option<String> {
    if pairs.is_empty() {
        return None;
    }
    let mut out = String::from("(");
    for (idx, (k, v)) in pairs.iter().enumerate() {
        if idx > 0 {
            out.push(' ');
        }
        out.push('(');
        out.push_str(&prin1_string(k));
        out.push_str(" . ");
        out.push_str(&prin1_string(v));
        out.push(')');
    }
    out.push(')');
    Some(out)
}

/// Format a list of strings for `nodes.olp`, returning `None` if empty.
pub fn format_string_list(items: &[String]) -> Option<String> {
    if items.is_empty() {
        return None;
    }
    let mut out = String::from("(");
    for (idx, item) in items.iter().enumerate() {
        if idx > 0 {
            out.push(' ');
        }
        out.push_str(&prin1_string(item));
    }
    out.push(')');
    Some(out)
}

/// Format `links.properties` or `citations.properties` plist.
pub fn format_link_properties(outline: &[String], search_option: Option<&str>) -> String {
    let mut out = String::from("(:outline ");
    if outline.is_empty() {
        out.push_str("nil");
    } else {
        out.push('(');
        for (idx, item) in outline.iter().enumerate() {
            if idx > 0 {
                out.push(' ');
            }
            out.push_str(&prin1_string(item));
        }
        out.push(')');
    }
    if let Some(opt) = search_option {
        out.push_str(" :search-option ");
        out.push_str(&prin1_string(opt));
    }
    out.push(')');
    out
}

/// Exact port of Emacs `split-string-and-unquote` with default separators
/// (`[ \f\t\n\r\v]+`).
pub fn split_string_and_unquote(s: &str) -> Vec<String> {
    let is_sep = |b: u8| matches!(b, b' ' | b'\x0c' | b'\t' | b'\n' | b'\r' | b'\x0b');
    let bytes = s.as_bytes();
    let mut result = Vec::new();
    let mut i = 0;

    while i < bytes.len() {
        while i < bytes.len() && is_sep(bytes[i]) {
            i += 1;
        }
        if i >= bytes.len() {
            break;
        }
        if bytes[i] == b'"' {
            i += 1;
            let mut tok = String::new();
            let mut closed = false;
            while i < bytes.len() {
                if bytes[i] == b'\\' && i + 1 < bytes.len() {
                    let ch = s[i + 1..].chars().next().unwrap();
                    tok.push(ch);
                    i += 1 + ch.len_utf8();
                } else if bytes[i] == b'"' {
                    i += 1;
                    closed = true;
                    break;
                } else {
                    let ch = s[i..].chars().next().unwrap();
                    tok.push(ch);
                    i += ch.len_utf8();
                }
            }
            if closed {
                result.push(tok);
            } else {
                // Unclosed quote: Emacs falls back to non-quote token from the '"'.
                // Rewind is unnecessary for valid inputs, handle cleanly:
                result.push(format!("\"{}", tok));
            }
        } else {
            let start = i;
            while i < bytes.len() && !is_sep(bytes[i]) && bytes[i] != b'"' {
                i += 1;
            }
            result.push(s[start..i].to_string());
        }
    }
    result
}

/// Mirror Emacs `abbreviate-file-name`: replace `$HOME` prefix with `~`.
pub fn abbreviate_file_name(path: &Path, home: Option<&Path>) -> String {
    if let Some(h) = home {
        if h.as_os_str() != "/" {
            if path == h {
                return "~".to_string();
            }
            if let Ok(rel) = path.strip_prefix(h) {
                return format!("~/{}", rel.to_string_lossy());
            }
        }
    }
    path.to_string_lossy().into_owned()
}

/// Expand leading `~` or `~/` using `$HOME`.
pub fn expand_user_path(path: &str, home: Option<&Path>) -> PathBuf {
    if let Some(h) = home {
        if path == "~" {
            return h.to_path_buf();
        }
        if let Some(rest) = path.strip_prefix("~/") {
            return h.join(rest);
        }
    }
    PathBuf::from(path)
}

/// Canonicalize `path` if it exists, or canonicalize its deepest existing
/// ancestor and re-append the non-existent tail components.
fn canonicalize_best_effort(path: &Path) -> PathBuf {
    if let Ok(c) = fs::canonicalize(path) {
        return c;
    }
    let mut tail: Vec<std::ffi::OsString> = Vec::new();
    let mut cur = path;
    while let Some(parent) = cur.parent() {
        if let Some(name) = cur.file_name() {
            tail.push(name.to_os_string());
        }
        if let Ok(c) = fs::canonicalize(parent) {
            let mut out = c;
            for comp in tail.into_iter().rev() {
                out.push(comp);
            }
            return out;
        }
        if parent.as_os_str().is_empty() {
            break;
        }
        cur = parent;
    }
    path.to_path_buf()
}

/// Check if `file_path` is strictly under (or equal to) `dir_path`.
pub fn is_path_under_dir(file_path: &str, dir_path: &Path, home: Option<&Path>) -> bool {
    let expanded = expand_user_path(file_path, home);
    if expanded.starts_with(dir_path) {
        return true;
    }
    let cf = canonicalize_best_effort(&expanded);
    let cd = canonicalize_best_effort(dir_path);
    cf.starts_with(&cd)
}

/// Parse an `org-id-locations` alist from disk (`((file "id1" ...) ...)`).
pub fn parse_id_locations_alist(input: &str) -> Result<Vec<(String, Vec<String>)>, String> {
    let bytes = input.as_bytes();
    let mut pos = 0;

    fn skip_ws_and_comments(bytes: &[u8], pos: &mut usize) {
        loop {
            while *pos < bytes.len() && bytes[*pos].is_ascii_whitespace() {
                *pos += 1;
            }
            if *pos < bytes.len() && bytes[*pos] == b';' {
                while *pos < bytes.len() && bytes[*pos] != b'\n' {
                    *pos += 1;
                }
            } else {
                break;
            }
        }
    }

    fn parse_lisp_string(input: &str, bytes: &[u8], pos: &mut usize) -> Result<String, String> {
        if *pos >= bytes.len() || bytes[*pos] != b'"' {
            return Err(format!("expected string at byte {}", *pos));
        }
        *pos += 1;
        let mut out = String::new();
        while *pos < bytes.len() {
            let b = bytes[*pos];
            if b == b'"' {
                *pos += 1;
                return Ok(out);
            }
            if b == b'\\' {
                *pos += 1;
                if *pos >= bytes.len() {
                    return Err("unterminated escape in string".to_string());
                }
                match bytes[*pos] {
                    b'n' => {
                        out.push('\n');
                        *pos += 1;
                    }
                    b't' => {
                        out.push('\t');
                        *pos += 1;
                    }
                    b'r' => {
                        out.push('\r');
                        *pos += 1;
                    }
                    b'f' => {
                        out.push('\x0c');
                        *pos += 1;
                    }
                    b'a' => {
                        out.push('\x07');
                        *pos += 1;
                    }
                    b'b' => {
                        out.push('\x08');
                        *pos += 1;
                    }
                    b'e' => {
                        out.push('\x1b');
                        *pos += 1;
                    }
                    b'v' => {
                        out.push('\x0b');
                        *pos += 1;
                    }
                    b'\\' => {
                        out.push('\\');
                        *pos += 1;
                    }
                    b'"' => {
                        out.push('"');
                        *pos += 1;
                    }
                    b'\n' => {
                        // Line continuation in Lisp string
                        *pos += 1;
                    }
                    b'0'..=b'7' => {
                        let mut val: u32 = 0;
                        let mut count = 0;
                        while count < 3
                            && *pos < bytes.len()
                            && matches!(bytes[*pos], b'0'..=b'7')
                        {
                            val = val * 8 + (bytes[*pos] - b'0') as u32;
                            *pos += 1;
                            count += 1;
                        }
                        if let Some(ch) = char::from_u32(val) {
                            out.push(ch);
                        }
                    }
                    _ => {
                        let ch = input[*pos..].chars().next().unwrap();
                        out.push(ch);
                        *pos += ch.len_utf8();
                    }
                }
            } else {
                let ch = input[*pos..].chars().next().unwrap();
                out.push(ch);
                *pos += ch.len_utf8();
            }
        }
        Err("unterminated string literal".to_string())
    }

    skip_ws_and_comments(bytes, &mut pos);
    if pos >= bytes.len() {
        return Ok(Vec::new());
    }
    if input[pos..].starts_with("nil")
        && bytes
            .get(pos + 3)
            .map_or(true, |b| b.is_ascii_whitespace() || *b == b';')
    {
        return Ok(Vec::new());
    }
    if bytes[pos] != b'(' {
        return Err(format!("expected '(' at byte {}", pos));
    }
    pos += 1;

    let mut entries = Vec::new();
    loop {
        skip_ws_and_comments(bytes, &mut pos);
        if pos >= bytes.len() {
            return Err("unterminated outer list".to_string());
        }
        if bytes[pos] == b')' {
            break;
        }
        if bytes[pos] != b'(' {
            return Err(format!("expected entry '(' at byte {}", pos));
        }
        pos += 1;
        skip_ws_and_comments(bytes, &mut pos);
        let file = parse_lisp_string(input, bytes, &mut pos)?;
        let mut ids = Vec::new();
        loop {
            skip_ws_and_comments(bytes, &mut pos);
            if pos >= bytes.len() {
                return Err("unterminated entry list".to_string());
            }
            if bytes[pos] == b')' {
                pos += 1;
                break;
            }
            if bytes[pos] == b'.' {
                // Dotted tail not expected for valid org-id-locations, skip dot if present
                pos += 1;
                continue;
            }
            ids.push(parse_lisp_string(input, bytes, &mut pos)?);
        }
        entries.push((file, ids));
    }

    Ok(entries)
}

/// Format an `org-id-locations` alist for Emacs `read` / `org-id-locations-load`.
pub fn format_id_locations_alist(entries: &[(String, Vec<String>)]) -> String {
    if entries.is_empty() {
        return "nil\n".to_string();
    }
    let mut out = String::from("(");
    for (idx, (file, ids)) in entries.iter().enumerate() {
        if idx > 0 {
            out.push('\n');
            out.push(' ');
        }
        out.push('(');
        out.push_str(&prin1_string(file));
        for id in ids {
            out.push(' ');
            out.push_str(&prin1_string(id));
        }
        out.push(')');
    }
    out.push_str(")\n");
    out
}

/// Merge `scanned` entries for `dir` into `out_path` without clobbering entries
/// outside `dir`, then write atomically.
pub fn merge_and_write_id_locations(
    out_path: &Path,
    dir: &Path,
    scanned: &[(String, Vec<String>)],
) -> Result<(), String> {
    let home = std::env::var_os("HOME").map(PathBuf::from);
    let mut merged: Vec<(String, Vec<String>)> = if out_path.exists() {
        let existing_raw = fs::read_to_string(out_path)
            .map_err(|e| format!("failed to read {}: {}", out_path.display(), e))?;
        let existing = parse_id_locations_alist(&existing_raw)?;
        existing
            .into_iter()
            .filter(|(file, _)| !is_path_under_dir(file, dir, home.as_deref()))
            .collect()
    } else {
        Vec::new()
    };

    merged.extend(scanned.iter().cloned());

    if let Some(parent) = out_path.parent() {
        if !parent.as_os_str().is_empty() {
            fs::create_dir_all(parent)
                .map_err(|e| format!("failed to create {}: {}", parent.display(), e))?;
        }
    }

    let tmp_name = format!(
        ".{}.tmp.{}",
        out_path
            .file_name()
            .map(|s| s.to_string_lossy().into_owned())
            .unwrap_or_else(|| "id-locations.el".to_string()),
        std::process::id()
    );
    let tmp_path = out_path.with_file_name(tmp_name);
    let content = format_id_locations_alist(&merged);
    fs::write(&tmp_path, content)
        .map_err(|e| format!("failed to write {}: {}", tmp_path.display(), e))?;
    fs::rename(&tmp_path, out_path).map_err(|e| {
        let _ = fs::remove_file(&tmp_path);
        format!("failed to rename to {}: {}", out_path.display(), e)
    })?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_prin1_string_escaping_and_octal_padding() {
        assert_eq!(prin1_string(""), "\"\"");
        assert_eq!(prin1_string("hello"), "\"hello\"");
        assert_eq!(prin1_string("a\"b\\c\nd"), "\"a\\\"b\\\\c\\nd\"");
        assert_eq!(prin1_string("\t8"), "\"\\118\"");
        assert_eq!(prin1_string("\t0"), "\"\\0110\"");
        assert_eq!(prin1_string("\x01"), "\"\\1\"");
        assert_eq!(prin1_string("\x010"), "\"\\0010\"");
        assert_eq!(prin1_string("\x000"), "\"\\0000\"");
        assert_eq!(prin1_string("\x7f0"), "\"\\1770\"");
        assert_eq!(prin1_string("\x7f"), "\"\\177\"");
        assert_eq!(prin1_string("\r\n"), "\"\\15\\n\"");
        assert_eq!(prin1_string("\x07\x08\x0b\x0c\r\x1f09"), "\"\\7\\10\\13\\f\\15\\03709\"");
        assert_eq!(prin1_string("中文 🚀"), "\"中文 🚀\"");
    }

    #[test]
    fn test_is_path_under_dir_deleted_via_symlink() {
        use std::os::unix::fs::symlink;
        use std::time::UNIX_EPOCH;

        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let root = std::env::temp_dir().join(format!("orst-sexpr-{}-{}", std::process::id(), nanos));
        let real_dir = root.join("real");
        let sibling_dir = root.join("real2");
        let link_dir = root.join("link");
        fs::create_dir_all(&real_dir).unwrap();
        fs::create_dir_all(&sibling_dir).unwrap();
        symlink(&real_dir, &link_dir).unwrap();

        let stale = real_dir.join("deleted/sub/note.org");
        let sibling = sibling_dir.join("deleted/note.org");
        assert!(is_path_under_dir(&stale.to_string_lossy(), &link_dir, None));
        assert!(!is_path_under_dir(&sibling.to_string_lossy(), &link_dir, None));

        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn test_split_string_and_unquote_parity() {
        assert_eq!(split_string_and_unquote("a b"), vec!["a", "b"]);
        assert_eq!(
            split_string_and_unquote("  \"two words\"  'single'  "),
            vec!["two words", "'single'"]
        );
        assert_eq!(split_string_and_unquote("\"\""), vec![""]);
        assert_eq!(split_string_and_unquote("a\"b c\"d"), vec!["a", "b c", "d"]);
        assert_eq!(
            split_string_and_unquote("\"esc \\\"q\\\" \\\\b\""),
            vec!["esc \"q\" \\b"]
        );
        assert_eq!(
            split_string_and_unquote("  foo\\ bar  "),
            vec!["foo\\", "bar"]
        );
    }

    #[test]
    fn test_id_locations_roundtrip() {
        let entries = vec![
            ("~/code/camhr/kb/note.org".to_string(), vec!["kb-1".to_string()]),
            (
                "~/code/org-roam/a\"b.org".to_string(),
                vec!["id-1".to_string(), "id-2".to_string()],
            ),
        ];
        let s = format_id_locations_alist(&entries);
        let parsed = parse_id_locations_alist(&s).unwrap();
        assert_eq!(parsed, entries);
    }
}
