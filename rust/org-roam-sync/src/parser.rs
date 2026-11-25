use std::borrow::Cow;
use std::collections::{HashMap, HashSet};
use std::path::Path;
use std::sync::OnceLock;

use regex::Regex;

use crate::sexpr::{
    format_alist, format_link_properties, format_string_list, split_string_and_unquote,
};

const KNOWN_PROTOCOLS: &[&str] = &[
    "attachment",
    "elisp",
    "file+emacs",
    "file+sys",
    "file",
    "ftp",
    "help",
    "https",
    "http",
    "id",
    "mailto",
    "news",
    "roam",
    "shell",
];

// Non-word BMP/astral Unicode ranges in Emacs `org-mode-syntax-table` (`char-syntax != ?w`).
// Used for exact `\<` word-boundary and `[[:punct:]]` parity in `org-link-plain-re`.
const NON_WORD_RANGES: &[(u32, u32)] = &[
    (0x00a0, 0x00a4),
    (0x00a6, 0x00b1),
    (0x00b4, 0x00b4),
    (0x00b6, 0x00b6),
    (0x00b8, 0x00b8),
    (0x00ba, 0x00bf),
    (0x00d7, 0x00d7),
    (0x00f7, 0x00f7),
    (0x02c7, 0x02c7),
    (0x02c9, 0x02c9),
    (0x02d0, 0x02d0),
    (0x02d8, 0x02db),
    (0x02dd, 0x02dd),
    (0x0384, 0x0385),
    (0x05be, 0x05be),
    (0x05c0, 0x05c0),
    (0x05c3, 0x05c3),
    (0x05c6, 0x05c6),
    (0x0e2f, 0x0e2f),
    (0x0e3f, 0x0e3f),
    (0x0e46, 0x0e46),
    (0x0e4f, 0x0e4f),
    (0x0e5a, 0x0e5b),
    (0x0eaf, 0x0eaf),
    (0x0ec6, 0x0ec6),
    (0x0f00, 0x0f0b),
    (0x0f0d, 0x0f18),
    (0x0f1a, 0x0f1f),
    (0x0f34, 0x0f34),
    (0x0f36, 0x0f36),
    (0x0f38, 0x0f3f),
    (0x0f7f, 0x0f7f),
    (0x0f85, 0x0f85),
    (0x0fbe, 0x0fcf),
    (0x1361, 0x1368),
    (0x1800, 0x180a),
    (0x2000, 0x2026),
    (0x202f, 0x205f),
    (0x207d, 0x207e),
    (0x208d, 0x208e),
    (0x20ac, 0x20ac),
    (0x2103, 0x2103),
    (0x2109, 0x2109),
    (0x2116, 0x2116),
    (0x2121, 0x2122),
    (0x2153, 0x2154),
    (0x215b, 0x215e),
    (0x2190, 0x244f),
    (0x2460, 0x246e),
    (0x2474, 0x24b5),
    (0x2500, 0x254b),
    (0x2592, 0x2592),
    (0x25a0, 0x25a1),
    (0x25a3, 0x25a9),
    (0x25b2, 0x25b3),
    (0x25b6, 0x25b7),
    (0x25bc, 0x25bd),
    (0x25c0, 0x25c1),
    (0x25c6, 0x25c8),
    (0x25cb, 0x25cb),
    (0x25ce, 0x25d1),
    (0x25ef, 0x25ef),
    (0x2605, 0x2606),
    (0x260e, 0x260f),
    (0x261c, 0x261c),
    (0x261e, 0x261e),
    (0x2640, 0x2640),
    (0x2642, 0x2642),
    (0x2660, 0x2661),
    (0x2663, 0x2665),
    (0x2667, 0x266a),
    (0x266c, 0x266d),
    (0x266f, 0x266f),
    (0x2768, 0x276d),
    (0x2770, 0x2775),
    (0x27e6, 0x27eb),
    (0x2983, 0x2998),
    (0x29fc, 0x29fd),
    (0x2a00, 0x2bff),
    (0x2e00, 0x2e7f),
    (0x3000, 0x3003),
    (0x3008, 0x301c),
    (0x30fb, 0x30fb),
    (0x3200, 0x321c),
    (0x3220, 0x3229),
    (0x3260, 0x327b),
    (0x327e, 0x327f),
    (0x3380, 0x3384),
    (0x3388, 0x33ca),
    (0x33cf, 0x33d0),
    (0x33d3, 0x33d3),
    (0x33d6, 0x33d6),
    (0x33d8, 0x33d8),
    (0x33db, 0x33dd),
    (0xaadb, 0xaadf),
    (0xfd3e, 0xfd3f),
    (0xfe35, 0xfe44),
    (0xfe59, 0xfe5e),
    (0xff01, 0xff0f),
    (0xff1b, 0xff20),
    (0xff3b, 0xff40),
    (0xff5b, 0xff65),
    (0xffe0, 0xffe3),
    (0xffe5, 0xffe5),
    (0x11660, 0x1166c),
    (0x1fb00, 0x1fbff),
];

#[inline]
fn is_org_word_char(c: char) -> bool {
    let cp = c as u32;
    if cp < 0x80 {
        matches!(
            c,
            '$' | '%' | '\'' | '0'..='9' | 'A'..='Z' | 'a'..='z'
        )
    } else {
        NON_WORD_RANGES
            .binary_search_by(|&(lo, hi)| {
                if cp < lo {
                    std::cmp::Ordering::Greater
                } else if cp > hi {
                    std::cmp::Ordering::Less
                } else {
                    std::cmp::Ordering::Equal
                }
            })
            .is_err()
    }
}

#[inline]
fn is_emacs_punct(c: char) -> bool {
    let cp = c as u32;
    if cp < 0x80 {
        matches!(
            c,
            '!'..='/' | ':'..='@' | '['..='`' | '{'..='~'
        )
    } else {
        !is_org_word_char(c)
    }
}

#[derive(Debug, Clone)]
pub struct ParsedNode {
    pub id: String,
    pub file: String,
    pub level: i64,
    pub pos: i64,
    pub todo: Option<String>,
    pub priority: Option<i64>,
    pub scheduled: Option<String>,
    pub deadline: Option<String>,
    pub title: String,
    pub properties: Option<String>,
    pub olp: Option<String>,
}

#[derive(Debug, Clone)]
pub struct ParsedCitation {
    pub node_id: String,
    pub cite_key: String,
    pub pos: i64,
    pub properties: String,
}

#[derive(Debug, Clone)]
pub struct ParsedLink {
    pub pos: i64,
    pub source: String,
    pub dest: String,
    pub link_type: String,
    pub properties: String,
}

#[derive(Debug, Clone)]
pub struct ParsedOrgData {
    pub file_title: String,
    pub nodes: Vec<ParsedNode>,
    pub aliases: Vec<(String, String)>,
    pub tags: Vec<(String, String)>,
    pub refs: Vec<(String, String, String)>,
    pub citations: Vec<ParsedCitation>,
    pub links: Vec<ParsedLink>,
    pub org_ids: Vec<String>,
}

#[derive(Debug, Clone)]
struct LineSpan {
    byte_start: usize,
    byte_end: usize, // excluding '\n'
    char_start: usize,
    is_ascii: bool,
}

struct LineIndex<'a> {
    text: &'a str,
    lines: Vec<LineSpan>,
}

impl<'a> LineIndex<'a> {
    fn new(text: &'a str) -> Self {
        let bytes = text.as_bytes();
        let mut lines = Vec::new();
        let mut byte_start = 0usize;
        let mut char_start = 0usize;
        let mut i = 0usize;
        let mut is_ascii = true;

        while i < bytes.len() {
            let b = bytes[i];
            if b == b'\n' {
                let line_str = &text[byte_start..i];
                let char_len = if is_ascii {
                    i - byte_start
                } else {
                    line_str.chars().count()
                };
                lines.push(LineSpan {
                    byte_start,
                    byte_end: i,
                    char_start,
                    is_ascii,
                });
                char_start += char_len + 1;
                byte_start = i + 1;
                is_ascii = true;
            } else if b >= 0x80 {
                is_ascii = false;
            }
            i += 1;
        }
        if byte_start < bytes.len() || lines.is_empty() {
            lines.push(LineSpan {
                byte_start,
                byte_end: bytes.len(),
                char_start,
                is_ascii,
            });
        }

        Self { text, lines }
    }

    fn line_str(&self, idx: usize) -> &'a str {
        let l = &self.lines[idx];
        &self.text[l.byte_start..l.byte_end]
    }

    fn byte_to_char_pos(&self, byte_idx: usize) -> i64 {
        let idx = self
            .lines
            .partition_point(|l| l.byte_start <= byte_idx)
            .saturating_sub(1);
        let l = &self.lines[idx];
        if l.is_ascii {
            (l.char_start + (byte_idx - l.byte_start) + 1) as i64
        } else {
            let clamped = byte_idx.min(l.byte_end);
            let chars = self.text[l.byte_start..clamped].chars().count();
            (l.char_start + chars + 1) as i64
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum LineKind {
    Normal,
    Headline(usize),      // level = count of '*'
    OpaqueBlock,          // inside #+begin_{src,example,comment,export} or \begin{...}
    BlockBoundary,        // #+begin_quote / #+end_quote etc.
    CommentLine,          // ^[ \t]*#(?: |$) (not #+)
    FixedWidth,           // ^[ \t]*:(?: |$) outside drawer
    PropertyDrawerBound,  // :PROPERTIES: or :END: of property drawer
    NodeProperty,         // :KEY: VAL inside valid property drawer
    OtherDrawerBound,     // :LOGBOOK: / :END:
    Planning,             // SCHEDULED:/DEADLINE:/CLOSED: directly after headline
    Keyword,              // #+KEY: VAL outside opaque block
}

#[derive(Debug, Clone)]
struct PropEntry {
    key_upper: String,
    value: String,
}

#[derive(Debug, Clone)]
struct HeadingMeta {
    line_idx: usize,
    level: usize,
    pos: i64,
    todo: Option<String>,
    props_todo: Option<String>,
    priority: Option<u8>,
    props_priority: String,
    raw_title: Option<String>,      // raw match 4 of org-complex-heading-regexp
    display_title: Option<String>,  // org-link-display-format(raw_title)
    olp_title: Option<String>,      // cookie-stripped display_title
    local_tags: Vec<String>,
    scheduled_iso: Option<String>,
    deadline_iso: Option<String>,
    scheduled_raw: Option<String>,
    deadline_raw: Option<String>,
    closed_raw: Option<String>,
    props_in_order: Vec<PropEntry>,
    id: Option<String>,
    roam_exclude: bool,
    blocked: bool,
}

fn bracket_re() -> &'static Regex {
    static RE: OnceLock<Regex> = OnceLock::new();
    RE.get_or_init(|| {
        Regex::new(r"(?s)\[\[((?:[^\[\]\\]|\\(?:\\\\)*[\[\]]|\\+[^\[\]])+)\](?:\[([\s\S]+?)\])?\]")
            .unwrap()
    })
}

fn angle_re() -> &'static Regex {
    static RE: OnceLock<Regex> = OnceLock::new();
    RE.get_or_init(|| {
        Regex::new(r"(?i)<(attachment|elisp|file\+emacs|file\+sys|file|ftp|help|https|http|id|mailto|news|roam|shell):([^>\n]*(?:\n[ \t]*[^>\s\n][^>\n]*)*)>")
            .unwrap()
    })
}

fn ts_active_re() -> &'static Regex {
    static RE: OnceLock<Regex> = OnceLock::new();
    RE.get_or_init(|| {
        Regex::new(r"<(\d{4}-\d{2}-\d{2})[^>\r\n]*?(?: (\d{1,2}):(\d{2})[^>\r\n]*)?>").unwrap()
    })
}

fn ts_inactive_re() -> &'static Regex {
    static RE: OnceLock<Regex> = OnceLock::new();
    RE.get_or_init(|| {
        Regex::new(r"\[\d{4}-\d{2}-\d{2} [A-Za-z][^\r\n\]]*\]").unwrap()
    })
}

fn ts_active_dow_re() -> &'static Regex {
    static RE: OnceLock<Regex> = OnceLock::new();
    RE.get_or_init(|| {
        Regex::new(r"<\d{4}-\d{2}-\d{2} [A-Za-z][^\r\n>]*>").unwrap()
    })
}

fn cookie_re() -> &'static Regex {
    static RE: OnceLock<Regex> = OnceLock::new();
    RE.get_or_init(|| Regex::new(r"\[(?:[0-9]*%|[0-9]*/[0-9]*)\]").unwrap())
}

fn cite_prefix_re() -> &'static Regex {
    static RE: OnceLock<Regex> = OnceLock::new();
    RE.get_or_init(|| Regex::new(r"\[cite(?:/[/_[:alnum:]-]+)?:[ \t\r\n]*").unwrap())
}

fn cite_key_re() -> &'static Regex {
    static RE: OnceLock<Regex> = OnceLock::new();
    RE.get_or_init(|| Regex::new(r"@([!#-+./:<>-@^-`{-~[:word:]-]+)").unwrap())
}

/// Port of Emacs `org-link-display-format`.
pub fn org_link_display_format(s: &str) -> String {
    bracket_re()
        .replace_all(s, |caps: &regex::Captures| {
            if let Some(desc) = caps.get(2) {
                desc.as_str().to_string()
            } else {
                caps.get(1).unwrap().as_str().to_string()
            }
        })
        .into_owned()
}

/// Port of Emacs `org-link-unescape`: collapses `\\[` -> `[`, `\\]` -> `]`,
/// and odd backslash runs before `[` or `]`.
fn org_link_unescape(s: &str) -> String {
    let bytes = s.as_bytes();
    let mut out = String::with_capacity(s.len());
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'\\' {
            let start = i;
            while i < bytes.len() && bytes[i] == b'\\' {
                i += 1;
            }
            let bs_count = i - start;
            if i < bytes.len() && (bytes[i] == b'[' || bytes[i] == b']') {
                // Org's `org-link-unescape` halves backslash escapes only when escaping `[`/`]`
                for _ in 0..(bs_count / 2) {
                    out.push('\\');
                }
                if bs_count % 2 == 1 {
                    out.push(bytes[i] as char);
                    i += 1;
                }
            } else {
                for _ in 0..bs_count {
                    out.push('\\');
                }
            }
        } else {
            let ch = s[i..].chars().next().unwrap();
            out.push(ch);
            i += ch.len_utf8();
        }
    }
    out
}

fn strip_cookies_for_olp(title: &str) -> String {
    let stripped = cookie_re().replace_all(title, "");
    stripped.trim_matches([' ', '\t']).to_string()
}

fn is_opaque_block_name(name_lower: &str) -> bool {
    matches!(
        name_lower,
        "src" | "example" | "comment" | "export"
    )
}

fn is_greater_block_name(name_lower: &str) -> bool {
    matches!(
        name_lower,
        "quote" | "center" | "verse"
    ) || !is_opaque_block_name(name_lower)
}

