//! Parallel scanner for `jobctl` sessions, `/proc` liveness, Claude daemon
//! `state.json`, and JSONL transcript heads, emitting one Elisp plist.

use serde_json::Value;
use std::collections::{HashMap, HashSet};
use std::ffi::{OsStr, OsString};
use std::fs::{self, File};
use std::io::{self, Read, Write};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicUsize, Ordering};

pub const DEFAULT_HEAD_BYTES: usize = 65_536;

pub const USAGE: &str = "\
Usage: claude-jobs-scan [OPTIONS]

Options:
  --state-dir DIR      jobctl state dir (default: $JOBCTL_STATE or ~/.cache/jobctl)
  --jobs-dir DIR       Claude daemon jobs dir (default: ~/.claude/jobs)
  --projects-dir DIR   Claude projects transcript dir (default: ~/.claude/projects)
  --head-bytes N       Max bytes to read from JSONL heads (default: 65536)
  --uuid UUID          Lookup a single session UUID and print its plist or nil
  -h, --help           Show this help message
";

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Config {
    pub state_dir: PathBuf,
    pub jobs_dir: PathBuf,
    pub projects_dir: PathBuf,
    pub proc_dir: PathBuf,
    pub head_bytes: usize,
    pub uuid: Option<String>,
}

impl Default for Config {
    fn default() -> Self {
        let home = std::env::var_os("HOME")
            .filter(|v| !v.is_empty())
            .map(PathBuf::from)
            .unwrap_or_else(|| PathBuf::from("."));
        let state_dir = std::env::var_os("JOBCTL_STATE")
            .filter(|v| !v.is_empty())
            .map(PathBuf::from)
            .unwrap_or_else(|| home.join(".cache/jobctl"));
        Self {
            state_dir,
            jobs_dir: home.join(".claude/jobs"),
            projects_dir: home.join(".claude/projects"),
            proc_dir: PathBuf::from("/proc"),
            head_bytes: DEFAULT_HEAD_BYTES,
            uuid: None,
        }
    }
}

pub fn validate_uuid(uuid: &str) -> Result<(), String> {
    if uuid.is_empty()
        || uuid.contains('/')
        || uuid.contains('\\')
        || uuid.contains('\0')
        || uuid.contains("..")
    {
        return Err(format!("invalid --uuid value: {uuid:?}"));
    }
    Ok(())
}

