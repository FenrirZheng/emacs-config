//! Clean the answerer's `output/<name>` text before it goes back into Emacs.
//!
//! The answering side writes free-form markdown. We do two light, predictable
//! normalisations and otherwise pass the text through verbatim:
//!   1. Trim surrounding whitespace.
//!   2. If the whole answer is a single fenced code block (some answerers wrap
//!      their entire reply in ```), unwrap it so the buffer shows the content,
//!      not the fence.
//!   3. If the answer leads with an echoed YAML front-matter block, drop it.
//!
//! Deliberately conservative: we never reflow, re-wrap, or strip internal
//! fences — only the outermost wrapper a tool might have added.

/// Normalise the raw output file contents into the answer body.
pub fn parse(text: &str) -> String {
    let t = strip_front_matter(text.trim());
    let t = t.trim();
    match unwrap_single_fence(t) {
        Some(inner) => inner,
        None => t.to_string(),
    }
}

/// Drop a leading `---\n ... \n---\n` YAML block if present, else return as-is.
fn strip_front_matter(text: &str) -> &str {
    let Some(rest) = text.strip_prefix("---\n") else {
        return text;
    };
    // Find the closing delimiter line.
    if let Some(idx) = rest.find("\n---\n") {
        &rest[idx + "\n---\n".len()..]
    } else if let Some(idx) = rest.find("\n---") {
        // closing fence at EOF without trailing newline
        rest[idx + "\n---".len()..].trim_start_matches('\n')
    } else {
        text
    }
}

/// If `text` is exactly one fenced block (first line opens a ``` fence, last
/// non-empty line is the matching close), return the inner content; else None.
fn unwrap_single_fence(text: &str) -> Option<String> {
    let mut lines = text.lines();
    let first = lines.next()?;
    let fence = fence_marker(first)?; // e.g. "```" or "````"
    // The opening line may carry an info string (```rust) — that's fine.
    let mut body: Vec<&str> = Vec::new();
    let mut closed = false;
    for line in lines {
        if !closed && line.trim_end() == fence {
            closed = true;
            continue; // consume the closing fence
        }
        if closed {
            // Anything after the close means it was NOT a single wrapping block.
            return None;
        }
        body.push(line);
    }
    if closed {
        Some(body.join("\n"))
    } else {
        None
    }
}

/// Return the bare backtick run that opens `line` (≥3 backticks), or None.
fn fence_marker(line: &str) -> Option<String> {
    let ticks = line.chars().take_while(|&c| c == '`').count();
    if ticks >= 3 {
        Some("`".repeat(ticks))
    } else {
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn plain_passthrough() {
        assert_eq!(parse("  hello world \n"), "hello world");
    }

    #[test]
    fn unwraps_single_fence() {
        assert_eq!(parse("```\nlet x = 1;\n```"), "let x = 1;");
        assert_eq!(parse("```rust\nfn main() {}\n```"), "fn main() {}");
    }

    #[test]
    fn keeps_multi_block() {
        let s = "intro\n```\ncode\n```\noutro";
        assert_eq!(parse(s), s);
    }

    #[test]
    fn strips_front_matter() {
        assert_eq!(parse("---\nid: x\n---\nthe answer"), "the answer");
    }
}