fn parse_headline_level(line: &str) -> Option<usize> {
    let bytes = line.as_bytes();
    let mut stars = 0;
    while stars < bytes.len() && bytes[stars] == b'*' {
        stars += 1;
    }
    // `org-outline-regexp` is `\*+ ` (strictly ASCII space after stars, never `\t`).
    if stars > 0 && stars < bytes.len() && bytes[stars] == b' ' {
        Some(stars)
    } else {
        None
    }
}

fn parse_begin_block(line: &str) -> Option<String> {
    let trimmed = line.trim_start_matches([' ', '\t']);
    let bytes = trimmed.as_bytes();
    if bytes.len() < 8 || !bytes[..8].eq_ignore_ascii_case(b"#+begin_") {
        return None;
    }
    let rest = &trimmed[8..];
    let name: String = rest
        .chars()
        .take_while(|c| !c.is_whitespace())
        .collect::<String>()
        .to_ascii_lowercase();
    if name.is_empty() {
        None
    } else {
        Some(name)
    }
}

fn is_end_block(line: &str, name_lower: &str) -> bool {
    let trimmed = line
        .trim_start_matches([' ', '\t'])
        .trim_end_matches([' ', '\t', '\r']);
    let bytes = trimmed.as_bytes();
    if bytes.len() < 6 || !bytes[..6].eq_ignore_ascii_case(b"#+end_") {
        return false;
    }
    trimmed[6..].eq_ignore_ascii_case(name_lower)
}

fn parse_latex_begin(line: &str) -> Option<String> {
    let trimmed = line.trim_start_matches([' ', '\t']);
    let rest = trimmed.strip_prefix("\\begin{")?;
    let end = rest.find('}')?;
    let env = &rest[..end];
    if env.is_empty() || !env.chars().all(|c| c.is_ascii_alphanumeric() || c == '*') {
        return None;
    }
    Some(env.to_string())
}

fn is_latex_end(line: &str, env: &str) -> bool {
    let trimmed = line.trim();
    if let Some(rest) = trimmed.strip_prefix("\\end{") {
        if let Some(inner) = rest.strip_suffix('}') {
            return inner == env;
        }
    }
    false
}

fn parse_drawer_open(line: &str) -> Option<String> {
    let trimmed = line.trim_matches([' ', '\t']);
    if trimmed.len() >= 3 && trimmed.starts_with(':') && trimmed.ends_with(':') {
        let inner = &trimmed[1..trimmed.len() - 1];
        if !inner.is_empty()
            && !inner.eq_ignore_ascii_case("END")
            && inner
                .chars()
                .all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-')
        {
            return Some(inner.to_string());
        }
    }
    None
}

fn is_drawer_end(line: &str) -> bool {
    line.trim_matches([' ', '\t']).eq_ignore_ascii_case(":END:")
}

fn parse_node_property_line(line: &str) -> Option<(String, String)> {
    let trimmed = line.trim_start_matches([' ', '\t']);
    let rest = trimmed.strip_prefix(':')?;
    let colon = rest.find(':')?;
    let key = &rest[..colon];
    if key.is_empty() || key.chars().any(|c| c.is_whitespace()) {
        return None;
    }
    let after = &rest[colon + 1..];
    if !after.is_empty() && !after.starts_with([' ', '\t']) {
        return None;
    }
    let val = after.trim();
    Some((key.to_string(), val.to_string()))
}

fn parse_keyword_line(line: &str) -> Option<(String, String)> {
    let trimmed = line.trim_start_matches([' ', '\t']);
    let rest = trimmed.strip_prefix("#+")?;
    let colon = rest.find(':')?;
    let key = &rest[..colon];
    if key.is_empty() || key.chars().any(|c| c.is_whitespace()) {
        return None;
    }
    let val = rest[colon + 1..].trim();
    Some((key.to_string(), val.to_string()))
}

fn is_comment_line(line: &str) -> bool {
    let trimmed = line.trim_start_matches([' ', '\t']);
    if !trimmed.starts_with('#') {
        return false;
    }
    trimmed.len() == 1 || matches!(trimmed.as_bytes()[1], b' ' | b'\t')
}

fn is_fixed_width_line(line: &str) -> bool {
    let trimmed = line.trim_start_matches([' ', '\t']);
    if !trimmed.starts_with(':') {
        return false;
    }
    trimmed.len() == 1 || matches!(trimmed.as_bytes()[1], b' ' | b'\t')
}

fn is_planning_line(line: &str) -> bool {
    let trimmed = line.trim_start_matches([' ', '\t']);
    trimmed.starts_with("SCHEDULED:")
        || trimmed.starts_with("DEADLINE:")
        || trimmed.starts_with("CLOSED:")
}

fn parse_planning_fields(
    line: &str,
    scheduled_iso: &mut Option<String>,
    deadline_iso: &mut Option<String>,
    scheduled_raw: &mut Option<String>,
    deadline_raw: &mut Option<String>,
    closed_raw: &mut Option<String>,
) {
    static PLAN_RE: OnceLock<Regex> = OnceLock::new();
    let re = PLAN_RE.get_or_init(|| {
        Regex::new(r"(SCHEDULED|DEADLINE|CLOSED):[ \t]*(\[[^\]]+\]|<[^>]+>)").unwrap()
    });
    for caps in re.captures_iter(line) {
        let kw = &caps[1];
        let ts = &caps[2];
        match kw {
            "SCHEDULED" => {
                if scheduled_raw.is_none() {
                    *scheduled_raw = Some(ts.to_string());
                    *scheduled_iso = format_org_ts_iso(ts);
                }
            }
            "DEADLINE" => {
                if deadline_raw.is_none() {
                    *deadline_raw = Some(ts.to_string());
                    *deadline_iso = format_org_ts_iso(ts);
                }
            }
            "CLOSED" => {
                if closed_raw.is_none() {
                    *closed_raw = Some(ts.to_string());
                }
            }
            _ => {}
        }
    }
}

fn format_org_ts_iso(ts: &str) -> Option<String> {
    static TS_TIME_RE: OnceLock<Regex> = OnceLock::new();
    let time_re = TS_TIME_RE
        .get_or_init(|| Regex::new(r"<(\d{4}-\d{2}-\d{2})[^>\r\n]*? (\d{1,2}):(\d{2})").unwrap());
    if let Some(caps) = time_re.captures(ts) {
        let date = &caps[1];
        let hh: u32 = caps[2].parse().unwrap_or(0);
        let mm: u32 = caps[3].parse().unwrap_or(0);
        return Some(format!("{}T{:02}:{:02}:00", date, hh, mm));
    }
    let caps = ts_active_re().captures(ts)?;
    Some(format!("{}T00:00:00", &caps[1]))
}

#[derive(Debug, Clone)]
struct TodoKeywords {
    all: Vec<String>,
    active: HashSet<String>,
    done: HashSet<String>,
}

impl TodoKeywords {
    fn default_org() -> Self {
        let mut active = HashSet::new();
        active.insert("TODO".to_string());
        let mut done = HashSet::new();
        done.insert("DONE".to_string());
        Self {
            all: vec!["TODO".to_string(), "DONE".to_string()],
            active,
            done,
        }
    }
}

fn parse_todo_keywords_line(val: &str, out: &mut TodoKeywords) {
    let mut before_pipe: Vec<String> = Vec::new();
    let mut after_pipe: Vec<String> = Vec::new();
    let mut seen_pipe = false;

    for tok in val.split_whitespace() {
        if tok == "|" {
            seen_pipe = true;
            continue;
        }
        let kw = match tok.find('(') {
            Some(idx) => &tok[..idx],
            None => tok,
        };
        if !kw.is_empty() {
            if seen_pipe {
                after_pipe.push(kw.to_string());
            } else {
                before_pipe.push(kw.to_string());
            }
        }
    }

    if !seen_pipe {
        // Without `|`, Org treats the last keyword on the line as DONE and all preceding as active.
        if let Some(last) = before_pipe.pop() {
            after_pipe.push(last);
        }
    }

    for kw in before_pipe {
        if !out.all.iter().any(|k| k == &kw) {
            out.all.push(kw.clone());
        }
        out.done.remove(&kw);
        out.active.insert(kw);
    }
    for kw in after_pipe {
        if !out.all.iter().any(|k| k == &kw) {
            out.all.push(kw.clone());
        }
        out.active.remove(&kw);
        out.done.insert(kw);
    }
}

fn is_valid_tag_group(tag_part: &str) -> bool {
    tag_part.len() >= 3
        && tag_part.starts_with(':')
        && tag_part.ends_with(':')
        && tag_part
            .chars()
            .all(|c| c.is_alphanumeric() || matches!(c, '_' | '@' | '#' | '%' | ':'))
}

/// Check if `after` (immediately following a candidate TODO keyword or `[#X]` cookie)
/// satisfies `org-complex-heading-regexp`: empty, starts with ASCII `' '`, all `[ \t]`,
/// or `[ \t]+:tags:[ \t]*$`.
fn after_token_matches_complex(after: &str) -> bool {
    if after.is_empty() || after.starts_with(' ') {
        return true;
    }
    let trimmed_end = after.trim_end_matches([' ', '\t']);
    if trimmed_end.is_empty() {
        return true;
    }
    let trimmed_start = trimmed_end.trim_start_matches([' ', '\t']);
    trimmed_start.len() < trimmed_end.len() && is_valid_tag_group(trimmed_start)
}

/// Port of Emacs `org-remove-tabs` (default tab-width 8).
fn org_remove_tabs(s: &str) -> String {
    if !s.contains('\t') {
        return s.to_string();
    }
    let width = 8usize;
    let mut out = String::with_capacity(s.len());
    let mut col = 0usize;
    for ch in s.chars() {
        if ch == '\t' {
            let spaces = width - (col % width);
            for _ in 0..spaces {
                out.push(' ');
            }
            col += spaces;
        } else {
            out.push(ch);
            col += 1;
        }
    }
    out
}

fn priority_prop_re() -> &'static Regex {
    static RE: OnceLock<Regex> = OnceLock::new();
    RE.get_or_init(|| Regex::new(r"\[#([A-Z0-9]+)\]").unwrap())
}

struct ParsedHeadingComponents {
    level: usize,
    todo: Option<String>,
    props_todo: Option<String>,
    priority: Option<u8>,
    props_priority: String,
    raw_title: Option<String>,
    local_tags: Vec<String>,
}

fn parse_heading_components(
    line: &str,
    todo_keywords: &TodoKeywords,
) -> ParsedHeadingComponents {
    let stars = parse_headline_level(line).unwrap();
    let mut rest = line[stars..].trim_start_matches(' ');

    // Optional TODO keyword (`org-complex-heading-regexp` requires ASCII `' '` before it,
    // and after it either `' '`, trailing `[ \t]*$`, or `[ \t]+:tags:[ \t]*$`).
    let mut todo = None;
    let mut props_todo = None;
    if !rest.is_empty() {
        let mut best_kw: Option<&str> = None;
        for kw in &todo_keywords.all {
            if rest.starts_with(kw.as_str()) {
                let after = &rest[kw.len()..];
                if after_token_matches_complex(after)
                    && best_kw.map_or(true, |b| kw.len() > b.len())
                {
                    best_kw = Some(kw.as_str());
                }
            }
        }
        if let Some(kw) = best_kw {
            let after = &rest[kw.len()..];
            todo = Some(kw.to_string());
            // `org-todo-line-regexp` (used by `org-entry-properties` "TODO") does not have a
            // separate tags group, so it only matches if `after` starts with `' '` or is `[ \t]*$`.
            if after.is_empty()
                || after.starts_with(' ')
                || after.trim_matches([' ', '\t']).is_empty()
            {
                props_todo = Some(kw.to_string());
            }
            rest = after.trim_start_matches(' ');
        }
    }

    // Optional [#X] priority cookie (`org-complex-heading-regexp` requires single graphic char
    // and `' '` / `[ \t]*$` / `[ \t]+:tags:[ \t]*$` after it).
    let mut priority = None;
    let rbytes = rest.as_bytes();
    if rbytes.len() >= 4
        && rbytes[0] == b'['
        && rbytes[1] == b'#'
        && rbytes[3] == b']'
        && rbytes[2] != b'\n'
        && rbytes[2] != b'\r'
        && after_token_matches_complex(&rest[4..])
    {
        priority = Some(rbytes[2]);
        rest = rest[4..].trim_start_matches(' ');
    }

    // `org-entry-properties` extracts `"PRIORITY"` via `org-priority-regexp` (`\[#\([A-Z0-9]+\)\] ?`)
    // anywhere on the heading line, defaulting to `"B"`.
    let props_priority = priority_prop_re()
        .captures(line)
        .map(|c| c[1].to_string())
        .unwrap_or_else(|| "B".to_string());

    // Strip trailing whitespace, then optional :tag1:tag2:
    let trimmed_end = rest.trim_end_matches([' ', '\t']);
    let mut local_tags = Vec::new();
    let mut title_raw = trimmed_end;

    if trimmed_end.ends_with(':') {
        if let Some(ws_pos) = trimmed_end.rfind([' ', '\t']) {
            let tag_part = &trimmed_end[ws_pos + 1..];
            if is_valid_tag_group(tag_part) {
                for t in tag_part.split(':').filter(|s| !s.is_empty()) {
                    local_tags.push(t.to_string());
                }
                title_raw = trimmed_end[..ws_pos].trim_end_matches([' ', '\t']);
            }
        } else if is_valid_tag_group(trimmed_end) {
            for t in trimmed_end.split(':').filter(|s| !s.is_empty()) {
                local_tags.push(t.to_string());
            }
            title_raw = "";
        }
    }

    let raw_title = if title_raw.is_empty() {
        None
    } else {
        Some(title_raw.to_string())
    };

    ParsedHeadingComponents {
        level: stars,
        todo,
        props_todo,
        priority,
        props_priority,
        raw_title,
        local_tags,
    }
}

fn extract_node_properties_map(props_in_order: &[PropEntry]) -> HashMap<String, String> {
    let mut map: HashMap<String, String> = HashMap::new();
    let mut seen_base: HashSet<String> = HashSet::new();
    for entry in props_in_order {
        if let Some(base) = entry.key_upper.strip_suffix('+') {
            if !base.is_empty() {
                if let Some(existing) = map.get_mut(base) {
                    existing.push(' ');
                    existing.push_str(&entry.value);
                } else {
                    map.insert(base.to_string(), entry.value.clone());
                }
            }
        } else if seen_base.insert(entry.key_upper.clone()) {
            if let Some(existing) = map.get_mut(&entry.key_upper) {
                let mut combined = entry.value.clone();
                combined.push(' ');
                combined.push_str(existing);
                *existing = combined;
            } else {
                map.insert(entry.key_upper.clone(), entry.value.clone());
            }
        }
    }
    map
}

fn extract_category_parts(props_in_order: &[PropEntry]) -> (Option<String>, Vec<String>) {
    let mut base: Option<String> = None;
    let mut plus: Vec<String> = Vec::new();
    for entry in props_in_order {
        if entry.key_upper == "CATEGORY" {
            base = Some(entry.value.clone());
        } else if entry.key_upper == "CATEGORY+" {
            plus.push(entry.value.clone());
        }
    }
    (base, plus)
}