pub fn parse_args(args: &[OsString]) -> Result<Option<Config>, String> {
    let mut cfg = Config::default();
    let mut i = 0;
    while i < args.len() {
        let arg = args[i].to_string_lossy();
        match arg.as_ref() {
            "-h" | "--help" => return Ok(None),
            "--state-dir" => {
                i += 1;
                let v = args.get(i).ok_or("--state-dir requires a value")?;
                cfg.state_dir = PathBuf::from(v);
            }
            "--jobs-dir" => {
                i += 1;
                let v = args.get(i).ok_or("--jobs-dir requires a value")?;
                cfg.jobs_dir = PathBuf::from(v);
            }
            "--projects-dir" => {
                i += 1;
                let v = args.get(i).ok_or("--projects-dir requires a value")?;
                cfg.projects_dir = PathBuf::from(v);
            }
            "--head-bytes" => {
                i += 1;
                let v = args.get(i).ok_or("--head-bytes requires a value")?;
                let s = v.to_string_lossy();
                cfg.head_bytes = s
                    .parse::<usize>()
                    .map_err(|_| format!("invalid --head-bytes value: {s}"))?;
            }
            "--uuid" => {
                i += 1;
                let v = args.get(i).ok_or("--uuid requires a value")?;
                let s = v.to_string_lossy().into_owned();
                validate_uuid(&s)?;
                cfg.uuid = Some(s);
            }
            other => return Err(format!("unknown argument: {other}")),
        }
        i += 1;
    }
    Ok(Some(cfg))
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Session {
    pub sid: String,
    pub pid: u32,
    pub live_pids: Vec<u32>,
    pub state: &'static str,
    pub resumed: bool,
    pub agent: String,
    pub started: String,
    pub cwd: Option<String>,
    pub transcript_path: Option<String>,
    pub first_user_text: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DaemonJob {
    pub short: String,
    pub state: String,
    pub updated: String,
    pub intent: String,
    pub raw_intent: String,
    pub name: String,
    pub cwd: Option<String>,
}

#[derive(Debug, Default, Clone, PartialEq, Eq)]
pub struct ScanResult {
    pub sessions: Vec<Session>,
    pub daemons: Vec<DaemonJob>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct MetaInfo {
    sid: String,
    pid: u32,
    cwd: Option<String>,
    agent: String,
    started: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum QuoteMode {
    Unquoted,
    Single,
    Double,
    AnsiC,
}

fn hex_val(b: u8) -> Option<u32> {
    match b {
        b'0'..=b'9' => Some((b - b'0') as u32),
        b'a'..=b'f' => Some((b - b'a' + 10) as u32),
        b'A'..=b'F' => Some((b - b'A' + 10) as u32),
        _ => None,
    }
}

fn push_unicode_scalar(out: &mut Vec<u8>, code: u32) {
    let ch = char::from_u32(code).unwrap_or('\u{FFFD}');
    let mut buf = [0u8; 4];
    let s = ch.encode_utf8(&mut buf);
    out.extend_from_slice(s.as_bytes());
}

/// Unescape a single bash `printf '%q'`-encoded word into UTF-8 text.
///
/// Handles unquoted `\X` escapes, `'...'`, `"..."`, and ANSI-C `$'...'`
/// (`\n`, `\t`, `\r`, `\a`, `\b`, `\e`, `\E`, `\f`, `\v`, `\NNN` octal,
/// `\xHH` hex, `\uHHHH`/`\UHHHHHHHH` Unicode, `\cX` control bytes).
pub fn unescape_bash_word(raw: &str) -> String {
    let trimmed = raw.strip_suffix('\r').unwrap_or(raw);
    let b = trimmed.as_bytes();
    let mut out = Vec::with_capacity(b.len());
    let mut mode = QuoteMode::Unquoted;
    let mut i = 0;

    while i < b.len() {
        match mode {
            QuoteMode::Unquoted => {
                if i + 1 < b.len() && b[i] == b'$' && b[i + 1] == b'\'' {
                    mode = QuoteMode::AnsiC;
                    i += 2;
                } else if b[i] == b'\'' {
                    mode = QuoteMode::Single;
                    i += 1;
                } else if b[i] == b'"' {
                    mode = QuoteMode::Double;
                    i += 1;
                } else if b[i] == b'\\' {
                    if i + 1 < b.len() {
                        out.push(b[i + 1]);
                        i += 2;
                    } else {
                        out.push(b'\\');
                        i += 1;
                    }
                } else {
                    out.push(b[i]);
                    i += 1;
                }
            }
            QuoteMode::Single => {
                if b[i] == b'\'' {
                    mode = QuoteMode::Unquoted;
                } else {
                    out.push(b[i]);
                }
                i += 1;
            }
            QuoteMode::Double => {
                if b[i] == b'"' {
                    mode = QuoteMode::Unquoted;
                    i += 1;
                } else if b[i] == b'\\' {
                    if i + 1 < b.len() {
                        match b[i + 1] {
                            b'$' | b'`' | b'"' | b'\\' => {
                                out.push(b[i + 1]);
                                i += 2;
                            }
                            b'\n' => {
                                i += 2;
                            }
                            other => {
                                out.push(b'\\');
                                out.push(other);
                                i += 2;
                            }
                        }
                    } else {
                        out.push(b'\\');
                        i += 1;
                    }
                } else {
                    out.push(b[i]);
                    i += 1;
                }
            }
            QuoteMode::AnsiC => {
                if b[i] == b'\'' {
                    mode = QuoteMode::Unquoted;
                    i += 1;
                } else if b[i] == b'\\' {
                    if i + 1 >= b.len() {
                        out.push(b'\\');
                        i += 1;
                        continue;
                    }
                    match b[i + 1] {
                        b'a' => {
                            out.push(0x07);
                            i += 2;
                        }
                        b'b' => {
                            out.push(0x08);
                            i += 2;
                        }
                        b'e' | b'E' => {
                            out.push(0x1b);
                            i += 2;
                        }
                        b'f' => {
                            out.push(0x0c);
                            i += 2;
                        }
                        b'n' => {
                            out.push(0x0a);
                            i += 2;
                        }
                        b'r' => {
                            out.push(0x0d);
                            i += 2;
                        }
                        b't' => {
                            out.push(0x09);
                            i += 2;
                        }
                        b'v' => {
                            out.push(0x0b);
                            i += 2;
                        }
                        b'\\' => {
                            out.push(b'\\');
                            i += 2;
                        }
                        b'\'' => {
                            out.push(b'\'');
                            i += 2;
                        }
                        b'"' => {
                            out.push(b'"');
                            i += 2;
                        }
                        b'?' => {
                            out.push(b'?');
                            i += 2;
                        }
                        b'0'..=b'7' => {
                            let mut val: u32 = 0;
                            let mut j = i + 1;
                            let end = (i + 4).min(b.len());
                            while j < end && (b'0'..=b'7').contains(&b[j]) {
                                val = (val << 3) | (b[j] - b'0') as u32;
                                j += 1;
                            }
                            out.push((val & 0xff) as u8);
                            i = j;
                        }
                        b'x' => {
                            let mut val: u32 = 0;
                            let mut j = i + 2;
                            let end = (i + 4).min(b.len());
                            while j < end {
                                if let Some(d) = hex_val(b[j]) {
                                    val = (val << 4) | d;
                                    j += 1;
                                } else {
                                    break;
                                }
                            }
                            if j > i + 2 {
                                out.push((val & 0xff) as u8);
                                i = j;
                            } else {
                                out.push(b'\\');
                                out.push(b'x');
                                i += 2;
                            }
                        }
                        b'u' | b'U' => {
                            let max_digits = if b[i + 1] == b'u' { 4 } else { 8 };
                            let mut val: u32 = 0;
                            let mut j = i + 2;
                            let end = (i + 2 + max_digits).min(b.len());
                            while j < end {
                                if let Some(d) = hex_val(b[j]) {
                                    val = (val << 4) | d;
                                    j += 1;
                                } else {
                                    break;
                                }
                            }
                            if j > i + 2 {
                                push_unicode_scalar(&mut out, val);
                                i = j;
                            } else {
                                out.push(b'\\');
                                out.push(b[i + 1]);
                                i += 2;
                            }
                        }
                        b'c' => {
                            if i + 2 < b.len() {
                                let c = b[i + 2];
                                out.push(if c == b'?' { 0x7f } else { c & 0x1f });
                                i += 3;
                            } else {
                                out.push(b'\\');
                                out.push(b'c');
                                i += 2;
                            }
                        }
                        other => {
                            out.push(b'\\');
                            out.push(other);
                            i += 2;
                        }
                    }
                } else {
                    out.push(b[i]);
                    i += 1;
                }
            }
        }
    }

    String::from_utf8_lossy(&out).into_owned()
}

fn parse_meta_str(content: &str, fallback_sid: &str) -> MetaInfo {
    let mut sid = fallback_sid.to_owned();
    let mut pid: u32 = 0;
    let mut cwd: Option<String> = None;
    let mut agent = String::from("-");
    let mut started = String::new();

    for line in content.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() || trimmed.starts_with('#') {
            continue;
        }
        let Some((key, raw_val)) = line.split_once('=') else {
            continue;
        };
        let key = key.trim();
        let val = unescape_bash_word(raw_val);
        match key {
            "sid" => {
                if !val.is_empty() {
                    sid = val;
                }
            }
            "pid" => {
                pid = val.trim().parse::<u32>().unwrap_or(0);
            }
            "cwd" => {
                cwd = if val.is_empty() { None } else { Some(val) };
            }
            "agent" => {
                agent = if val.is_empty() {
                    String::from("-")
                } else {
                    val
                };
            }
            "started" => {
                started = val;
            }
            _ => {}
        }
    }

    MetaInfo {
        sid,
        pid,
        cwd,
        agent,
        started,
    }
}

fn parse_meta_file(path: &Path, fallback_sid: &str) -> Option<MetaInfo> {
    let bytes = fs::read(path).ok()?;
    let text = String::from_utf8_lossy(&bytes);
    Some(parse_meta_str(&text, fallback_sid))
}

fn collect_meta_entries(state_dir: &Path) -> Vec<MetaInfo> {
    let Ok(rd) = fs::read_dir(state_dir) else {
        return Vec::new();
    };
    let mut files: Vec<(String, PathBuf)> = rd
        .filter_map(Result::ok)
        .filter_map(|entry| {
            let path = entry.path();
            if !path.is_file() {
                return None;
            }
            if path.extension() != Some(OsStr::new("meta")) {
                return None;
            }
            let stem = path.file_stem()?.to_string_lossy().into_owned();
            Some((stem, path))
        })
        .collect();
    files.sort_by(|a, b| a.0.cmp(&b.0));
    files
        .into_iter()
        .filter_map(|(stem, path)| parse_meta_file(&path, &stem))
        .collect()
}

/// Return every target session ID referenced by `--session-id` or `--resume`
/// in a NUL-separated `/proc/<pid>/cmdline` buffer.
pub fn match_cmdline_for_sids<'a>(
    cmdline: &'a [u8],
    target_sids: &HashSet<&[u8]>,
) -> Vec<&'a [u8]> {
    let args: Vec<&[u8]> = cmdline
        .split(|&b| b == b'\0')
        .filter(|s| !s.is_empty())
        .collect();
    let mut matched = Vec::new();
    let mut i = 0;
    while i < args.len() {
        let arg = args[i];
        if arg == b"--session-id" || arg == b"--resume" {
            if let Some(&sid_bytes) = args.get(i + 1) {
                if target_sids.contains(sid_bytes) {
                    matched.push(sid_bytes);
                    i += 2;
                    continue;
                }
            }
        } else if let Some(rest) = arg
            .strip_prefix(b"--session-id=")
            .or_else(|| arg.strip_prefix(b"--resume="))
        {
            if target_sids.contains(rest) {
                matched.push(rest);
            }
        }
        i += 1;
    }
    matched
}

fn scan_proc_liveness(
    proc_dir: &Path,
    target_sids: &HashSet<&[u8]>,
) -> HashMap<Vec<u8>, Vec<u32>> {
    let mut hits: HashMap<Vec<u8>, Vec<u32>> = HashMap::new();
    if target_sids.is_empty() {
        return hits;
    }
    let Ok(rd) = fs::read_dir(proc_dir) else {
        return hits;
    };
    for entry in rd.filter_map(Result::ok) {
        let Some(name) = entry.file_name().to_str().map(str::to_owned) else {
            continue;
        };
        let Ok(pid) = name.parse::<u32>() else {
            continue;
        };
        if pid == 0 {
            continue;
        }
        let Ok(cmdline) = fs::read(entry.path().join("cmdline")) else {
            continue;
        };
        if cmdline.is_empty() {
            continue;
        }
        for sid_bytes in match_cmdline_for_sids(&cmdline, target_sids) {
            hits.entry(sid_bytes.to_vec()).or_default().push(pid);
        }
    }
    hits
}

pub fn classify_liveness(
    meta_pid: u32,
    mut live_pids: Vec<u32>,
) -> (Vec<u32>, &'static str, bool) {
    live_pids.sort_unstable();
    live_pids.dedup();
    if live_pids.is_empty() {
        (live_pids, "dead", false)
    } else if live_pids.len() == 1 && live_pids[0] == meta_pid {
        (live_pids, "alive", false)
    } else {
        (live_pids, "alive", true)
    }
}

fn parallel_map<T, R, F>(items: &[T], f: F) -> Vec<R>
where
    T: Sync,
    R: Send,
    F: Fn(&T) -> R + Sync,
{
    if items.is_empty() {
        return Vec::new();
    }
    let workers = std::thread::available_parallelism()
        .map_or(1, |n| n.get())
        .min(items.len());
    if workers <= 1 {
        return items.iter().map(&f).collect();
    }
    let next = AtomicUsize::new(0);
    let mut slots: Vec<Option<R>> = (0..items.len()).map(|_| None).collect();
    std::thread::scope(|s| {
        let handles: Vec<_> = (0..workers)
            .map(|_| {
                s.spawn(|| {
                    let mut done = Vec::new();
                    loop {
                        let idx = next.fetch_add(1, Ordering::Relaxed);
                        if idx >= items.len() {
                            break done;
                        }
                        done.push((idx, f(&items[idx])));
                    }
                })
            })
            .collect();
        for h in handles {
            for (idx, val) in h.join().expect("worker thread panicked") {
                slots[idx] = Some(val);
            }
        }
    });
    slots
        .into_iter()
        .map(|slot| slot.expect("every item processed"))
        .collect()
}

/// Parse one daemon `state.json` payload matching `jq`'s `(.intent // .name // "")[0:60]`.
pub fn parse_state_json(bytes: &[u8], dir_name: &str) -> Option<DaemonJob> {
    let val: Value = serde_json::from_slice(bytes).ok()?;
    let obj = val.as_object()?;
    let short = obj
        .get("daemonShort")
        .and_then(Value::as_str)
        .filter(|s| !s.is_empty())
        .unwrap_or(dir_name)
        .to_owned();
    let state = obj
        .get("state")
        .and_then(Value::as_str)
        .unwrap_or("")
        .to_owned();
    let updated = obj
        .get("updatedAt")
        .and_then(Value::as_str)
        .unwrap_or("")
        .to_owned();
    let name = obj
        .get("name")
        .and_then(Value::as_str)
        .unwrap_or("")
        .to_owned();
    let raw_intent = match obj.get("intent") {
        Some(Value::String(s)) => s.clone(),
        Some(Value::Null) | None | Some(Value::Bool(false)) => name.clone(),
        Some(other) => other.to_string(),
    };
    let intent: String = raw_intent.chars().take(60).collect();
    let cwd = obj
        .get("cwd")
        .and_then(Value::as_str)
        .filter(|s| !s.is_empty())
        .map(str::to_owned);

    Some(DaemonJob {
        short,
        state,
        updated,
        intent,
        raw_intent,
        name,
        cwd,
    })
}

fn collect_daemons(jobs_dir: &Path) -> Vec<DaemonJob> {
    let Ok(rd) = fs::read_dir(jobs_dir) else {
        return Vec::new();
    };
    let mut candidates: Vec<(String, PathBuf)> = rd
        .filter_map(Result::ok)
        .filter_map(|entry| {
            let path = entry.path();
            if !path.is_dir() {
                return None;
            }
            let state_file = path.join("state.json");
            if !state_file.is_file() {
                return None;
            }
            let dir_name = entry.file_name().to_string_lossy().into_owned();
            Some((dir_name, state_file))
        })
        .collect();
    candidates.sort_by(|a, b| a.0.cmp(&b.0));

    parallel_map(&candidates, |(dir_name, state_file)| {
        let bytes = fs::read(state_file).ok()?;
        parse_state_json(&bytes, dir_name)
    })
    .into_iter()
    .flatten()
    .collect()
}

/// Encode a `cwd` path to Claude Code's `~/.claude/projects/<encoded-cwd>` dirname.
/// Every non-ASCII-alphanumeric character becomes `'-'`.
pub fn encode_cwd_dirname(cwd: &str) -> String {
    cwd.chars()
        .map(|c| if c.is_ascii_alphanumeric() { c } else { '-' })
        .collect()
}

fn resolve_transcripts(
    projects_dir: &Path,
    queries: &[(&str, Option<&str>)],
) -> Vec<Option<PathBuf>> {
    let mut results: Vec<Option<PathBuf>> = vec![None; queries.len()];
    if queries.is_empty() || !projects_dir.is_dir() {
        return results;
    }

    let mut unresolved: Vec<usize> = Vec::new();
    for (idx, (sid, meta_cwd)) in queries.iter().enumerate() {
        let filename = format!("{sid}.jsonl");
        let mut found = None;
        if let Some(cwd) = meta_cwd {
            let primary = projects_dir.join(encode_cwd_dirname(cwd)).join(&filename);
            if primary.is_file() {
                found = Some(primary);
            } else {
                let legacy = projects_dir.join(cwd.replace('/', "-")).join(&filename);
                if legacy.is_file() {
                    found = Some(legacy);
                }
            }
        }
        if found.is_some() {
            results[idx] = found;
        } else {
            unresolved.push(idx);
        }
    }

    if unresolved.is_empty() {
        return results;
    }

    // Fallback depth-2 scan over projects_dir only when at least one session remains unresolved.
    let Ok(rd) = fs::read_dir(projects_dir) else {
        return results;
    };

    if unresolved.len() <= 4 {
        let mut remaining = unresolved;
        for entry in rd.filter_map(Result::ok) {
            if remaining.is_empty() {
                break;
            }
            let subdir = entry.path();
            if !subdir.is_dir() {
                continue;
            }
            let mut still_missing = Vec::with_capacity(remaining.len());
            for idx in remaining {
                let candidate = subdir.join(format!("{}.jsonl", queries[idx].0));
                if candidate.is_file() {
                    results[idx] = Some(candidate);
                } else {
                    still_missing.push(idx);
                }
            }
            remaining = still_missing;
        }
    } else {
        let mut by_filename: HashMap<String, Vec<usize>> = HashMap::with_capacity(unresolved.len());
        for idx in unresolved {
            by_filename
                .entry(format!("{}.jsonl", queries[idx].0))
                .or_default()
                .push(idx);
        }
        for entry in rd.filter_map(Result::ok) {
            if by_filename.is_empty() {
                break;
            }
            let subdir = entry.path();
            if !subdir.is_dir() {
                continue;
            }
            let Ok(sub_rd) = fs::read_dir(&subdir) else {
                continue;
            };
            for file_entry in sub_rd.filter_map(Result::ok) {
                let name = file_entry.file_name();
                let Some(name_str) = name.to_str() else {
                    continue;
                };
                if let Some(indices) = by_filename.get(name_str) {
                    let path = file_entry.path();
                    if path.is_file() {
                        for &idx in indices {
                            results[idx] = Some(path.clone());
                        }
                        by_filename.remove(name_str);
                        if by_filename.is_empty() {
                            break;
                        }
                    }
                }
            }
        }
    }

    results
}

fn contains_bytes(haystack: &[u8], needle: &[u8]) -> bool {
    if needle.is_empty() {
        return true;
    }
    haystack.windows(needle.len()).any(|w| w == needle)
}

fn extract_user_text(obj: &serde_json::Map<String, Value>) -> Option<String> {
    if obj.get("type").and_then(Value::as_str) != Some("user") {
        return None;
    }
    let content = obj.get("message").and_then(|m| m.get("content"))?;
    match content {
        Value::String(t) => (!t.is_empty()).then(|| t.clone()),
        Value::Array(arr) => arr.iter().find_map(|blk| {
            if blk.get("type").and_then(Value::as_str) == Some("text") {
                blk.get("text")
                    .and_then(Value::as_str)
                    .filter(|t| !t.is_empty())
                    .map(str::to_owned)
            } else {
                None
            }
        }),
        _ => None,
    }
}

/// Extract `(cwd, first_user_text)` from a JSONL head buffer.
///
/// Tolerates lossy UTF-8 splits and truncated trailing JSON lines.
pub fn parse_jsonl_head_bytes(
    buf: &[u8],
    mut need_cwd: bool,
) -> (Option<String>, Option<String>) {
    let mut found_cwd: Option<String> = None;
    let mut first_user_text: Option<String> = None;

    for raw_line in buf.split(|&b| b == b'\n') {
        let line = raw_line.strip_suffix(b"\r").unwrap_or(raw_line);
        if line.iter().all(|b| b.is_ascii_whitespace()) {
            continue;
        }
        if !need_cwd && !contains_bytes(line, b"user") {
            continue;
        }
        let s = String::from_utf8_lossy(line);
        let Ok(Value::Object(obj)) = serde_json::from_str::<Value>(&s) else {
            continue;
        };
        if need_cwd {
            if let Some(cwd) = obj
                .get("cwd")
                .and_then(Value::as_str)
                .filter(|c| !c.is_empty())
            {
                found_cwd = Some(cwd.to_owned());
                need_cwd = false;
            }
        }
        if first_user_text.is_none() {
            first_user_text = extract_user_text(&obj);
        }
        if !need_cwd && first_user_text.is_some() {
            break;
        }
    }

    (found_cwd, first_user_text)
}

fn read_jsonl_head(
    path: &Path,
    head_bytes: usize,
    need_cwd: bool,
) -> (Option<String>, Option<String>) {
    if head_bytes == 0 {
        return (None, None);
    }
    let Ok(file) = File::open(path) else {
        return (None, None);
    };
    let mut buf = Vec::with_capacity(head_bytes.min(65_536));
    if file.take(head_bytes as u64).read_to_end(&mut buf).is_err() {
        return (None, None);
    }
    parse_jsonl_head_bytes(&buf, need_cwd)
}

pub fn scan_all(cfg: &Config) -> ScanResult {
    let metas = collect_meta_entries(&cfg.state_dir);
    let target_sids: HashSet<&[u8]> = metas.iter().map(|m| m.sid.as_bytes()).collect();
    let mut live_by_sid = scan_proc_liveness(&cfg.proc_dir, &target_sids);

    let queries: Vec<(&str, Option<&str>)> = metas
        .iter()
        .map(|m| (m.sid.as_str(), m.cwd.as_deref()))
        .collect();
    let transcript_paths = resolve_transcripts(&cfg.projects_dir, &queries);

    let head_inputs: Vec<(Option<&Path>, bool)> = metas
        .iter()
        .zip(transcript_paths.iter())
        .map(|(m, tp)| (tp.as_deref(), m.cwd.is_none()))
        .collect();

    let (head_results, daemons) = std::thread::scope(|s| {
        let daemons_handle = s.spawn(|| collect_daemons(&cfg.jobs_dir));
        let heads = parallel_map(&head_inputs, |(tp, need_cwd)| match tp {
            Some(path) => read_jsonl_head(path, cfg.head_bytes, *need_cwd),
            None => (None, None),
        });
        let daemons = daemons_handle
            .join()
            .expect("daemon collector thread panicked");
        (heads, daemons)
    });

    let sessions = metas
        .into_iter()
        .zip(transcript_paths)
        .zip(head_results)
        .map(|((meta, tpath), (json_cwd, first_user_text))| {
            let live = live_by_sid
                .remove(meta.sid.as_bytes())
                .unwrap_or_default();
            let (live_pids, state, resumed) = classify_liveness(meta.pid, live);
            let cwd = meta.cwd.or(json_cwd);
            let transcript_path = tpath.map(|p| p.to_string_lossy().into_owned());
            Session {
                sid: meta.sid,
                pid: meta.pid,
                live_pids,
                state,
                resumed,
                agent: meta.agent,
                started: meta.started,
                cwd,
                transcript_path,
                first_user_text,
            }
        })
        .collect();

    ScanResult { sessions, daemons }
}

pub fn scan_uuid(cfg: &Config, uuid: &str) -> Option<Session> {
    let meta_path = cfg.state_dir.join(format!("{uuid}.meta"));
    let meta = if meta_path.is_file() {
        parse_meta_file(&meta_path, uuid)
    } else {
        None
    };

    let mut target_sids = HashSet::new();
    target_sids.insert(uuid.as_bytes());
    let mut live_by_sid = scan_proc_liveness(&cfg.proc_dir, &target_sids);
    let live = live_by_sid.remove(uuid.as_bytes()).unwrap_or_default();

    let meta_cwd = meta.as_ref().and_then(|m| m.cwd.as_deref());
    let tpath = resolve_transcripts(&cfg.projects_dir, &[(uuid, meta_cwd)])
        .into_iter()
        .next()
        .flatten();

    if meta.is_none() && tpath.is_none() && live.is_empty() {
        return None;
    }

    let need_cwd = meta_cwd.is_none();
    let (json_cwd, first_user_text) = match tpath.as_deref() {
        Some(path) => read_jsonl_head(path, cfg.head_bytes, need_cwd),
        None => (None, None),
    };

    let (sid, pid, agent, started, cwd) = match meta {
        Some(m) => (m.sid, m.pid, m.agent, m.started, m.cwd.or(json_cwd)),
        None => (
            uuid.to_owned(),
            0,
            String::from("-"),
            String::new(),
            json_cwd,
        ),
    };
    let (live_pids, state, resumed) = classify_liveness(pid, live);
    let transcript_path = tpath.map(|p| p.to_string_lossy().into_owned());

    Some(Session {
        sid,
        pid,
        live_pids,
        state,
        resumed,
        agent,
        started,
        cwd,
        transcript_path,
        first_user_text,
    })
}

/// Write `s` as an Elisp double-quoted string literal.
///
/// Escapes `"`, `\`, `\n`, `\r`, `\t`, and all other ASCII control bytes
/// (`< 0x20` or `== 0x7f`) via 3-digit octal (`\NNN`), never `\xHH`.
pub fn lisp_string(w: &mut impl Write, s: &str) -> io::Result<()> {
    w.write_all(b"\"")?;
    let bytes = s.as_bytes();
    let mut start = 0;
    for (idx, &b) in bytes.iter().enumerate() {
        let esc: Option<&[u8]> = match b {
            b'"' => Some(b"\\\""),
            b'\\' => Some(b"\\\\"),
            b'\n' => Some(b"\\n"),
            b'\r' => Some(b"\\r"),
            b'\t' => Some(b"\\t"),
            0x00..=0x1f | 0x7f => None,
            _ => continue,
        };
        if start < idx {
            w.write_all(&bytes[start..idx])?;
        }
        if let Some(seq) = esc {
            w.write_all(seq)?;
        } else {
            write!(w, "\\{:03o}", b)?;
        }
        start = idx + 1;
    }
    if start < bytes.len() {
        w.write_all(&bytes[start..])?;
    }
    w.write_all(b"\"")
}

fn write_opt_lisp_string(w: &mut impl Write, opt: Option<&str>) -> io::Result<()> {
    match opt {
        Some(s) => lisp_string(w, s),
        None => w.write_all(b"nil"),
    }
}

fn write_session_plist(w: &mut impl Write, s: &Session) -> io::Result<()> {
    w.write_all(b"(:sid ")?;
    lisp_string(w, &s.sid)?;
    write!(w, " :pid {} :live-pids (", s.pid)?;
    for (i, pid) in s.live_pids.iter().enumerate() {
        if i > 0 {
            w.write_all(b" ")?;
        }
        write!(w, "{pid}")?;
    }
    w.write_all(b") :state ")?;
    lisp_string(w, s.state)?;
    w.write_all(if s.resumed {
        b" :resumed t :agent "
    } else {
        b" :resumed nil :agent "
    })?;
    lisp_string(w, &s.agent)?;
    w.write_all(b" :started ")?;
    lisp_string(w, &s.started)?;
    w.write_all(b" :cwd ")?;
    write_opt_lisp_string(w, s.cwd.as_deref())?;
    w.write_all(b" :transcript-path ")?;
    write_opt_lisp_string(w, s.transcript_path.as_deref())?;
    w.write_all(b" :first-user-text ")?;
    write_opt_lisp_string(w, s.first_user_text.as_deref())?;
    w.write_all(b")")
}

fn write_daemon_plist(w: &mut impl Write, d: &DaemonJob) -> io::Result<()> {
    w.write_all(b"(:short ")?;
    lisp_string(w, &d.short)?;
    w.write_all(b" :state ")?;
    lisp_string(w, &d.state)?;
    w.write_all(b" :updated ")?;
    lisp_string(w, &d.updated)?;
    w.write_all(b" :intent ")?;
    lisp_string(w, &d.intent)?;
    w.write_all(b" :raw-intent ")?;
    lisp_string(w, &d.raw_intent)?;
    w.write_all(b" :name ")?;
    lisp_string(w, &d.name)?;
    w.write_all(b" :cwd ")?;
    write_opt_lisp_string(w, d.cwd.as_deref())?;
    w.write_all(b")")
}

pub fn write_full_lisp(w: &mut impl Write, res: &ScanResult) -> io::Result<()> {
    w.write_all(b"(:sessions (")?;
    for (i, s) in res.sessions.iter().enumerate() {
        if i > 0 {
            w.write_all(b" ")?;
        }
        write_session_plist(w, s)?;
    }
    w.write_all(b") :daemons (")?;
    for (i, d) in res.daemons.iter().enumerate() {
        if i > 0 {
            w.write_all(b" ")?;
        }
        write_daemon_plist(w, d)?;
    }
    w.write_all(b"))\n")
}

pub fn write_uuid_lisp(w: &mut impl Write, session: Option<&Session>) -> io::Result<()> {
    match session {
        Some(s) => {
            write_session_plist(w, s)?;
            w.write_all(b"\n")
        }
        None => w.write_all(b"nil\n"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bash_unescape_variants() {
        assert_eq!(unescape_bash_word("plain"), "plain");
        assert_eq!(unescape_bash_word("/a/b/c"), "/a/b/c");
        assert_eq!(unescape_bash_word("''"), "");
        assert_eq!(unescape_bash_word(r#""""#), "");
        assert_eq!(unescape_bash_word(r"a\ b"), "a b");
        assert_eq!(
            unescape_bash_word(r#"\{\"k\":1\}"#),
            r#"{"k":1}"#
        );
        assert_eq!(unescape_bash_word(r"foo\;bar"), "foo;bar");
        assert_eq!(
            unescape_bash_word(r"$'line1\nline2\t\'x\'\\y\x41\u00e9\001'"),
            "line1\nline2\t'x'\\yAé\x01"
        );
        assert_eq!(unescape_bash_word(r"$'ctrl:\cA\c?'"), "ctrl:\x01\x7f");
        assert_eq!(unescape_bash_word(r"$'unknown:\q'"), r"unknown:\q");
        assert_eq!(unescape_bash_word(r#""a\"b\$c\\d""#), r#"a"b$c\d"#);
        assert_eq!(unescape_bash_word("'it'\\''s ok'"), "it's ok");
        assert_eq!(unescape_bash_word("unicode_中文_⑂"), "unicode_中文_⑂");
    }

    #[test]
    fn encode_cwd_matches_claude_rules() {
        assert_eq!(encode_cwd_dirname("/home/fenrir/.emacs.d"), "-home-fenrir--emacs-d");
        assert_eq!(
            encode_cwd_dirname("/home/fenrir/.claude_opus-5.5"),
            "-home-fenrir--claude-opus-5-5"
        );
        assert_eq!(
            encode_cwd_dirname("/home/fenrir/Downloads/Rust crate split-v1"),
            "-home-fenrir-Downloads-Rust-crate-split-v1"
        );
    }

    #[test]
    fn jsonl_head_string_and_array_and_tool_result() {
        let data = concat!(
            "{\"type\":\"system\",\"cwd\":\"/tmp/proj\"}\r\n",
            "{\"type\":\"user\",\"message\":{\"content\":[{\"type\":\"tool_result\",\"content\":\"ok\"}]}}\r\n",
            "{\"type\":\"user\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"\"}]}}\n",
            "{\"type\":\"user\",\"message\":{\"content\":[{\"type\":\"tool_result\"},{\"type\":\"text\",\"text\":\"first\"},{\"type\":\"text\",\"text\":\"second\"}]}}\n"
        );
        let (cwd, text) = parse_jsonl_head_bytes(data.as_bytes(), true);
        assert_eq!(cwd.as_deref(), Some("/tmp/proj"));
        assert_eq!(text.as_deref(), Some("first"));

        let str_data = "{\"type\":\"user\",\"cwd\":\"/a\",\"message\":{\"content\":\"\"}}\n{\"type\":\"user\",\"message\":{\"content\":\"hello world\"}}\n";
        let (cwd2, text2) = parse_jsonl_head_bytes(str_data.as_bytes(), true);
        assert_eq!(cwd2.as_deref(), Some("/a"));
        assert_eq!(text2.as_deref(), Some("hello world"));
    }

    #[test]
    fn jsonl_head_truncation_and_utf8_split() {
        let valid_line = "{\"type\":\"user\",\"cwd\":\"/tmp/u\",\"message\":{\"content\":\"before cut\"}}\n";
        let mut buf = Vec::from(valid_line.as_bytes());
        // Append partial line with a split 3-byte UTF-8 char at the end.
        buf.extend_from_slice("{\"type\":\"assistant\",\"text\":\"中文".as_bytes());
        buf.pop(); // break last UTF-8 sequence
        let (cwd, text) = parse_jsonl_head_bytes(&buf, true);
        assert_eq!(cwd.as_deref(), Some("/tmp/u"));
        assert_eq!(text.as_deref(), Some("before cut"));

        // Huge first line > 64KB followed by user message.
        let big = format!("{{\"type\":\"queue-operation\",\"pad\":\"{}\"}}\n{{\"type\":\"user\",\"message\":{{\"content\":\"after big\"}}}}\n", "x".repeat(70_000));
        let (_, small_head) = parse_jsonl_head_bytes(&big.as_bytes()[..65_536], false);
        assert_eq!(small_head, None);
        let (_, big_head) = parse_jsonl_head_bytes(big.as_bytes(), false);
        assert_eq!(big_head.as_deref(), Some("after big"));
    }

    #[test]
    fn state_json_intent_cjk_and_fallbacks() {
        let cjk_65 = "一".repeat(65);
        let json = format!(
            r#"{{"daemonShort":"d1","state":"running","updatedAt":"2026-11-25T00:00:00Z","intent":"{cjk_65}","name":"fallback","cwd":"/tmp/x"}}"#
        );
        let d = parse_state_json(json.as_bytes(), "dir1").unwrap();
        assert_eq!(d.short, "d1");
        assert_eq!(d.intent.chars().count(), 60);
        assert_eq!(d.raw_intent.chars().count(), 65);

        // null intent falls back to name
        let null_intent = br#"{"daemonShort":"d2","state":"done","updatedAt":"t","intent":null,"name":"from-name"}"#;
        let d2 = parse_state_json(null_intent, "dir2").unwrap();
        assert_eq!(d2.intent, "from-name");
        assert_eq!(d2.raw_intent, "from-name");

        // empty string "" intent stays "" (matches jq `//`)
        let empty_intent = br#"{"daemonShort":"d3","state":"done","updatedAt":"t","intent":"","name":"ignored"}"#;
        let d3 = parse_state_json(empty_intent, "dir3").unwrap();
        assert_eq!(d3.intent, "");

        // invalid json skipped
        assert!(parse_state_json(b"{broken", "dir4").is_none());
    }

    #[test]
    fn lisp_string_octal_control_escapes() {
        let mut out = Vec::new();
        lisp_string(&mut out, "a\x01a\nb\tc\rd\"e\\f\x7f中文⑂").unwrap();
        assert_eq!(
            String::from_utf8(out).unwrap(),
            "\"a\\001a\\nb\\tc\\rd\\\"e\\\\f\\177中文⑂\""
        );
    }

    #[test]
    fn cmdline_matcher_and_liveness() {
        let sid = b"11111111-2222-3333-4444-555555555555";
        let mut set = HashSet::new();
        set.insert(&sid[..]);

        let ok1 = b"claude\0--session-id\011111111-2222-3333-4444-555555555555\0";
        assert_eq!(match_cmdline_for_sids(ok1, &set), vec![&sid[..]]);

        let ok2 = b"claude\0--resume=11111111-2222-3333-4444-555555555555\0";
        assert_eq!(match_cmdline_for_sids(ok2, &set), vec![&sid[..]]);

        // Prompt argument containing flag text must NOT match.
        let prompt_arg = b"claude\0-p\0check --session-id 11111111-2222-3333-4444-555555555555\0";
        assert!(match_cmdline_for_sids(prompt_arg, &set).is_empty());

        assert_eq!(classify_liveness(10, vec![]), (vec![], "dead", false));
        assert_eq!(classify_liveness(10, vec![10]), (vec![10], "alive", false));
        assert_eq!(classify_liveness(10, vec![20]), (vec![20], "alive", true));
        assert_eq!(
            classify_liveness(10, vec![30, 10, 30]),
            (vec![10, 30], "alive", true)
        );
    }

    #[test]
    fn cli_arg_validation() {
        let args: Vec<OsString> = vec!["--uuid".into(), "../bad".into()];
        assert!(parse_args(&args).is_err());
        let args2: Vec<OsString> = vec!["--uuid".into(), "a/b".into()];
        assert!(parse_args(&args2).is_err());
        let args3: Vec<OsString> = vec!["--head-bytes".into(), "notanint".into()];
        assert!(parse_args(&args3).is_err());
        let args4: Vec<OsString> = vec!["--help".into()];
        assert_eq!(parse_args(&args4).unwrap(), None);
    }

    #[test]
    fn resolve_transcripts_more_than_four_unresolved_and_head_bytes_zero() {
        let tmp = std::env::temp_dir().join(format!("cjs-t5-{}", std::process::id()));
        let _ = fs::remove_dir_all(&tmp);
        let state = tmp.join("state");
        let jobs = tmp.join("jobs");
        let proj1 = tmp.join("projects/sub-a");
        let proj2 = tmp.join("projects/sub-b");
        fs::create_dir_all(&state).unwrap();
        fs::create_dir_all(&jobs).unwrap();
        fs::create_dir_all(&proj1).unwrap();
        fs::create_dir_all(&proj2).unwrap();

        for i in 1..=6 {
            let sid = format!("11111111-1111-4111-8111-00000000000{i}");
            // Omit cwd= so all 6 sessions hit the `unresolved.len() > 4` depth-2 map scan.
            fs::write(
                state.join(format!("{sid}.meta")),
                format!("sid={sid}\npid=badpid\nstarted=2026-11-25T0{i}:00:00Z\n"),
            )
            .unwrap();
            let dir = if i <= 3 { &proj1 } else { &proj2 };
            fs::write(
                dir.join(format!("{sid}.jsonl")),
                format!(
                    "{{\"type\":\"user\",\"cwd\":\"/tmp/p={i}\",\"message\":{{\"content\":\"prompt {i}\"}}}}\n"
                ),
            )
            .unwrap();
        }

        let cfg = Config {
            state_dir: state,
            jobs_dir: jobs,
            projects_dir: tmp.join("projects"),
            proc_dir: tmp.join("no-proc"),
            head_bytes: DEFAULT_HEAD_BYTES,
            uuid: None,
        };
        let res = scan_all(&cfg);
        assert_eq!(res.sessions.len(), 6);
        for (idx, s) in res.sessions.iter().enumerate() {
            let i = idx + 1;
            assert_eq!(s.pid, 0);
            assert!(s.transcript_path.is_some());
            assert_eq!(s.cwd.as_deref(), Some(format!("/tmp/p={i}").as_str()));
            assert_eq!(
                s.first_user_text.as_deref(),
                Some(format!("prompt {i}").as_str())
            );
        }

        let cfg_zero = Config {
            head_bytes: 0,
            ..cfg
        };
        let res_zero = scan_all(&cfg_zero);
        assert!(res_zero
            .sessions
            .iter()
            .all(|s| s.first_user_text.is_none() && s.transcript_path.is_some()));

        let _ = fs::remove_dir_all(&tmp);
    }

    #[test]
    fn cli_missing_flag_values_and_state_json_non_object() {
        for flag in [
            "--state-dir",
            "--jobs-dir",
            "--projects-dir",
            "--head-bytes",
            "--uuid",
        ] {
            let args: Vec<OsString> = vec![flag.into()];
            assert!(parse_args(&args).is_err(), "expected err for trailing {flag}");
        }
        assert!(parse_state_json(b"", "empty").is_none());
        assert!(parse_state_json(b"[1,2,3]", "arr").is_none());
        let d = parse_state_json(
            br#"{"daemonShort":"","state":"running","updatedAt":"2026-11-25T00:00:00Z","intent":false,"name":"fallback-name"}"#,
            "dir-fallback",
        )
        .unwrap();
        assert_eq!(d.short, "dir-fallback");
        assert_eq!(d.intent, "fallback-name");
    }
}
