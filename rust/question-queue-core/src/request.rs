//! Build the markdown request document, name it uniquely, and drop it into the
//! queue's `input/` directory atomically.
//!
//! Atomicity matters: the queue monitor watches `input/` for `close_write` AND
//! `moved_to`, and a rename-into-place fires exactly one `moved_to` with the
//! file already complete — no partial-write race where the monitor reads a
//! half-written question. So we write a dotfile temp in the same directory,
//! `fsync`, then `rename` it onto the final name (same-filesystem rename is
//! atomic on Linux).

use std::collections::hash_map::DefaultHasher;
use std::hash::{Hash, Hasher};
use std::io::Write;
use std::path::Path;
use std::time::{SystemTime, UNIX_EPOCH};

/// User timezone is UTC+8 (no DST), per the project convention. Filenames and
/// the `created:` field are stamped in local time for human legibility;
/// uniqueness comes from the hash suffix, not the timestamp.
const TZ_OFFSET_SECS: i64 = 8 * 3600;

/// Assemble + atomically write the request. Returns the basename written.
pub fn submit(
    region: &str,
    question: &str,
    lang: &str,
    source: Option<&str>,
    input_dir: &str,
) -> Result<String, String> {
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|e| format!("clock before epoch: {e}"))?;
    let local = now.as_secs() as i64 + TZ_OFFSET_SECS;
    let (date_compact, created) = format_times(local);

    let suffix = short_hash(question, region, now.subsec_nanos());
    let stem = format!("{date_compact}-{suffix:06x}");
    let filename = format!("{stem}.md");

    let body = build_markdown(region, question, lang, source, &stem, &created);
    atomic_write(Path::new(input_dir), &filename, &body)?;
    Ok(filename)
}

/// 24-bit hash of (question, region, nanos) → collision guard for two submits
/// landing in the same second.
fn short_hash(question: &str, region: &str, nanos: u32) -> u32 {
    let mut h = DefaultHasher::new();
    question.hash(&mut h);
    region.hash(&mut h);
    nanos.hash(&mut h);
    (h.finish() & 0x00ff_ffff) as u32
}

/// `("YYYYMMDD-HHMMSS", "YYYY-MM-DD HH:MM:SS+08:00")` from local-adjusted epoch.
fn format_times(local_secs: i64) -> (String, String) {
    let days = local_secs.div_euclid(86_400);
    let tod = local_secs.rem_euclid(86_400);
    let (h, mi, s) = (tod / 3600, (tod % 3600) / 60, tod % 60);
    let (y, m, d) = civil_from_days(days);
    (
        format!("{y:04}{m:02}{d:02}-{h:02}{mi:02}{s:02}"),
        format!("{y:04}-{m:02}-{d:02} {h:02}:{mi:02}:{s:02}+08:00"),
    )
}

/// Days-since-1970 → (year, month, day), Gregorian. Howard Hinnant's
/// `civil_from_days` (public domain), the standard chrono-free conversion.
fn civil_from_days(z: i64) -> (i64, u32, u32) {
    let z = z + 719_468;
    let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
    let doe = (z - era * 146_097) as i64; // [0, 146096]
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365; // [0, 399]
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100); // [0, 365]
    let mp = (5 * doy + 2) / 153; // [0, 11]
    let d = (doy - (153 * mp + 2) / 5 + 1) as u32; // [1, 31]
    let m = if mp < 10 { mp + 3 } else { mp - 9 } as u32; // [1, 12]
    (if m <= 2 { y + 1 } else { y }, m, d)
}

/// The markdown the answerer reads. Front-matter carries provenance; the
/// question and the highlighted context are clearly separated, with the
/// context in a fenced block tagged with the buffer's language for syntax
/// highlighting on the reading side.
///
/// The context block is OMITTED entirely when REGION is empty/blank — a
/// question-only request (no highlight) ships just the front-matter + question,
/// not an empty code fence.
fn build_markdown(
    region: &str,
    question: &str,
    lang: &str,
    source: Option<&str>,
    stem: &str,
    created: &str,
) -> String {
    let source_line = source.unwrap_or("(unknown)");
    let header = format!(
        "---\n\
         id: {stem}\n\
         source: {source_line}\n\
         lang: {lang}\n\
         created: {created}\n\
         ---\n\
         \n\
         # Question\n\
         \n\
         {question}\n",
    );
    if region.trim().is_empty() {
        return header;
    }
    let lang_tag = if lang.is_empty() { "text" } else { lang };
    // Guard against the region containing a ``` fence that would close ours
    // early: if it does, bump our fence to a longer run.
    let fence = pick_fence(region);
    format!(
        "{header}\n\
         # Context\n\
         \n\
         {fence}{lang_tag}\n\
         {region}\n\
         {fence}\n",
    )
}

/// Choose a backtick fence longer than any run of backticks inside `body`, so
/// embedded fences can't terminate the block prematurely.
fn pick_fence(body: &str) -> String {
    let mut max_run = 0usize;
    let mut cur = 0usize;
    for ch in body.chars() {
        if ch == '`' {
            cur += 1;
            max_run = max_run.max(cur);
        } else {
            cur = 0;
        }
    }
    "`".repeat(max_run.max(2) + 1)
}

/// Write to `dir/.NAME.tmp`, fsync, then rename onto `dir/NAME`.
fn atomic_write(dir: &Path, filename: &str, body: &str) -> Result<(), String> {
    std::fs::create_dir_all(dir)
        .map_err(|e| format!("create_dir_all {}: {e}", dir.display()))?;
    let tmp = dir.join(format!(".{filename}.tmp"));
    let final_path = dir.join(filename);
    {
        let mut f = std::fs::File::create(&tmp)
            .map_err(|e| format!("create {}: {e}", tmp.display()))?;
        f.write_all(body.as_bytes())
            .map_err(|e| format!("write {}: {e}", tmp.display()))?;
        // Best-effort durability; ignore fsync errors on filesystems that no-op.
        let _ = f.sync_all();
    }
    std::fs::rename(&tmp, &final_path).map_err(|e| {
        let _ = std::fs::remove_file(&tmp);
        format!("rename {} -> {}: {e}", tmp.display(), final_path.display())
    })?;
    Ok(())
}