fn org_not_nil(val: Option<&str>) -> bool {
    match val {
        None => false,
        Some(s) => !s.eq_ignore_ascii_case("nil"),
    }
}

fn build_properties_alist(
    file_path: &str,
    default_category: &str,
    props_in_order: &[PropEntry],
    ts_ia: Option<&str>,
    ts_active: Option<&str>,
    active_ts_first: bool,
    scheduled_raw: Option<&str>,
    deadline_raw: Option<&str>,
    closed_raw: Option<&str>,
    blocked: bool,
    all_tags: &[String],
    local_tags: &[String],
    props_priority: &str,
    props_todo: Option<&str>,
    raw_item: Option<&str>,
) -> Option<String> {
    let mut out: Vec<(String, String)> = Vec::new();
    let prop_map = extract_node_properties_map(props_in_order);

    // Only prepend derived CATEGORY at index 0 when NOT explicitly present in the drawer;
    // when :CATEGORY: / :CATEGORY+: is in `:PROPERTIES:`, Emacs keeps it in drawer order.
    if !prop_map.contains_key("CATEGORY") {
        let cat = if default_category == "nil" {
            "???"
        } else {
            default_category
        };
        out.push(("CATEGORY".to_string(), cat.to_string()));
    }

    // Standard drawer properties in REVERSE file order (matching Emacs `push` onto `props`),
    // skipping `org-special-properties` (note: CATEGORY is NOT a special property).
    let is_special = |k: &str| {
        matches!(
            k,
            "TODO"
                | "PRIORITY"
                | "ITEM"
                | "FILE"
                | "TAGS"
                | "ALLTAGS"
                | "BLOCKED"
                | "SCHEDULED"
                | "DEADLINE"
                | "CLOSED"
                | "TIMESTAMP"
                | "TIMESTAMP_IA"
        )
    };

    // Merge KEY+ into first base occurrence, preserve reverse order of base keys.
    let mut seen_base = HashSet::new();
    let mut drawer_ordered: Vec<(String, String)> = Vec::new();
    for entry in props_in_order {
        let base = entry.key_upper.strip_suffix('+').unwrap_or(&entry.key_upper);
        if is_special(base) {
            continue;
        }
        if seen_base.insert(base.to_string()) {
            if let Some(val) = prop_map.get(base) {
                drawer_ordered.push((base.to_string(), val.clone()));
            }
        }
    }
    drawer_ordered.reverse();
    out.extend(drawer_ordered);

    // In `org-entry-properties`, `find-ts` pushes the first-found timestamp first, then
    // the second-found timestamp on top of `ts`, so the second-found appears first in `props`.
    if active_ts_first {
        if let Some(t) = ts_ia {
            out.push(("TIMESTAMP_IA".to_string(), t.to_string()));
        }
        if let Some(t) = ts_active {
            out.push(("TIMESTAMP".to_string(), t.to_string()));
        }
    } else {
        if let Some(t) = ts_active {
            out.push(("TIMESTAMP".to_string(), t.to_string()));
        }
        if let Some(t) = ts_ia {
            out.push(("TIMESTAMP_IA".to_string(), t.to_string()));
        }
    }
    if let Some(s) = scheduled_raw {
        out.push(("SCHEDULED".to_string(), s.to_string()));
    }
    if let Some(d) = deadline_raw {
        out.push(("DEADLINE".to_string(), d.to_string()));
    }
    if let Some(c) = closed_raw {
        out.push(("CLOSED".to_string(), c.to_string()));
    }
    out.push((
        "BLOCKED".to_string(),
        if blocked { "t".to_string() } else { String::new() },
    ));
    if !all_tags.is_empty() {
        out.push((
            "ALLTAGS".to_string(),
            format!(":{}:", all_tags.join(":")),
        ));
    }
    if !local_tags.is_empty() {
        out.push((
            "TAGS".to_string(),
            format!(":{}:", local_tags.join(":")),
        ));
    }
    out.push(("FILE".to_string(), file_path.to_string()));
    out.push(("PRIORITY".to_string(), props_priority.to_string()));
    if let Some(td) = props_todo {
        out.push(("TODO".to_string(), td.to_string()));
    }
    if let Some(item) = raw_item {
        out.push(("ITEM".to_string(), org_remove_tabs(item)));
    }

    format_alist(&out)
}

fn parse_refs_for_node(node_id: &str, raw_refs: &str, out: &mut Vec<(String, String, String)>) {
    let tokens = split_string_and_unquote(raw_refs);
    let mut rows: Vec<(String, String, String)> = Vec::new();

    for token in tokens {
        if let Some(rest) = token.strip_prefix('@') {
            rows.push((node_id.to_string(), rest.to_string(), "cite".to_string()));
        } else if token.starts_with("[cite:") {
            let verbatim_ranges = find_verbatim_ranges(&token, 0);
            let mut matched = Vec::new();
            collect_all_links_in_slice(&token, 0, &mut matched);
            let mut bracket_link_ranges: Vec<(usize, usize)> = Vec::new();
            for ml in &matched {
                if let MatchedLink::Bracket {
                    start,
                    end,
                    raw_desc,
                    ..
                } = *ml
                {
                    if end > start {
                        if raw_desc.map_or(false, |d| d.starts_with(']')) {
                            if let Some(inner) = resolve_inner_bracket_at_end(&token, start, end) {
                                if !is_in_ranges(inner.start(), &verbatim_ranges) {
                                    bracket_link_ranges.push((inner.start(), inner.end()));
                                }
                            }
                        } else if !is_in_ranges(start, &verbatim_ranges) {
                            bracket_link_ranges.push((start, end));
                        }
                    }
                }
            }
            visit_citations_in_chunk(
                &token,
                0,
                &verbatim_ranges,
                &bracket_link_ranges,
                None,
                |_ref_abs, key| {
                    rows.push((node_id.to_string(), key.to_string(), "cite".to_string()));
                },
            );
        } else {
            let encoded = token.replace(' ', "%20");
            if let Some((_start, _end, bracket_target, matched_full)) =
                find_first_link_in_str(&encoded)
            {
                let url_str = bracket_target.unwrap_or(matched_full);
                if let Some(colon) = url_str.find(':') {
                    let scheme = &url_str[..colon];
                    if !scheme.is_empty()
                        && scheme
                            .chars()
                            .all(|c| c.is_ascii_alphanumeric() || matches!(c, '+' | '-' | '.'))
                    {
                        let rest_url = &url_str[colon + 1..];
                        let decoded = org_link_decode(rest_url);
                        rows.push((
                            node_id.to_string(),
                            decoded,
                            scheme.to_ascii_lowercase(),
                        ));
                    }
                }
            }
        }
    }

    // Elisp uses `(push ... rows)` in dolist, reversing order of refs.
    rows.reverse();
    out.extend(rows);
}

fn org_link_decode(s: &str) -> String {
    let bytes = s.as_bytes();
    let mut raw = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'%' && i + 2 < bytes.len() {
            if let (Some(h), Some(l)) = (hex_val(bytes[i + 1]), hex_val(bytes[i + 2])) {
                raw.push((h << 4) | l);
                i += 3;
                continue;
            }
        }
        raw.push(bytes[i]);
        i += 1;
    }
    String::from_utf8_lossy(&raw).into_owned()
}

#[inline]
fn hex_val(b: u8) -> Option<u8> {
    match b {
        b'0'..=b'9' => Some(b - b'0'),
        b'a'..=b'f' => Some(b - b'a' + 10),
        b'A'..=b'F' => Some(b - b'A' + 10),
        _ => None,
    }
}

/// Match `org-link-plain-re` starting at `start` (where `start` is the start of `proto:`).
fn match_plain_link_at(text: &str, start: usize) -> Option<(usize, &str, &str)> {
    // Check `\<` word boundary (Emacs triggers boundary between CJK and Latin scripts too)
    if start > 0 {
        if let Some(prev) = text[..start].chars().next_back() {
            if is_org_word_char(prev) && (prev as u32) < 0x2E80 {
                return None;
            }
        }
    }

    let rest = &text[start..];
    let rbytes = rest.as_bytes();
    let matched_proto = KNOWN_PROTOCOLS.iter().find(|&&p| {
        rbytes.len() > p.len()
            && rbytes[..p.len()].eq_ignore_ascii_case(p.as_bytes())
            && rbytes[p.len()] == b':'
    })?;

    let proto = &rest[..matched_proto.len()];
    let path_start = start + proto.len() + 1;
    let path_str = &text[path_start..];

    // Parse greedy `segment` sequence where each segment is either:
    // - single char not in `][ \t\n()<>`
    // - balanced `(...)`, `<...>`, or `[...]` with at most 1 nested balanced level
    let mut segments: Vec<(usize, bool)> = Vec::new(); // (byte_end_rel, is_balanced_group)
    let mut i = 0usize;
    let pbytes = path_str.as_bytes();

    while i < pbytes.len() {
        let ch = path_str[i..].chars().next().unwrap();
        match ch {
            '(' | '<' | '[' => {
                if let Some(end_rel) = match_balanced_group(&path_str[i..], ch, 1) {
                    i += end_rel;
                    segments.push((i, true));
                } else {
                    break;
                }
            }
            ')' | '>' | ']' | ' ' | '\t' | '\n' => break,
            _ => {
                i += ch.len_utf8();
                segments.push((i, false));
            }
        }
    }

    // Backtrack from longest match to find last segment valid as final token
    // AND requiring at least one preceding segment (so `id:a` fails, `id:ab` succeeds).
    for idx in (1..segments.len()).rev() {
        let (end_rel, is_bal) = segments[idx];
        if is_bal {
            return Some((
                path_start + end_rel,
                proto,
                &path_str[..end_rel],
            ));
        }
        let seg_start = segments[idx - 1].0;
        let last_ch = path_str[seg_start..end_rel].chars().next().unwrap();
        if last_ch == '/' || (!is_emacs_punct(last_ch) && !last_ch.is_whitespace()) {
            return Some((
                path_start + end_rel,
                proto,
                &path_str[..end_rel],
            ));
        }
    }

    None
}

fn match_balanced_group(s: &str, open: char, max_depth: usize) -> Option<usize> {
    let close = match open {
        '(' => ')',
        '<' => '>',
        '[' => ']',
        _ => return None,
    };
    let mut i = open.len_utf8();
    while i < s.len() {
        let ch = s[i..].chars().next().unwrap();
        if ch == close {
            return Some(i + ch.len_utf8());
        }
        if matches!(ch, ' ' | '\t' | '\n' | ')' | '>' | ']') {
            return None;
        }
        if matches!(ch, '(' | '<' | '[') {
            if max_depth == 0 {
                return None;
            }
            let inner_len = match_balanced_group(&s[i..], ch, max_depth - 1)?;
            i += inner_len;
            continue;
        }
        i += ch.len_utf8();
    }
    None
}

fn proto_prefix_re() -> &'static Regex {
    static RE: OnceLock<Regex> = OnceLock::new();
    RE.get_or_init(|| {
        Regex::new(r"(?i)(?:attachment|elisp|file\+emacs|file\+sys|file|ftp|help|https|http|id|mailto|news|roam|shell):").unwrap()
    })
}

fn find_first_link_in_str(s: &str) -> Option<(usize, usize, Option<&str>, &str)> {
    let b_m = bracket_re().captures(s);
    let a_m = angle_re().captures(s);

    let mut best_start = usize::MAX;
    let mut best: Option<(usize, usize, Option<&str>, &str)> = None;

    if let Some(caps) = b_m {
        let m0 = caps.get(0).unwrap();
        best_start = m0.start();
        best = Some((
            m0.start(),
            m0.end(),
            Some(caps.get(1).unwrap().as_str()),
            m0.as_str(),
        ));
    }
    if let Some(caps) = a_m {
        let m0 = caps.get(0).unwrap();
        if m0.start() < best_start {
            best_start = m0.start();
            best = Some((m0.start(), m0.end(), None, m0.as_str()));
        }
    }
    for m in proto_prefix_re().find_iter(s) {
        if m.start() >= best_start {
            break;
        }
        if let Some((end, _proto, _path)) = match_plain_link_at(s, m.start()) {
            best = Some((m.start(), end, None, &s[m.start()..end]));
            break;
        }
    }
    best
}

#[derive(Debug)]
enum MatchedLink<'a> {
    Bracket {
        start: usize,
        end: usize,
        raw_target: &'a str,
        raw_desc: Option<&'a str>,
    },
    Angle {
        start: usize,
        end: usize,
        proto: &'a str,
        raw_path: &'a str,
    },
    Plain {
        start: usize,
        end: usize,
        proto: &'a str,
        raw_path: &'a str,
    },
}

impl<'a> MatchedLink<'a> {
    fn start(&self) -> usize {
        match *self {
            MatchedLink::Bracket { start, .. }
            | MatchedLink::Angle { start, .. }
            | MatchedLink::Plain { start, .. } => start,
        }
    }

    fn end(&self) -> usize {
        match *self {
            MatchedLink::Bracket { end, .. }
            | MatchedLink::Angle { end, .. }
            | MatchedLink::Plain { end, .. } => end,
        }
    }

    fn parse_type_and_path(&self) -> Option<(String, String)> {
        match *self {
            MatchedLink::Bracket { raw_target, .. } => {
                // Replace `[ \t]*\n[ \t]*` with `" "`
                static NL_WS: OnceLock<Regex> = OnceLock::new();
                let nl_ws = NL_WS.get_or_init(|| Regex::new(r"[ \t]*\n[ \t]*").unwrap());
                let collapsed = nl_ws.replace_all(raw_target, " ");
                let link = org_link_unescape(&collapsed);

                let (mut ltype, mut path, had_file_scheme) = if link.starts_with('/')
                    || link.starts_with("~/")
                    || link.starts_with("./")
                    || link.starts_with("../")
                {
                    ("file".to_string(), link, false)
                } else if let Some((proto, rest)) = split_known_proto_prefix(&link) {
                    let hf = proto.eq_ignore_ascii_case("file")
                        || proto.eq_ignore_ascii_case("file+sys")
                        || proto.eq_ignore_ascii_case("file+emacs");
                    (proto.to_string(), rest.to_string(), hf)
                } else if link.starts_with('(') && link.ends_with(')') && link.len() > 2 {
                    ("coderef".to_string(), link[1..link.len() - 1].to_string(), false)
                } else if let Some(cid) = link.strip_prefix('#') {
                    ("custom-id".to_string(), cid.to_string(), false)
                } else {
                    ("fuzzy".to_string(), link, false)
                };

                normalize_file_link(&mut ltype, &mut path, had_file_scheme);
                Some((ltype, path))
            }
            MatchedLink::Angle {
                proto, raw_path, ..
            } => {
                static ANGLE_NL: OnceLock<Regex> = OnceLock::new();
                let angle_nl = ANGLE_NL.get_or_init(|| Regex::new(r"\n[ \t]*").unwrap());
                let collapsed = angle_nl.replace_all(raw_path, "").into_owned();
                let mut ltype = proto.to_string();
                let mut path = collapsed;
                let hf = proto.eq_ignore_ascii_case("file")
                    || proto.eq_ignore_ascii_case("file+sys")
                    || proto.eq_ignore_ascii_case("file+emacs");
                normalize_file_link(&mut ltype, &mut path, hf);
                Some((ltype, path))
            }
            MatchedLink::Plain {
                proto, raw_path, ..
            } => {
                let mut ltype = proto.to_string();
                let mut path = raw_path.to_string();
                let hf = proto.eq_ignore_ascii_case("file")
                    || proto.eq_ignore_ascii_case("file+sys")
                    || proto.eq_ignore_ascii_case("file+emacs");
                normalize_file_link(&mut ltype, &mut path, hf);
                Some((ltype, path))
            }
        }
    }
}

fn split_known_proto_prefix(link: &str) -> Option<(&str, &str)> {
    let lbytes = link.as_bytes();
    for &p in KNOWN_PROTOCOLS {
        if lbytes.len() > p.len()
            && lbytes[..p.len()].eq_ignore_ascii_case(p.as_bytes())
            && lbytes[p.len()] == b':'
        {
            return Some((&link[..p.len()], &link[p.len() + 1..]));
        }
    }
    None
}

fn normalize_file_link(ltype: &mut String, path: &mut String, had_file_scheme: bool) {
    if ltype == "file" || ltype == "file+sys" || ltype == "file+emacs" {
        *ltype = "file".to_string();
        if let Some(idx) = path.find("::") {
            path.truncate(idx);
        }
        if had_file_scheme {
            while path.starts_with("//") {
                path.remove(0);
            }
        }
    }
}

fn collect_all_links_in_slice<'a>(
    slice: &'a str,
    base_offset: usize,
    out: &mut Vec<MatchedLink<'a>>,
) {
    let mut b_iter = bracket_re().captures_iter(slice).peekable();
    let mut a_iter = angle_re().captures_iter(slice).peekable();
    let mut p_iter = proto_prefix_re().find_iter(slice).peekable();

    let mut cursor = 0usize;
    loop {
        while let Some(c) = b_iter.peek() {
            if c.get(0).unwrap().start() < cursor {
                b_iter.next();
            } else {
                break;
            }
        }
        while let Some(c) = a_iter.peek() {
            if c.get(0).unwrap().start() < cursor {
                a_iter.next();
            } else {
                break;
            }
        }
        while let Some(m) = p_iter.peek() {
            if m.start() < cursor {
                p_iter.next();
            } else {
                break;
            }
        }

        let b_pos = b_iter
            .peek()
            .map(|c| c.get(0).unwrap().start())
            .unwrap_or(usize::MAX);
        let a_pos = a_iter
            .peek()
            .map(|c| c.get(0).unwrap().start())
            .unwrap_or(usize::MAX);
        let p_pos = p_iter.peek().map(|m| m.start()).unwrap_or(usize::MAX);

        let min_pos = b_pos.min(a_pos).min(p_pos);
        if min_pos == usize::MAX {
            break;
        }

        if b_pos == min_pos {
            let caps = b_iter.next().unwrap();
            let m0 = caps.get(0).unwrap();
            let target = caps.get(1).unwrap().as_str();
            let desc = caps.get(2).map(|m| m.as_str());
            cursor = m0.end();
            out.push(MatchedLink::Bracket {
                start: base_offset + m0.start(),
                end: base_offset + m0.end(),
                raw_target: target,
                raw_desc: desc,
            });
        } else if a_pos == min_pos {
            let caps = a_iter.next().unwrap();
            let m0 = caps.get(0).unwrap();
            let proto = caps.get(1).unwrap().as_str();
            let raw_path = caps.get(2).unwrap().as_str();
            cursor = m0.end();
            out.push(MatchedLink::Angle {
                start: base_offset + m0.start(),
                end: base_offset + m0.end(),
                proto,
                raw_path,
            });
        } else {
            let m = p_iter.next().unwrap();
            if let Some((end, proto, raw_path)) = match_plain_link_at(slice, m.start()) {
                cursor = end;
                out.push(MatchedLink::Plain {
                    start: base_offset + m.start(),
                    end: base_offset + end,
                    proto,
                    raw_path,
                });
            } else {
                cursor = m.start() + 1;
            }
        }
    }
}

/// Find `(start, end)` byte ranges of `=verbatim=` and `~code~` objects inside
/// a single Org text container (paragraph, headline, table cell, list item) using
/// `org-element-verbatim-parser` rules (no 1-newline cap within a container).
fn find_verbatim_ranges(text: &str, base_offset: usize) -> Vec<(usize, usize)> {
    let mut ranges = Vec::new();
    let bytes = text.as_bytes();
    let mut i = 0usize;

    let is_pre = |c: char| {
        c.is_whitespace() || matches!(c, '-' | '(' | '\'' | '"' | '{')
    };
    let is_post = |c: char| {
        c.is_whitespace()
            || matches!(
                c,
                '-' | '.' | ',' | ':' | '!' | '?' | ';' | '\'' | '"' | ')' | '}' | '['
            )
    };

    while i < bytes.len() {
        let b = bytes[i];
        if b == b'=' || b == b'~' {
            let valid_pre = if i == 0 {
                true
            } else {
                text[..i].chars().next_back().map_or(false, is_pre)
            };
            if valid_pre && i + 1 < bytes.len() {
                let next_ch = text[i + 1..].chars().next().unwrap();
                if !next_ch.is_whitespace() {
                    let mut j = i + 1;
                    let mut found_end: Option<usize> = None;
                    while j < bytes.len() {
                        if bytes[j] == b && j > i + 1 {
                            let prev_ch = text[..j].chars().next_back().unwrap();
                            if !prev_ch.is_whitespace() {
                                let valid_post = if j + 1 >= bytes.len() {
                                    true
                                } else {
                                    text[j + 1..].chars().next().map_or(false, is_post)
                                };
                                if valid_post {
                                    found_end = Some(j + 1);
                                    break;
                                }
                            }
                        }
                        let ch = text[j..].chars().next().unwrap();
                        j += ch.len_utf8();
                    }
                    if let Some(end) = found_end {
                        ranges.push((base_offset + i, base_offset + end));
                        i = end;
                        continue;
                    }
                }
            }
        }
        let ch = text[i..].chars().next().unwrap();
        i += ch.len_utf8();
    }

    ranges
}

fn is_list_item_start(line: &str) -> bool {
    let trimmed = line.trim_start_matches([' ', '\t']);
    let bytes = trimmed.as_bytes();
    if bytes.is_empty() {
        return false;
    }
    if matches!(bytes[0], b'-' | b'+' | b'*') {
        return bytes.len() == 1 || matches!(bytes[1], b' ' | b'\t');
    }
    let mut i = 0;
    while i < bytes.len() && bytes[i].is_ascii_digit() {
        i += 1;
    }
    if i > 0 && i < bytes.len() && matches!(bytes[i], b'.' | b')') {
        return i + 1 == bytes.len() || matches!(bytes[i + 1], b' ' | b'\t');
    }
    false
}

fn is_table_row(line: &str) -> bool {
    line.trim_start_matches([' ', '\t']).starts_with('|')
}

/// Split a contiguous slice of `Headline`/`Normal` lines `[run_start..run_end)` into
/// `(abs_byte_start, abs_byte_end)` Org text containers (separating headings, blank lines,
/// list items, and table cells) for `=verbatim=`/`~code~` and cross-container link resolution.
fn compute_text_containers(
    idx: &LineIndex,
    kinds: &[LineKind],
    run_start: usize,
    run_end: usize,
) -> Vec<(usize, usize)> {
    let mut containers: Vec<(usize, usize)> = Vec::new();
    let mut cur_start: Option<usize> = None;
    let mut cur_end: usize = 0;

    let flush = |containers: &mut Vec<(usize, usize)>, cur_start: &mut Option<usize>, cur_end: usize| {
        if let Some(s) = cur_start.take() {
            if cur_end > s {
                containers.push((s, cur_end));
            }
        }
    };

    for li in run_start..run_end {
        let line = idx.line_str(li);
        let lstart = idx.lines[li].byte_start;
        let lend = idx.lines[li].byte_end;

        if matches!(kinds[li], LineKind::Headline(_) | LineKind::BlockBoundary) {
            flush(&mut containers, &mut cur_start, cur_end);
            if matches!(kinds[li], LineKind::Headline(_)) && lend > lstart {
                containers.push((lstart, lend));
            }
            continue;
        }
        if line.trim_matches([' ', '\t']).is_empty() {
            flush(&mut containers, &mut cur_start, cur_end);
            continue;
        }
        if is_table_row(line) {
            flush(&mut containers, &mut cur_start, cur_end);
            // Split table row into per-cell ranges between '|' delimiters
            let bytes = line.as_bytes();
            let mut cell_start = 0usize;
            for (bi, &b) in bytes.iter().enumerate() {
                if b == b'|' {
                    if bi > cell_start {
                        containers.push((lstart + cell_start, lstart + bi));
                    }
                    cell_start = bi + 1;
                }
            }
            if bytes.len() > cell_start {
                containers.push((lstart + cell_start, lend));
            }
            continue;
        }
        if is_list_item_start(line) {
            flush(&mut containers, &mut cur_start, cur_end);
            cur_start = Some(lstart);
            cur_end = lend;
            continue;
        }
        if cur_start.is_none() {
            cur_start = Some(lstart);
        }
        cur_end = lend;
    }
    flush(&mut containers, &mut cur_start, cur_end);
    containers
}

fn container_idx_for_byte(containers: &[(usize, usize)], byte_idx: usize) -> Option<usize> {
    let idx = containers.partition_point(|&(s, _)| s <= byte_idx);
    if idx == 0 {
        None
    } else {
        let (s, e) = containers[idx - 1];
        if byte_idx >= s && byte_idx < e {
            Some(idx - 1)
        } else {
            None
        }
    }
}

/// If `[[target1][]]...[[target2][desc2]]` spanned across containers, resolve the valid
/// bracket link ending at `abs_end` (if any, matching Emacs `(backward-char)` + `(org-element-context)`).
fn resolve_inner_bracket_at_end<'a>(
    text: &'a str,
    container_start: usize,
    abs_end: usize,
) -> Option<MatchedLink<'a>> {
    let mut pos = container_start;
    while pos < abs_end {
        let slice = &text[pos..abs_end];
        let caps = bracket_re().captures(slice)?;
        let m0 = caps.get(0).unwrap();
        let m_start = pos + m0.start();
        let m_end = pos + m0.end();
        if m_end == abs_end {
            let desc = caps.get(2).map(|m| m.as_str());
            if desc.map_or(false, |d| d.starts_with(']')) {
                // `[[x][]]` itself is invalid; advance past its `][` + `]` and check inside
                pos += caps.get(2).unwrap().start() + 1;
                continue;
            }
            return Some(MatchedLink::Bracket {
                start: m_start,
                end: abs_end,
                raw_target: caps.get(1).unwrap().as_str(),
                raw_desc: desc,
            });
        }
        pos = m_end;
    }
    None
}

fn find_range_containing(pos: usize, ranges: &[(usize, usize)]) -> Option<(usize, usize)> {
    let idx = ranges.partition_point(|&(s, _)| s <= pos);
    if idx == 0 {
        None
    } else {
        let (s, e) = ranges[idx - 1];
        if pos >= s && pos < e {
            Some((s, e))
        } else {
            None
        }
    }
}

fn is_in_ranges(pos: usize, ranges: &[(usize, usize)]) -> bool {
    find_range_containing(pos, ranges).is_some()
}

fn is_strictly_inside_any_range(pos: usize, ranges: &[(usize, usize)]) -> bool {
    // `ranges` are sorted by `start` and non-overlapping
    let idx = ranges.partition_point(|&(s, _)| s < pos);
    if idx == 0 {
        false
    } else {
        let (s, e) = ranges[idx - 1];
        pos > s && pos < e
    }
}

/// Extract only `org-id-locations` IDs (`node-property` `:ID:` outside opaque blocks),
/// matching `org-id-update-id-locations` (`org-id.el:550-589`).
fn is_dos_eol(text: &str) -> bool {
    let bytes = text.as_bytes();
    let mut saw_crlf = false;
    for (i, &b) in bytes.iter().enumerate() {
        if b == b'\n' {
            if i > 0 && bytes[i - 1] == b'\r' {
                saw_crlf = true;
            } else {
                return false;
            }
        }
    }
    saw_crlf
}

fn normalize_dos_eol(text: &str) -> Cow<'_, str> {
    if is_dos_eol(text) {
        Cow::Owned(text.replace("\r\n", "\n"))
    } else {
        Cow::Borrowed(text)
    }
}

pub fn extract_org_ids_only(text: &str) -> Vec<String> {
    let normalized = normalize_dos_eol(text);
    let idx = LineIndex::new(&normalized);
    let n = idx.lines.len();
    let kinds = classify_lines(&idx);
    let mut ids = Vec::new();
    for i in 0..n {
        if kinds[i] == LineKind::NodeProperty {
            if let Some((k, v)) = parse_node_property_line(idx.line_str(i)) {
                if k.eq_ignore_ascii_case("ID") && !v.is_empty() {
                    ids.push(v);
                }
            }
        }
    }
    ids
}

fn classify_lines(idx: &LineIndex) -> Vec<LineKind> {
    let n = idx.lines.len();
    let mut kinds = vec![LineKind::Normal; n];

    // Step 1: Identify headlines and opaque/greater blocks & latex environments
    let mut i = 0;
    while i < n {
        let line = idx.line_str(i);
        if let Some(lvl) = parse_headline_level(line) {
            kinds[i] = LineKind::Headline(lvl);
            i += 1;
            continue;
        }
        if let Some(bname) = parse_begin_block(line) {
            // Find matching #+end_<bname> before any headline
            let mut end_line = None;
            let mut j = i + 1;
            while j < n {
                let jl = idx.line_str(j);
                if parse_headline_level(jl).is_some() {
                    break;
                }
                if is_end_block(jl, &bname) {
                    end_line = Some(j);
                    break;
                }
                j += 1;
            }
            if let Some(el) = end_line {
                if is_opaque_block_name(&bname) {
                    for k in i..=el {
                        kinds[k] = LineKind::OpaqueBlock;
                    }
                    i = el + 1;
                    continue;
                } else {
                    let _ = is_greater_block_name(&bname);
                    kinds[i] = LineKind::BlockBoundary;
                    kinds[el] = LineKind::BlockBoundary;
                    i += 1;
                    continue;
                }
            }
        }
        if let Some(env) = parse_latex_begin(line) {
            let mut end_line = None;
            let mut j = i + 1;
            while j < n {
                let jl = idx.line_str(j);
                if parse_headline_level(jl).is_some() {
                    break;
                }
                if is_latex_end(jl, &env) {
                    end_line = Some(j);
                    break;
                }
                j += 1;
            }
            if let Some(el) = end_line {
                for k in i..=el {
                    kinds[k] = LineKind::OpaqueBlock;
                }
                i = el + 1;
                continue;
            }
        }
        i += 1;
    }

    // Step 2: Classify drawers, planning lines, keywords, comments, fixed-width
    let mut i = 0;
    let mut allow_planning = false;
    let mut allow_props = true; // true at file top or immediately after Headline / 1 Planning line
    while i < n {
        if kinds[i] == LineKind::OpaqueBlock || kinds[i] == LineKind::BlockBoundary {
            allow_planning = false;
            allow_props = false;
            i += 1;
            continue;
        }
        if let LineKind::Headline(_) = kinds[i] {
            allow_planning = true;
            allow_props = true;
            i += 1;
            continue;
        }

        let line = idx.line_str(i);

        // Planning line: at most ONE line immediately after heading
        if allow_planning && is_planning_line(line) {
            kinds[i] = LineKind::Planning;
            allow_planning = false;
            i += 1;
            continue;
        }

        // Check drawer opening
        if let Some(dname) = parse_drawer_open(line) {
            let mut end_line = None;
            let mut j = i + 1;
            while j < n {
                if matches!(kinds[j], LineKind::Headline(_) | LineKind::OpaqueBlock) {
                    break;
                }
                if is_drawer_end(idx.line_str(j)) {
                    end_line = Some(j);
                    break;
                }
                j += 1;
            }
            if let Some(el) = end_line {
                let is_props = dname.eq_ignore_ascii_case("PROPERTIES");
                if is_props {
                    let valid_pos = if allow_props {
                        true
                    } else {
                        (0..i).all(|prev| {
                            matches!(kinds[prev], LineKind::CommentLine | LineKind::Normal)
                                && (kinds[prev] == LineKind::CommentLine
                                    || idx.line_str(prev).trim().is_empty())
                        })
                    };
                    if valid_pos {
                        kinds[i] = LineKind::PropertyDrawerBound;
                        kinds[el] = LineKind::PropertyDrawerBound;
                        for k in (i + 1)..el {
                            if parse_node_property_line(idx.line_str(k)).is_some() {
                                kinds[k] = LineKind::NodeProperty;
                            }
                        }
                        allow_planning = false;
                        allow_props = false;
                        i = el + 1;
                        continue;
                    }
                }
                // General drawer (e.g. :LOGBOOK:)
                kinds[i] = LineKind::OtherDrawerBound;
                kinds[el] = LineKind::OtherDrawerBound;
                allow_planning = false;
                allow_props = false;
                i = el + 1;
                continue;
            }
        }

        if is_comment_line(line) {
            kinds[i] = LineKind::CommentLine;
            allow_planning = false;
            i += 1;
            continue;
        }

        if parse_keyword_line(line).is_some() {
            kinds[i] = LineKind::Keyword;
            allow_planning = false;
            allow_props = false;
            i += 1;
            continue;
        }

        if is_fixed_width_line(line) {
            kinds[i] = LineKind::FixedWidth;
            allow_planning = false;
            allow_props = false;
            i += 1;
            continue;
        }

        // Normal line (may be blank)
        allow_planning = false;
        allow_props = false;
        i += 1;
    }

    kinds
}

fn dedup_keep_last(items: &[String]) -> Vec<String> {
    let mut seen: HashSet<&str> = HashSet::new();
    let mut rev: Vec<String> = Vec::with_capacity(items.len());
    for item in items.iter().rev() {
        if seen.insert(item.as_str()) {
            rev.push(item.clone());
        }
    }
    rev.reverse();
    rev
}

pub fn parse_org_file(file_path: &str, text: &str) -> ParsedOrgData {
    let normalized = normalize_dos_eol(text);
    let text = normalized.as_ref();
    let idx = LineIndex::new(text);
    let n = idx.lines.len();
    let kinds = classify_lines(&idx);

    let default_category = Path::new(file_path)
        .file_stem()
        .map(|s| s.to_string_lossy().into_owned())
        .unwrap_or_default();

    // 1. Collect file-wide keywords: #+TITLE:, #+FILETAGS:, #+CATEGORY:, #+TODO:/SEQ_TODO:/TYP_TODO:
    let mut title_parts: Vec<String> = Vec::new();
    let mut file_tags_non_dedup: Vec<String> = Vec::new();
    let mut file_category: Option<String> = None;
    let mut todo_keywords = TodoKeywords {
        all: Vec::new(),
        active: HashSet::new(),
        done: HashSet::new(),
    };
    let mut has_custom_todo = false;

    for i in 0..n {
        if kinds[i] == LineKind::Keyword {
            if let Some((key, val)) = parse_keyword_line(idx.line_str(i)) {
                if key.eq_ignore_ascii_case("TITLE") {
                    if !val.is_empty() {
                        title_parts.push(val);
                    }
                } else if key.eq_ignore_ascii_case("FILETAGS") {
                    for tag in val.split(|c: char| c.is_whitespace() || c == ':') {
                        if !tag.is_empty() {
                            file_tags_non_dedup.push(tag.to_string());
                        }
                    }
                } else if key.eq_ignore_ascii_case("CATEGORY") {
                    file_category = Some(val);
                } else if key.eq_ignore_ascii_case("TODO")
                    || key.eq_ignore_ascii_case("SEQ_TODO")
                    || key.eq_ignore_ascii_case("TYP_TODO")
                {
                    has_custom_todo = true;
                    parse_todo_keywords_line(&val, &mut todo_keywords);
                }
            }
        }
    }
    if !has_custom_todo {
        todo_keywords = TodoKeywords::default_org();
    }

    let file_title = org_link_display_format(&title_parts.join(" "));
    let effective_file_category = file_category.unwrap_or_else(|| default_category.clone());

    // Deduplicated file tags for `org-get-tags` / `ALLTAGS` (keep last/most-local occurrence).
    let file_tags_dedup = dedup_keep_last(&file_tags_non_dedup);

    // 2. Collect org_ids (all `:ID:` inside LineKind::NodeProperty, for `org-id-locations`)
    let mut org_ids: Vec<String> = Vec::new();
    for i in 0..n {
        if kinds[i] == LineKind::NodeProperty {
            if let Some((k, v)) = parse_node_property_line(idx.line_str(i)) {
                if k.eq_ignore_ascii_case("ID") && !v.is_empty() {
                    org_ids.push(v);
                }
            }
        }
    }

    // 3. Find file-level :PROPERTIES: (only valid if line 0 or contiguous # comment lines precede it, NO blank lines!)
    let mut file_props: Vec<PropEntry> = Vec::new();
    let mut file_prop_start = None;
    for i in 0..n {
        if kinds[i] == LineKind::PropertyDrawerBound && parse_drawer_open(idx.line_str(i)).is_some() {
            file_prop_start = Some(i);
            break;
        }
        if kinds[i] != LineKind::CommentLine {
            break;
        }
    }
    if let Some(pstart) = file_prop_start {
        for i in (pstart + 1)..n {
            if kinds[i] == LineKind::PropertyDrawerBound {
                break;
            }
            if kinds[i] == LineKind::NodeProperty {
                if let Some((rk, val)) = parse_node_property_line(idx.line_str(i)) {
                    file_props.push(PropEntry {
                        key_upper: rk.to_ascii_uppercase(),
                        value: val,
                    });
                }
            }
        }
    }

    let first_heading_line = (0..n)
        .find(|&i| matches!(kinds[i], LineKind::Headline(_)))
        .unwrap_or(n);

    // Scan file-level TIMESTAMP / TIMESTAMP_IA before first heading
    let (file_ts_ia, file_ts_active, file_active_first) =
        scan_section_timestamps(&idx, &kinds, 0, first_heading_line);

    let file_prop_map = extract_node_properties_map(&file_props);
    let (file_cat_base, file_cat_plus) = extract_category_parts(&file_props);
    let file_node_id = file_prop_map.get("ID").cloned().filter(|s| !s.is_empty());
    let file_node_excluded = org_not_nil(file_prop_map.get("ROAM_EXCLUDE").map(|s| s.as_str()));
    let file_is_node = file_node_id.is_some() && !file_node_excluded;

    let mut nodes: Vec<ParsedNode> = Vec::new();
    let mut aliases: Vec<(String, String)> = Vec::new();
    let mut tags: Vec<(String, String)> = Vec::new();
    let mut refs: Vec<(String, String, String)> = Vec::new();

    if file_is_node {
        let nid = file_node_id.clone().unwrap();
        let props_str = build_properties_alist(
            file_path,
            &effective_file_category,
            &file_props,
            file_ts_ia.as_deref(),
            file_ts_active.as_deref(),
            file_active_first,
            None,
            None,
            None,
            false,
            &file_tags_dedup,
            &[],
            "B",
            None,
            None,
        );
        nodes.push(ParsedNode {
            id: nid.clone(),
            file: file_path.to_string(),
            level: 0,
            pos: 1,
            todo: None,
            priority: None,
            scheduled: None,
            deadline: None,
            title: file_title.clone(),
            properties: props_str,
            olp: None,
        });
        for t in &file_tags_non_dedup {
            tags.push((nid.clone(), t.clone()));
        }
        if let Some(al) = file_prop_map.get("ROAM_ALIASES") {
            for a in split_string_and_unquote(al) {
                aliases.push((nid.clone(), a));
            }
        }
        if let Some(rf) = file_prop_map.get("ROAM_REFS") {
            parse_refs_for_node(&nid, rf, &mut refs);
        }
    }

    // 4. Collect all headings
    let heading_lines: Vec<usize> = (0..n)
        .filter(|&i| matches!(kinds[i], LineKind::Headline(_)))
        .collect();

    let mut headings: Vec<HeadingMeta> = Vec::with_capacity(heading_lines.len());
    for (hi, &hline) in heading_lines.iter().enumerate() {
        let hend = heading_lines.get(hi + 1).copied().unwrap_or(n);
        let line = idx.line_str(hline);
        let hc = parse_heading_components(line, &todo_keywords);
        let level = hc.level;
        let display_title = hc.raw_title.as_deref().map(org_link_display_format);
        let olp_title = Some(
            display_title
                .as_deref()
                .map(strip_cookies_for_olp)
                .unwrap_or_default(),
        );
        let mut pos = idx.byte_to_char_pos(idx.lines[hline].byte_start);
        if hi == 0 {
            // `org-map-region` locates the first heading via `(re-search-forward org-outline-regexp)`
            // (`\*+ `), leaving `(point)` immediately after the stars and first space;
            // subsequent headings use `(outline-next-heading)` at line beginning.
            pos += (level as i64) + 1;
        }

        let mut scheduled_iso = None;
        let mut deadline_iso = None;
        let mut scheduled_raw = None;
        let mut deadline_raw = None;
        let mut closed_raw = None;
        let mut props_in_order = Vec::new();

        let mut j = hline + 1;
        while j < hend && kinds[j] == LineKind::Planning {
            parse_planning_fields(
                idx.line_str(j),
                &mut scheduled_iso,
                &mut deadline_iso,
                &mut scheduled_raw,
                &mut deadline_raw,
                &mut closed_raw,
            );
            j += 1;
        }
        if j < hend
            && kinds[j] == LineKind::PropertyDrawerBound
            && parse_drawer_open(idx.line_str(j)).is_some()
        {
            j += 1;
            while j < hend && kinds[j] != LineKind::PropertyDrawerBound {
                if kinds[j] == LineKind::NodeProperty {
                    if let Some((rk, val)) = parse_node_property_line(idx.line_str(j)) {
                        props_in_order.push(PropEntry {
                            key_upper: rk.to_ascii_uppercase(),
                            value: val,
                        });
                    }
                }
                j += 1;
            }
        }

        let prop_map = extract_node_properties_map(&props_in_order);
        let id = prop_map.get("ID").cloned().filter(|s| !s.is_empty());
        let roam_exclude = org_not_nil(prop_map.get("ROAM_EXCLUDE").map(|s| s.as_str()));

        headings.push(HeadingMeta {
            line_idx: hline,
            level,
            pos,
            todo: hc.todo,
            props_todo: hc.props_todo,
            priority: hc.priority,
            props_priority: hc.props_priority,
            raw_title: hc.raw_title,
            display_title,
            olp_title,
            local_tags: hc.local_tags,
            scheduled_iso,
            deadline_iso,
            scheduled_raw,
            deadline_raw,
            closed_raw,
            props_in_order,
            id,
            roam_exclude,
            // Under default `org-enforce-todo-dependencies = nil` (`org-blocker-hook = nil`),
            // `org-entry-blocked-p` always returns nil (`"BLOCKED" . ""`); `init-org-roam.el`
            // falls back to Elisp if `org-enforce-todo-dependencies` or `org-blocker-hook` is set.
            blocked: false,
        });
    }

    // Keep `done` keywords validated against `headings` (used by `todo_keywords` parsing);
    // `blocked` remains false when `org-enforce-todo-dependencies` is nil.
    let _ = (&todo_keywords.active, &todo_keywords.done);

    // Map each line -> enclosing heading index (if any)
    let mut line_to_heading: Vec<Option<usize>> = vec![None; n];
    for (hi, h) in headings.iter().enumerate() {
        let hend = heading_lines.get(hi + 1).copied().unwrap_or(n);
        for l in h.line_idx..hend {
            line_to_heading[l] = Some(hi);
        }
    }

    // Build parent index per heading using outline levels
    let mut parent_heading: Vec<Option<usize>> = vec![None; headings.len()];
    let mut stack: Vec<usize> = Vec::new();
    for hi in 0..headings.len() {
        while let Some(&top) = stack.last() {
            if headings[top].level < headings[hi].level {
                break;
            }
            stack.pop();
        }
        parent_heading[hi] = stack.last().copied();
        stack.push(hi);
    }

    // Helper: ancestor chain from root to `hi` (inclusive)
    let ancestor_chain = |mut cur: usize| -> Vec<usize> {
        let mut chain = Vec::new();
        loop {
            chain.push(cur);
            match parent_heading[cur] {
                Some(p) => cur = p,
                None => break,
            }
        }
        chain.reverse();
        chain
    };

    // Helper: inherited + local tags (`org-get-tags`: keep last / most-local occurrence)
    let compute_heading_tags = |hi: usize| -> Vec<String> {
        let chain = ancestor_chain(hi);
        let mut combined: Vec<String> = file_tags_dedup.clone();
        for &anc in &chain {
            combined.extend(headings[anc].local_tags.iter().cloned());
        }
        dedup_keep_last(&combined)
    };

    // Emit heading nodes
    for hi in 0..headings.len() {
        let h = &headings[hi];
        let Some(ref nid) = h.id else {
            continue;
        };
        if h.roam_exclude {
            continue;
        }
        let Some(ref title) = h.display_title else {
            // Skip heading without title, matching org-roam-db-insert-node-data
            continue;
        };

        let hend = heading_lines.get(hi + 1).copied().unwrap_or(n);
        let (ts_ia, ts_active, active_ts_first) =
            scan_section_timestamps(&idx, &kinds, h.line_idx, hend);

        let chain = ancestor_chain(hi);
        // `olp` excludes self (`chain[..chain.len()-1]`)
        let olp_vec: Vec<String> = chain[..chain.len().saturating_sub(1)]
            .iter()
            .filter_map(|&anc| headings[anc].olp_title.clone())
            .collect();
        let olp = format_string_list(&olp_vec);

        let all_tags = compute_heading_tags(hi);
        // Inherit category per `org-entry-get-with-inheritance "CATEGORY"`:
        // pure `:CATEGORY+:` entries append onto ancestor / `#+CATEGORY:` / file stem.
        let mut tail_plus: Vec<String> = Vec::new();
        let mut base_cat: Option<String> = None;
        for &anc in chain.iter().rev() {
            let (b, p) = extract_category_parts(&headings[anc].props_in_order);
            if !p.is_empty() {
                let mut combined = p;
                combined.append(&mut tail_plus);
                tail_plus = combined;
            }
            if let Some(b_val) = b {
                base_cat = Some(b_val);
                break;
            }
        }
        if base_cat.is_none() {
            if !file_cat_plus.is_empty() {
                let mut combined = file_cat_plus.clone();
                combined.append(&mut tail_plus);
                tail_plus = combined;
            }
            if let Some(ref b_val) = file_cat_base {
                base_cat = Some(b_val.clone());
            }
        }
        let eff_category = if let Some(b) = base_cat {
            if tail_plus.is_empty() {
                b
            } else {
                let mut all = Vec::with_capacity(1 + tail_plus.len());
                all.push(b);
                all.extend(tail_plus);
                all.join(" ")
            }
        } else if tail_plus.is_empty() {
            effective_file_category.clone()
        } else {
            let mut all = Vec::with_capacity(1 + tail_plus.len());
            all.push(effective_file_category.clone());
            all.extend(tail_plus);
            all.join(" ")
        };

        let props_str = build_properties_alist(
            file_path,
            &eff_category,
            &h.props_in_order,
            ts_ia.as_deref(),
            ts_active.as_deref(),
            active_ts_first,
            h.scheduled_raw.as_deref(),
            h.deadline_raw.as_deref(),
            h.closed_raw.as_deref(),
            h.blocked,
            &all_tags,
            &h.local_tags,
            &h.props_priority,
            h.props_todo.as_deref(),
            h.raw_title.as_deref(),
        );

        nodes.push(ParsedNode {
            id: nid.clone(),
            file: file_path.to_string(),
            level: h.level as i64,
            pos: h.pos,
            todo: h.todo.clone(),
            priority: h.priority.map(|p| p as i64),
            scheduled: h.scheduled_iso.clone(),
            deadline: h.deadline_iso.clone(),
            title: title.clone(),
            properties: props_str,
            olp,
        });

        for t in &all_tags {
            tags.push((nid.clone(), t.clone()));
        }
        let pmap = extract_node_properties_map(&h.props_in_order);
        if let Some(al) = pmap.get("ROAM_ALIASES") {
            for a in split_string_and_unquote(al) {
                aliases.push((nid.clone(), a));
            }
        }
        if let Some(rf) = pmap.get("ROAM_REFS") {
            parse_refs_for_node(nid, rf, &mut refs);
        }
    }

    // Helper: `org-roam-id-at-point` for a given line index
    let roam_id_at_line = |line_idx: usize| -> Option<String> {
        if let Some(mut cur) = line_to_heading[line_idx] {
            loop {
                if let Some(ref id) = headings[cur].id {
                    if !headings[cur].roam_exclude {
                        if headings[cur].display_title.is_some() {
                            return Some(id.clone());
                        } else {
                            // Empty-title heading was skipped from `nodes`; do not emit
                            // links/citations referencing it (prevents FK abort).
                            return None;
                        }
                    }
                }
                match parent_heading[cur] {
                    Some(p) => cur = p,
                    None => break,
                }
            }
        }
        if file_is_node {
            file_node_id.clone()
        } else {
            None
        }
    };

    // Helper: `:outline` (`org-get-outline-path 'with-self`) for a given line index
    let outline_at_line = |line_idx: usize| -> Vec<String> {
        if let Some(cur) = line_to_heading[line_idx] {
            ancestor_chain(cur)
                .into_iter()
                .filter_map(|anc| headings[anc].olp_title.clone())
                .collect()
        } else {
            Vec::new()
        }
    };

    // 5. Scan Links & Citations
    let mut links: Vec<ParsedLink> = Vec::new();
    let mut citations: Vec<ParsedCitation> = Vec::new();

    // Compute Org text containers & verbatim/code ranges across all Normal/Headline runs
    let mut all_containers: Vec<(usize, usize)> = Vec::new();
    let mut all_verbatim_ranges: Vec<(usize, usize)> = Vec::new();
    {
        let mut i = 0;
        while i < n {
            if matches!(
                kinds[i],
                LineKind::Headline(_) | LineKind::Normal | LineKind::BlockBoundary
            ) {
                let run_start = i;
                while i < n
                    && matches!(
                        kinds[i],
                        LineKind::Headline(_) | LineKind::Normal | LineKind::BlockBoundary
                    )
                {
                    i += 1;
                }
                let containers = compute_text_containers(&idx, &kinds, run_start, i);
                for &(cs, ce) in &containers {
                    all_verbatim_ranges.extend(find_verbatim_ranges(&text[cs..ce], cs));
                }
                all_containers.extend(containers);
            } else {
                i += 1;
            }
        }
    }

    // Scan links across the entire file (matching `while (re-search-forward org-link-any-re)`),
    // then resolve `org-element-context` at `(backward-char)` (`end - 1`).
    let mut matched_all = Vec::new();
    collect_all_links_in_slice(text, 0, &mut matched_all);

    // Bracket link ranges (same-container, non-verbatim, non-empty-desc) prevent citations
    // inside `[[target][[cite:@key]]]` descriptions from being parsed as citations.
    let mut bracket_link_ranges: Vec<(usize, usize)> = Vec::new();
    for ml in &matched_all {
        if let MatchedLink::Bracket {
            start,
            end,
            raw_desc,
            ..
        } = *ml
        {
            if end > start {
                if raw_desc.map_or(false, |d| d.starts_with(']')) {
                    if let Some(ci) = container_idx_for_byte(&all_containers, end - 1) {
                        let bound = all_containers[ci].0.max(start);
                        if let Some(inner) = resolve_inner_bracket_at_end(text, bound, end) {
                            let istart = inner.start();
                            if !is_in_ranges(istart, &all_verbatim_ranges)
                                && container_idx_for_byte(&all_containers, istart) == Some(ci)
                            {
                                bracket_link_ranges.push((istart, inner.end()));
                            }
                        }
                    }
                } else if !is_in_ranges(start, &all_verbatim_ranges) {
                    let c_start = container_idx_for_byte(&all_containers, start);
                    let c_end = container_idx_for_byte(&all_containers, end - 1);
                    if c_start.is_some() && c_start == c_end {
                        bracket_link_ranges.push((start, end));
                    }
                }
            }
        }
    }

    // Scan citations per-container (matching `org-element` object parsing per paragraph/headline/cell)
    let mut all_citation_ranges: Vec<(usize, usize)> = Vec::new();
    for &(cs, ce) in &all_containers {
        scan_citations_in_chunk(
            &idx,
            &text[cs..ce],
            cs,
            &all_verbatim_ranges,
            &bracket_link_ranges,
            &roam_id_at_line,
            &outline_at_line,
            &mut citations,
            &mut all_citation_ranges,
        );
    }

    for ml in matched_all {
        let m_start = ml.start();
        let m_end = ml.end();
        if m_end == 0 {
            continue;
        }
        let end_line = line_idx_for_byte(&idx, m_end - 1);
        let start_line = line_idx_for_byte(&idx, m_start);

        let is_empty_desc_bridge = matches!(
            &ml,
            MatchedLink::Bracket {
                raw_desc: Some(desc),
                ..
            } if desc.starts_with(']')
        );

        let resolved = if is_empty_desc_bridge {
            let c_start = container_idx_for_byte(&all_containers, m_start);
            let c_end = container_idx_for_byte(&all_containers, m_end - 1);
            let cite_start_range = find_range_containing(m_start, &all_citation_ranges);
            let cite_end_range = find_range_containing(m_end - 1, &all_citation_ranges);
            let verb_start_range = find_range_containing(m_start, &all_verbatim_ranges);
            let verb_end_range = find_range_containing(m_end - 1, &all_verbatim_ranges);
            let bridged_out_of_verb =
                verb_start_range.is_some() && verb_start_range != verb_end_range;
            if c_start.is_some()
                && c_start == c_end
                && cite_start_range == cite_end_range
                && !bridged_out_of_verb
            {
                ml
            } else {
                // `[[url1][]]` bridged across containers/blocks/citations/verbatim to `m_end`.
                // `(backward-char) (org-element-context)` inspects `m_end - 1`!
                match kinds[end_line] {
                    LineKind::Normal | LineKind::Headline(_) => {
                        if let Some(ci) = c_end {
                            let mut bound = all_containers[ci].0;
                            if let Some((_, cite_end)) = cite_start_range {
                                bound = bound.max(cite_end);
                            }
                            if let Some((_, verb_end)) = verb_start_range {
                                bound = bound.max(verb_end);
                            }
                            match resolve_inner_bracket_at_end(text, bound, m_end) {
                                Some(inner) => inner,
                                None => continue,
                            }
                        } else {
                            continue;
                        }
                    }
                    LineKind::NodeProperty | LineKind::Keyword => {
                        let lstart = idx.lines[end_line].byte_start;
                        match resolve_inner_bracket_at_end(text, lstart, m_end) {
                            Some(inner) => inner,
                            None => continue,
                        }
                    }
                    _ => continue,
                }
            }
        } else {
            ml
        };

        let line_idx = line_idx_for_byte(&idx, resolved.start());
        match kinds[line_idx] {
            LineKind::NodeProperty => {
                if let Some((key, _)) = parse_node_property_line(idx.line_str(line_idx)) {
                    if key.eq_ignore_ascii_case("ROAM_REFS") {
                        continue;
                    }
                } else {
                    continue;
                }
            }
            LineKind::Keyword => {
                if let Some((key, _)) = parse_keyword_line(idx.line_str(line_idx)) {
                    if key.eq_ignore_ascii_case("TRANSCLUDE") {
                        continue;
                    }
                } else {
                    continue;
                }
            }
            LineKind::Normal | LineKind::Headline(_) => {
                // Check verbatim/code and citation suppression
                if is_in_ranges(resolved.start(), &all_verbatim_ranges)
                    || is_in_ranges(resolved.start(), &all_citation_ranges)
                {
                    continue;
                }
                // Check Org description-list greedy `.* :: ` tag separator on list item lines
                let line_str = idx.line_str(line_idx);
                if is_list_item_start(line_str) {
                    if let Some(sep_rel) = line_str.rfind(" :: ") {
                        let sep_abs = idx.lines[line_idx].byte_start + sep_rel;
                        if resolved.start() < sep_abs + 4 && resolved.end() > sep_abs {
                            continue;
                        }
                    }
                }
                // Also ensure multi-line match didn't end inside an OpaqueBlock/Comment/etc.
                let rend_line = line_idx_for_byte(&idx, resolved.end().saturating_sub(1));
                if !matches!(
                    kinds[rend_line],
                    LineKind::Normal | LineKind::Headline(_)
                ) {
                    continue;
                }
                let _ = start_line;
            }
            _ => continue,
        }

        if let Some((ltype, path)) = resolved.parse_type_and_path() {
            if let Some(source) = roam_id_at_line(line_idx) {
                let outline = outline_at_line(line_idx);
                emit_link(
                    &idx,
                    resolved.start(),
                    &source,
                    &ltype,
                    &path,
                    &outline,
                    &mut links,
                );
            }
        }
    }

    ParsedOrgData {
        file_title,
        nodes,
        aliases,
        tags,
        refs,
        citations,
        links,
        org_ids,
    }
}

fn line_idx_for_byte(idx: &LineIndex, byte_idx: usize) -> usize {
    idx.lines
        .partition_point(|l| l.byte_start <= byte_idx)
        .saturating_sub(1)
}

fn emit_link(
    idx: &LineIndex,
    byte_start: usize,
    source: &str,
    ltype: &str,
    path: &str,
    outline: &[String],
    out: &mut Vec<ParsedLink>,
) {
    let (dest, search_opt) = if let Some(cpos) = path.find("::") {
        (&path[..cpos], Some(&path[cpos + 2..]))
    } else {
        (path, None)
    };
    let props = format_link_properties(outline, search_opt);
    out.push(ParsedLink {
        pos: idx.byte_to_char_pos(byte_start),
        source: source.to_string(),
        dest: dest.to_string(),
        link_type: ltype.to_string(),
        properties: props,
    });
}

fn visit_citations_in_chunk<F>(
    chunk: &str,
    base_offset: usize,
    verbatim_ranges: &[(usize, usize)],
    bracket_link_ranges: &[(usize, usize)],
    mut citation_ranges: Option<&mut Vec<(usize, usize)>>,
    mut on_ref: F,
) where
    F: FnMut(usize, &str),
{
    let mut cursor = 0usize;
    while cursor < chunk.len() {
        let Some(pm) = cite_prefix_re().find_at(chunk, cursor) else {
            break;
        };
        let abs_start = base_offset + pm.start();
        if is_in_ranges(abs_start, verbatim_ranges)
            || is_strictly_inside_any_range(abs_start, bracket_link_ranges)
        {
            cursor = pm.end();
            continue;
        }
        // Find closing `]` respecting balanced `[...]` inside citation (`scan-lists` with `org-element--pair-square-table`)
        let after = &chunk[pm.end()..];
        let mut depth = 1usize;
        let mut close_rel = None;
        for (idx_b, b) in after.bytes().enumerate() {
            match b {
                b'[' => depth += 1,
                b']' => {
                    depth -= 1;
                    if depth == 0 {
                        close_rel = Some(idx_b);
                        break;
                    }
                }
                _ => {}
            }
        }
        let Some(close_rel) = close_rel else {
            cursor = pm.end();
            continue;
        };
        let body = &after[..close_rel];
        let Some(first_key) = cite_key_re().find(body) else {
            cursor = pm.end();
            continue;
        };

        let body_abs = base_offset + pm.end();
        // Match `org-element-citation-parser` `:contents-begin` / `:contents-end`
        let contents_begin = body[..first_key.start()].rfind(';').map_or(0, |p| p + 1);
        let trimmed_end = body.trim_end_matches([' ', '\r', '\t', '\n']).len();
        let contents_end = if let Some(semi_rel) = body[first_key.end()..trimmed_end].rfind(';') {
            let semi_abs = first_key.end() + semi_rel;
            if cite_key_re().is_match(&body[semi_abs + 1..trimmed_end]) {
                trimmed_end
            } else {
                semi_abs + 1
            }
        } else {
            trimmed_end
        };

        // Match `org-element-citation-reference-parser`: one `@key` per `;`-delimited segment;
        // segments without an `@key` merge into the next reference's `:begin`/`:prefix`.
        let slice = &body[contents_begin..contents_end];
        let mut seg_cur = 0usize;
        while seg_cur < slice.len() {
            let Some(km) = cite_key_re().captures(&slice[seg_cur..]) else {
                break;
            };
            let ref_abs = body_abs + contents_begin + seg_cur;
            let key = &km[1];
            let km_full = km.get(0).unwrap();
            let after_key = seg_cur + km_full.end();
            let next_seg = match slice[after_key..].find(';') {
                Some(semi_rel) => after_key + semi_rel + 1,
                None => slice.len(),
            };
            on_ref(ref_abs, key);
            seg_cur = next_seg;
        }

        if let Some(ref mut ranges) = citation_ranges {
            ranges.push((abs_start, body_abs + close_rel + 1));
        }
        cursor = pm.end() + close_rel + 1;
    }
}

fn scan_citations_in_chunk(
    idx: &LineIndex,
    chunk: &str,
    base_offset: usize,
    verbatim_ranges: &[(usize, usize)],
    bracket_link_ranges: &[(usize, usize)],
    roam_id_at_line: &dyn Fn(usize) -> Option<String>,
    outline_at_line: &dyn Fn(usize) -> Vec<String>,
    out: &mut Vec<ParsedCitation>,
    citation_ranges: &mut Vec<(usize, usize)>,
) {
    visit_citations_in_chunk(
        chunk,
        base_offset,
        verbatim_ranges,
        bracket_link_ranges,
        Some(citation_ranges),
        |ref_abs, key| {
            let line_idx = line_idx_for_byte(idx, ref_abs);
            if let Some(source) = roam_id_at_line(line_idx) {
                let outline = outline_at_line(line_idx);
                out.push(ParsedCitation {
                    node_id: source,
                    cite_key: key.to_string(),
                    pos: idx.byte_to_char_pos(ref_abs),
                    properties: format_link_properties(&outline, None),
                });
            }
        },
    );
}

/// Returns `(ts_ia, ts_active, active_ts_first)`.
fn scan_section_timestamps(
    idx: &LineIndex,
    kinds: &[LineKind],
    start_line: usize,
    end_line: usize,
) -> (Option<String>, Option<String>, bool) {
    let mut ts_ia: Option<(usize, String)> = None;
    let mut ts_active: Option<(usize, String)> = None;

    for i in start_line..end_line {
        if !matches!(kinds[i], LineKind::Normal | LineKind::Headline(_)) {
            continue;
        }
        let line = idx.line_str(i);
        let lstart = idx.lines[i].byte_start;
        if ts_ia.is_none() {
            if let Some(m) = ts_inactive_re().find(line) {
                ts_ia = Some((lstart + m.start(), m.as_str().to_string()));
            }
        }
        if ts_active.is_none() {
            if let Some(m) = ts_active_dow_re().find(line) {
                ts_active = Some((lstart + m.start(), m.as_str().to_string()));
            }
        }
        if ts_ia.is_some() && ts_active.is_some() {
            break;
        }
    }

    let active_first = match (&ts_active, &ts_ia) {
        (Some((ap, _)), Some((ip, _))) => ap < ip,
        _ => false,
    };
    (
        ts_ia.map(|(_, s)| s),
        ts_active.map(|(_, s)| s),
        active_first,
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_missing_title_and_file_node() {
        let doc = ":PROPERTIES:\n:ID: id-1\n:END:\nBody [[id:id-2][Link]]\n";
        let p = parse_org_file("/vault/no-title.org", doc);
        assert_eq!(p.file_title, "");
        assert_eq!(p.nodes.len(), 1);
        assert_eq!(p.nodes[0].id, "id-1");
        assert_eq!(p.nodes[0].level, 0);
        assert_eq!(p.nodes[0].pos, 1);
        assert_eq!(p.nodes[0].title, "");
        assert_eq!(p.links.len(), 1);
        assert_eq!(p.links[0].dest, "id-2");
        assert_eq!(p.links[0].link_type, "id");
    }

    #[test]
    fn test_keyword_before_properties_disables_file_node() {
        let doc = "#+title: Early\n:PROPERTIES:\n:ID: ignored-id\n:END:\n";
        let p = parse_org_file("/vault/kw.org", doc);
        assert_eq!(p.file_title, "Early");
        assert!(p.nodes.is_empty());
        assert!(p.org_ids.is_empty());
    }

    #[test]
    fn test_headings_priority_exclude_olp_and_refs() {
        let doc = "\
:PROPERTIES:
:ID: file-id
:ROAM_REFS: @citeA \"https://example.com/a b\"
:END:
#+title: Root
#+filetags: :ftag:ftag:

* TODO [#A] Parent [1/2] [[id:x][Desc]] :ptag:
SCHEDULED: <2026-05-01 Fri 09:30>
:PROPERTIES:
:ID: head-1
:ROAM_EXCLUDE: nil
:ROAM_ALIASES: simple \"two words\"
:END:
** Child
:PROPERTIES:
:ID: head-excl
:ROAM_EXCLUDE:
:END:
Link under excluded [[id:target::*Sec]]
*** Grandchild
:PROPERTIES:
:ID: head-grand
:END:
";
        let p = parse_org_file("/vault/test.org", doc);
        assert_eq!(p.nodes.len(), 3); // file-id, head-1, head-grand (head-excl excluded)
        assert_eq!(p.nodes[1].id, "head-1");
        assert_eq!(p.nodes[1].todo.as_deref(), Some("TODO"));
        assert_eq!(p.nodes[1].priority, Some(65));
        assert_eq!(p.nodes[1].scheduled.as_deref(), Some("2026-05-01T09:30:00"));
        assert_eq!(p.nodes[1].olp, None);

        assert_eq!(p.nodes[2].id, "head-grand");
        assert_eq!(
            p.nodes[2].olp.as_deref(),
            Some("(\"Parent  Desc\" \"Child\")")
        );

        // Filetags are non-dedup at level 0
        let file_tags: Vec<&str> = p
            .tags
            .iter()
            .filter(|(id, _)| id == "file-id")
            .map(|(_, t)| t.as_str())
            .collect();
        assert_eq!(file_tags, vec!["ftag", "ftag"]);

        // Refs reversed on push
        assert_eq!(
            p.refs,
            vec![
                (
                    "file-id".to_string(),
                    "//example.com/a b".to_string(),
                    "https".to_string()
                ),
                ("file-id".to_string(), "citeA".to_string(), "cite".to_string()),
            ]
        );

        // Link on Parent heading + link under excluded heading (resolves source to ancestor head-1, :outline includes Child)
        assert_eq!(p.links.len(), 2);
        assert_eq!(p.links[0].source, "head-1");
        assert_eq!(p.links[0].dest, "x");
        assert_eq!(p.links[0].properties, "(:outline (\"Parent  Desc\"))");
        assert_eq!(p.links[1].source, "head-1");
        assert_eq!(p.links[1].dest, "target");
        assert_eq!(
            p.links[1].properties,
            "(:outline (\"Parent  Desc\" \"Child\") :search-option \"*Sec\")"
        );
    }

    #[test]
    fn test_cjk_verbatim_and_file_search_option() {
        let doc = "\
:PROPERTIES:
:ID: cjk-1
:END:
#+title: CJK
#+filetags: :lang_elisp:type_howto:

中文=https://leak.example.com=（或
Ascii =https://hidden.example.com= ok.
[[file:other.org::*H]] and [[Fuzzy::opt]]
";
        let p = parse_org_file("/vault/cjk.org", doc);
        let dests: Vec<(&str, &str, &str)> = p
            .links
            .iter()
            .map(|l| (l.link_type.as_str(), l.dest.as_str(), l.properties.as_str()))
            .collect();
        assert_eq!(
            dests,
            vec![
                ("elisp", "type_howto", "(:outline nil)"),
                ("https", "//leak.example.com=（或", "(:outline nil)"),
                ("file", "other.org", "(:outline nil)"),
                ("fuzzy", "Fuzzy", "(:outline nil :search-option \"opt\")"),
            ]
        );
    }

    #[test]
    fn test_challenger2_parser_parity_fixes() {
        let doc = "\
:PROPERTIES:
:ID: f-id
:ROAM_REFS: [cite:@k2;@k3] [cite/t:@k4]
:END:
#+TODO: TODO NEXT | DONE CANCELLED
#+filetags: :ft1:ft2:ft1:
#+filetags: :ft3:

*\tTabAfterStar
:PROPERTIES:
:ID: not-a-heading
:END:

* NEXT Parent :p_tag:
:PROPERTIES:
:ID: h-next
:A_PROP: a
:CATEGORY: ParentCat
:Z_PROP: z
:END:
[2026-05-01 Fri]
<2026-05-02 Sat>
** CANCELLED Child :c@1:ft2:
:PROPERTIES:
:ID: h-canc
:END:
* DONE DoneParent
:PROPERTIES:
:ID: h-done
:END:
** TODO OpenChild
:PROPERTIES:
:ID: h-open
:END:
*** Skipped lvl 3 TODO [#A] HasChildDone
:PROPERTIES:
:ID: h-prio
:END:
* TODO\t[#A]\tTabbed heading\t:tabtag:
:PROPERTIES:
:ID: h-tab
:END:
中文🚀 [cite:@k1; @k2] and [cite/t:pre @k3 post].
";
        let p = parse_org_file("/vault/adv.org", doc);

        // 1. Only `[cite:` refs accepted, `[cite/t:@k4]` rejected
        assert_eq!(
            p.refs,
            vec![
                ("f-id".to_string(), "k3".to_string(), "cite".to_string()),
                ("f-id".to_string(), "k2".to_string(), "cite".to_string()),
            ]
        );

        // 2. `*\tTabAfterStar` is NOT a headline (`not-a-heading` not a node)
        assert!(p.nodes.iter().all(|n| n.id != "not-a-heading"));

        // 3. File node ALLTAGS last-occurrence dedup: :ft2:ft1:ft3:
        let fnode = p.nodes.iter().find(|n| n.id == "f-id").unwrap();
        let fprops = fnode.properties.as_deref().unwrap();
        assert!(fprops.contains("(\"ALLTAGS\" . \":ft2:ft1:ft3:\")"), "fprops={}", fprops);

        // 4. `h-next`: CATEGORY stays in drawer order between A_PROP and Z_PROP, TIMESTAMP before TIMESTAMP_IA, BLOCKED=""
        let hnext = p.nodes.iter().find(|n| n.id == "h-next").unwrap();
        let hn_props = hnext.properties.as_deref().unwrap();
        let z_idx = hn_props.find("(\"Z_PROP\" . \"z\")").unwrap();
        let cat_idx = hn_props.find("(\"CATEGORY\" . \"ParentCat\")").unwrap();
        let a_idx = hn_props.find("(\"A_PROP\" . \"a\")").unwrap();
        assert!(z_idx < cat_idx && cat_idx < a_idx, "hn_props={}", hn_props);
        let ts_idx = hn_props.find("(\"TIMESTAMP\" . \"<2026-05-02 Sat>\")").unwrap();
        let tsia_idx = hn_props.find("(\"TIMESTAMP_IA\" . \"[2026-05-01 Fri]\")").unwrap();
        assert!(ts_idx < tsia_idx, "hn_props={}", hn_props);
        assert!(hn_props.contains("(\"BLOCKED\" . \"\")"), "hn_props={}", hn_props);

        // 5. `h-canc` ALLTAGS last-occurrence dedup: :ft1:ft3:p_tag:c@1:ft2:
        let hcanc = p.nodes.iter().find(|n| n.id == "h-canc").unwrap();
        assert!(hcanc
            .properties
            .as_deref()
            .unwrap()
            .contains("(\"ALLTAGS\" . \":ft1:ft3:p_tag:c@1:ft2:\")"));

        // 6. `h-done` has BLOCKED = "" despite TODO child
        let hdone = p.nodes.iter().find(|n| n.id == "h-done").unwrap();
        assert!(hdone
            .properties
            .as_deref()
            .unwrap()
            .contains("(\"BLOCKED\" . \"\")"));

        // 7. `h-prio` priority column is None, but properties PRIORITY is "A"
        let hprio = p.nodes.iter().find(|n| n.id == "h-prio").unwrap();
        assert_eq!(hprio.priority, None);
        assert!(hprio
            .properties
            .as_deref()
            .unwrap()
            .contains("(\"PRIORITY\" . \"A\")"));

        // 8. `h-tab` todo/priority None, title keeps `\t`, ITEM expands tabs, PRIORITY="A"
        let htab = p.nodes.iter().find(|n| n.id == "h-tab").unwrap();
        assert_eq!(htab.todo, None);
        assert_eq!(htab.priority, None);
        assert_eq!(htab.title, "TODO\t[#A]\tTabbed heading");
        let htab_props = htab.properties.as_deref().unwrap();
        assert!(htab_props.contains("(\"PRIORITY\" . \"A\")"));
        assert!(htab_props.contains("(\"ITEM\" . \"TODO    [#A]    Tabbed heading\")"));

        // 9. Citations `pos` matches `citation-reference` `:begin`
        let line_text = "中文🚀 [cite:@k1; @k2] and [cite/t:pre @k3 post].";
        let line_char_start = doc[..doc.find("中文🚀").unwrap()].chars().count() as i64 + 1;
        let k1_off = line_text[..line_text.find("@k1").unwrap()].chars().count() as i64;
        let k2_off = line_text[..line_text.find(" @k2").unwrap()].chars().count() as i64;
        let k3_off = line_text[..line_text.find("pre @k3").unwrap()].chars().count() as i64;
        assert_eq!(p.citations.len(), 3);
        assert_eq!(p.citations[0].cite_key, "k1");
        assert_eq!(p.citations[0].pos, line_char_start + k1_off);
        assert_eq!(p.citations[1].cite_key, "k2");
        assert_eq!(p.citations[1].pos, line_char_start + k2_off);
        assert_eq!(p.citations[2].cite_key, "k3");
        assert_eq!(p.citations[2].pos, line_char_start + k3_off);
    }

    #[test]
    fn test_todo_keywords_no_pipe_last_is_done() {
        let mut kw = TodoKeywords {
            all: Vec::new(),
            active: HashSet::new(),
            done: HashSet::new(),
        };
        parse_todo_keywords_line("A(a) B C(c)", &mut kw);
        assert_eq!(kw.all, vec!["A", "B", "C"]);
        assert!(kw.active.contains("A"));
        assert!(kw.active.contains("B"));
        assert!(!kw.active.contains("C"));
        assert!(kw.done.contains("C"));
    }

    #[test]
    fn test_file_property_category_inheritance_and_nested_cite_brackets() {
        // 1. File-level `:CATEGORY:` without `#+CATEGORY:`
        let doc_drawer_only = "\
:PROPERTIES:
:ID: f-drawer-only
:CATEGORY: FileDrawerCat
:END:
#+title: Drawer Only

* Child
:PROPERTIES:
:ID: h-drawer-only
:END:
";
        let p1 = parse_org_file("/vault/cat-drawer-only.org", doc_drawer_only);
        let h1 = p1.nodes.iter().find(|n| n.id == "h-drawer-only").unwrap();
        assert!(
            h1.properties
                .as_deref()
                .unwrap()
                .contains("(\"CATEGORY\" . \"FileDrawerCat\")"),
            "h1_props={:?}",
            h1.properties
        );

        // 2. File-level `:CATEGORY:` overrides `#+CATEGORY:` when inherited
        let doc_both = "\
:PROPERTIES:
:ID: f-both
:CATEGORY: DrawerCat
:END:
#+CATEGORY: KwCat
#+title: Both

* Child
:PROPERTIES:
:ID: h-both
:END:
Multi [cite:@m4 p. [10]; @m5] and [cite:@a [b [c]]; @d].
";
        let p2 = parse_org_file("/vault/cat-both.org", doc_both);
        let hb = p2.nodes.iter().find(|n| n.id == "h-both").unwrap();
        assert!(
            hb.properties
                .as_deref()
                .unwrap()
                .contains("(\"CATEGORY\" . \"DrawerCat\")"),
            "hb_props={:?}",
            hb.properties
        );

        // 3. Citations with nested `[...]` locators do not truncate at inner `]`
        let keys: Vec<(&str, &str)> = p2
            .citations
            .iter()
            .map(|c| (c.node_id.as_str(), c.cite_key.as_str()))
            .collect();
        assert_eq!(
            keys,
            vec![
                ("h-both", "m4"),
                ("h-both", "m5"),
                ("h-both", "a"),
                ("h-both", "d"),
            ]
        );
    }

    #[test]
    fn test_category_plus_inheritance_and_citation_link_parity() {
        // 1. `:CATEGORY+:` without `#+CATEGORY:` (stem + FilePlus for child, drawer-only for file)
        let doc_plus_nokw = "\
:PROPERTIES:
:ID: f-pnk
:CATEGORY+: FilePlus
:END:
* H1
:PROPERTIES:
:ID: h-pnk
:END:
";
        let p_pnk = parse_org_file("/vault/catplus_nokw.org", doc_plus_nokw);
        assert!(p_pnk.nodes[0]
            .properties
            .as_deref()
            .unwrap()
            .contains("(\"CATEGORY\" . \"FilePlus\")"));
        assert!(p_pnk.nodes[1]
            .properties
            .as_deref()
            .unwrap()
            .contains("(\"CATEGORY\" . \"catplus_nokw FilePlus\")"));

        // 2. `:CATEGORY+:` with `#+CATEGORY:` and heading `:CATEGORY+:` chain
        let doc_plus_kw = "\
:PROPERTIES:
:ID: f-pkw
:CATEGORY+: FilePlus
:END:
#+CATEGORY: KwCat
* H1
:PROPERTIES:
:ID: h-pkw1
:CATEGORY+: HeadPlus
:END:
** H2
:PROPERTIES:
:ID: h-pkw2
:END:
";
        let p_pkw = parse_org_file("/vault/catplus_kw.org", doc_plus_kw);
        let fp = p_pkw.nodes.iter().find(|n| n.id == "f-pkw").unwrap();
        let h1 = p_pkw.nodes.iter().find(|n| n.id == "h-pkw1").unwrap();
        let h2 = p_pkw.nodes.iter().find(|n| n.id == "h-pkw2").unwrap();
        assert!(fp.properties.as_deref().unwrap().contains("(\"CATEGORY\" . \"FilePlus\")"));
        assert!(h1.properties.as_deref().unwrap().contains("(\"CATEGORY\" . \"HeadPlus\")"));
        assert!(h2.properties.as_deref().unwrap().contains("(\"CATEGORY\" . \"KwCat FilePlus HeadPlus\")"));

        // 3. Citations: `;` inside `[...]`, links inside citations, unclosed across paragraphs, nested `[cite:]`
        let doc_cites = "\
:PROPERTIES:
:ID: f-c
:END:
* H
:PROPERTIES:
:ID: h-c
:END:
[cite:@semi [10;20]; @aftersemi].
[cite:@link [[id:f-c][desc]]; @afterlink].
C [cite:@bad [10; @next].
D [cite:@e \\] p. 1; @f].
Nested [cite:@a [cite:@b] ; @c].
Unclosed [cite:@unclosed [loc

Next para with ] and ] and [cite:@good].
";
        let p_cites = parse_org_file("/vault/cites.org", doc_cites);
        assert!(p_cites.links.is_empty(), "links={:?}", p_cites.links);
        let cite_pairs: Vec<(&str, i64)> = p_cites
            .citations
            .iter()
            .map(|c| (c.cite_key.as_str(), c.pos))
            .collect();
        let expected_aftersemi_pos =
            doc_cites[..doc_cites.find("20]; @aftersemi").unwrap()].chars().count() as i64 + 1;
        assert_eq!(
            cite_pairs
                .iter()
                .map(|(k, _)| *k)
                .collect::<Vec<&str>>(),
            vec!["semi", "aftersemi", "link", "afterlink", "bad", "next", "f", "a", "c", "good"]
        );
        assert_eq!(cite_pairs[1], ("aftersemi", expected_aftersemi_pos));
    }

    #[test]
    fn test_empty_category_and_roam_refs_cite_parity() {
        // 1. Empty `#+CATEGORY:` sets category to "" (alone and combined with `:CATEGORY+:`)
        let doc_empty_cat = "\
:PROPERTIES:
:ID: f-ek
:END:
#+CATEGORY:
* H1
:PROPERTIES:
:ID: h-ek
:END:
";
        let p_ek = parse_org_file("/vault/empty-kw.org", doc_empty_cat);
        assert!(p_ek.nodes[0]
            .properties
            .as_deref()
            .unwrap()
            .contains("(\"CATEGORY\" . \"\")"));
        assert!(p_ek.nodes[1]
            .properties
            .as_deref()
            .unwrap()
            .contains("(\"CATEGORY\" . \"\")"));

        let doc_empty_cat_plus = "\
:PROPERTIES:
:ID: f-ekp
:END:
#+CATEGORY:
* H1
:PROPERTIES:
:ID: h-ekp1
:CATEGORY+: Plus
:END:
** H2
:PROPERTIES:
:ID: h-ekp2
:END:
";
        let p_ekp = parse_org_file("/vault/empty-kw-sub.org", doc_empty_cat_plus);
        assert!(p_ekp.nodes[0]
            .properties
            .as_deref()
            .unwrap()
            .contains("(\"CATEGORY\" . \"\")"));
        assert!(p_ekp.nodes[1]
            .properties
            .as_deref()
            .unwrap()
            .contains("(\"CATEGORY\" . \"Plus\")"));
        assert!(p_ekp.nodes[2]
            .properties
            .as_deref()
            .unwrap()
            .contains("(\"CATEGORY\" . \" Plus\")"));

        // 2. `:ROAM_REFS:` `[cite:...]` matches `org-cite-parse-objects`
        let doc_refs = "\
:PROPERTIES:
:ID: r-unquoted
:ROAM_REFS: [cite:@r1; @r2] [cite:@unclosed
:END:
* Quoted nested and complex cite refs
:PROPERTIES:
:ID: r-quoted
:ROAM_REFS: \"[cite:@a [10; @b]; @c]\" \"[cite:@x [cite:@nest]; @d]\" \"[cite:@u [cite:@inner]\" \"[cite:@k1] [[id:x][[cite:@k2]]]\" \"[cite:@p] [cite/t:@q]\"
:END:
";
        let p_refs = parse_org_file("/vault/refs.org", doc_refs);
        let r_unq: Vec<&str> = p_refs
            .refs
            .iter()
            .filter(|(nid, _, _)| nid == "r-unquoted")
            .map(|(_, k, _)| k.as_str())
            .collect();
        // `[cite:@r1;` is unclosed -> 0 refs; `@r2]` starts with `@` -> "r2]"; `[cite:@unclosed` -> 0 refs
        assert_eq!(r_unq, vec!["r2]"]);

        let r_quo: Vec<&str> = p_refs
            .refs
            .iter()
            .filter(|(nid, _, _)| nid == "r-quoted")
            .map(|(_, k, _)| k.as_str())
            .collect();
        // Forward order: a, b, c, x, d, inner, k1, p, q -> reversed by `rows.reverse()`
        assert_eq!(r_quo, vec!["q", "p", "k1", "inner", "d", "x", "c", "b", "a"]);
    }

    #[test]
    fn test_category_nil_and_bridge_link_cite_suppression() {
        // 1. `CATEGORY` exact `"nil"` -> `"???"` when inherited/keyword/file-stem (absent from own drawer)
        let doc_kw_nil = "\
:PROPERTIES:
:ID: f-kwnil
:END:
#+CATEGORY: nil
* H1
:PROPERTIES:
:ID: h-kwnil
:END:
";
        let p_kwnil = parse_org_file("/vault/kw-nil.org", doc_kw_nil);
        assert!(p_kwnil.nodes[0]
            .properties
            .as_deref()
            .unwrap()
            .contains("(\"CATEGORY\" . \"???\")"));
        assert!(p_kwnil.nodes[1]
            .properties
            .as_deref()
            .unwrap()
            .contains("(\"CATEGORY\" . \"???\")"));

        let doc_file_nil = "\
:PROPERTIES:
:ID: f-fnil
:END:
* H1
:PROPERTIES:
:ID: h-fnil
:END:
";
        let p_fnil = parse_org_file("/vault/nil.org", doc_file_nil);
        assert!(p_fnil.nodes[0]
            .properties
            .as_deref()
            .unwrap()
            .contains("(\"CATEGORY\" . \"???\")"));
        assert!(p_fnil.nodes[1]
            .properties
            .as_deref()
            .unwrap()
            .contains("(\"CATEGORY\" . \"???\")"));

        let doc_drawer_nil = "\
:PROPERTIES:
:ID: f-dnil
:CATEGORY: nil
:END:
* H1
:PROPERTIES:
:ID: h-dnil
:END:
";
        let p_dnil = parse_org_file("/vault/drawer-nil.org", doc_drawer_nil);
        assert!(p_dnil.nodes[0]
            .properties
            .as_deref()
            .unwrap()
            .contains("(\"CATEGORY\" . \"nil\")"));
        assert!(p_dnil.nodes[1]
            .properties
            .as_deref()
            .unwrap()
            .contains("(\"CATEGORY\" . \"???\")"));

        let doc_kw_nil_plus = "\
:PROPERTIES:
:ID: f-kwnp
:CATEGORY+: Plus
:END:
#+CATEGORY: nil
* H1
:PROPERTIES:
:ID: h-kwnp
:END:
";
        let p_kwnp = parse_org_file("/vault/kw-nil-plus.org", doc_kw_nil_plus);
        assert!(p_kwnp.nodes[0]
            .properties
            .as_deref()
            .unwrap()
            .contains("(\"CATEGORY\" . \"Plus\")"));
        assert!(p_kwnp.nodes[1]
            .properties
            .as_deref()
            .unwrap()
            .contains("(\"CATEGORY\" . \"nil Plus\")"));

        let doc_upper_nil = "\
:PROPERTIES:
:ID: f-upper
:END:
#+CATEGORY: NIL
";
        let p_upper = parse_org_file("/vault/upper-nil.org", doc_upper_nil);
        assert!(p_upper.nodes[0]
            .properties
            .as_deref()
            .unwrap()
            .contains("(\"CATEGORY\" . \"NIL\")"));

        // 2. Empty-desc bridge links (`[[id:x][]] [[id:y][[cite:@k]]]`, multi-bridge, cross-container, verbatim-prefixed)
        let doc_bridge = "\
:PROPERTIES:
:ID: bc-1
:ROAM_REFS: \"[cite:@k1] [[id:x][]] [[id:y][[cite:@k2]]]\" \"[cite:@k3] [[id:a][]] [[id:b][]] [[id:c][[cite:@k4]]]\" \"[cite:@k5] [[id:a][]] [[id:b][]] [[id:c][]] [[id:d][[cite:@k6]]]\"
:END:
Body1 [cite:@b1] [[id:x][]] [[id:y][[cite:@b2]]].
Body2 [[id:a][]] [[id:b][]] [[id:c][[cite:@b3]]].
Body3 [[id:a][]] [[id:b][]] [[id:c][]] [[id:d][[cite:@b4]]].
Body4 [cite:@br [[id:x][]]] and [cite:@other] and [[id:y][[cite:@inner]]].
Body5 =[[id:x][]]= [[id:y][[cite:@b5]]].
Body6 [[id:p][]]

[[id:q][[cite:@b6]]].
";
        let p_bridge = parse_org_file("/vault/bridge-cite.org", doc_bridge);
        let ref_keys: Vec<&str> = p_bridge.refs.iter().map(|(_, k, _)| k.as_str()).collect();
        assert_eq!(ref_keys, vec!["k5", "k3", "k1"]);
        let cite_keys: Vec<&str> = p_bridge
            .citations
            .iter()
            .map(|c| c.cite_key.as_str())
            .collect();
        assert_eq!(cite_keys, vec!["b1", "br", "other"]);
        let link_dests: Vec<&str> = p_bridge.links.iter().map(|l| l.dest.as_str()).collect();
        assert_eq!(link_dests, vec!["x", "a", "c", "a", "c", "y", "y", "q"]);
    }

    #[test]
    fn test_empty_title_heading_with_id_and_links_no_fk_orphan() {
        let doc = "\
:PROPERTIES:
:ID: file-ok
:END:
#+title: File OK

* Parent
:PROPERTIES:
:ID: parent-ok
:END:
** 
:PROPERTIES:
:ID: empty-sub
:END:
[[id:file-ok][link]] and [cite:@k1].
";
        let p = parse_org_file("/vault/empty-h.org", doc);
        let node_ids: Vec<&str> = p.nodes.iter().map(|n| n.id.as_str()).collect();
        assert_eq!(node_ids, vec!["file-ok", "parent-ok"]);
        // Neither links nor citations may reference skipped node `empty-sub`!
        assert!(p.links.iter().all(|l| node_ids.contains(&l.source.as_str())));
        assert!(p.citations.iter().all(|c| node_ids.contains(&c.node_id.as_str())));
        assert!(p.links.is_empty());
        assert!(p.citations.is_empty());
    }

    #[test]
    fn test_crlf_line_endings_tags_title_and_pos() {
        let doc = ":PROPERTIES:\r\n:ID: crlf-f\r\n:END:\r\n#+title: CRLF\r\n\r\n* TODO Heading :tag1:\r\n:PROPERTIES:\r\n:ID: crlf-h\r\n:END:\r\n[[id:crlf-f][back]]\r\n";
        let p = parse_org_file("/vault/crlf.org", doc);
        let h = p.nodes.iter().find(|n| n.id == "crlf-h").unwrap();
        assert_eq!(h.title, "Heading");
        assert!(p.tags.contains(&("crlf-h".to_string(), "tag1".to_string())));
        assert!(!h.properties.as_deref().unwrap().contains("\\15"));
        let lf_doc = doc.replace("\r\n", "\n");
        let p_lf = parse_org_file("/vault/crlf.org", &lf_doc);
        assert_eq!(p.links[0].pos, p_lf.links[0].pos);
    }

    #[test]
    fn test_mixed_eol_drawer_requires_clean_lf_line_end() {
        let doc = ":PROPERTIES:\n:ID: mix-f\n:END:\n#+title: Mixed\n\n* HMix\n:PROPERTIES:\r\n:ID: mix-h\r\n:END:\r\n[[id:mix-f][l]]\n";
        let p = parse_org_file("/vault/mixed.org", doc);
        let node_ids: Vec<&str> = p.nodes.iter().map(|n| n.id.as_str()).collect();
        assert_eq!(node_ids, vec!["mix-f"]);
        assert_eq!(p.links.len(), 1);
        assert_eq!(p.links[0].source, "mix-f");
    }
}
