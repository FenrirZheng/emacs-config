//! git-subtree-status — which git subtrees in this repo have changed.
//!
//! Subtrees are discovered from the trailers `git subtree add/merge/pull` write
//! (`git-subtree-dir:` / `git-subtree-split:`), so no registry file is needed.
//! For every subtree still present at HEAD it reports:
//!
//! * uncommitted — paths under the prefix that `git status` would list
//! * since       — files changed under the prefix between `--since <rev|date>` and HEAD
//! * import      — whether the prefix differs from what the last import brought in
//! * upstream    — whether the prefix differs from the ref in the optional git config
//!                 `subtree.<prefix>.upstream`
//!
//! Read-only, and offline: it reads the repository with gix and never fetches.

use std::collections::HashMap;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::exit;

use gix::ObjectId;
use gix::bstr::{BString, ByteSlice};

type Res<T> = Result<T, Box<dyn std::error::Error + Send + Sync + 'static>>;

const USAGE: &str = "\
usage: git-subtree-status [options]

  -C <dir>             run in <dir> instead of the current directory
  --since <rev|date>   also count files changed since a revision, or a date such
                       as '7 days ago' (the last first-parent commit before it)
  --filter <substr>    only subtrees whose prefix contains <substr>
  --all                list every subtree, not only those with a change
  --porcelain          tab-separated output for scripts (format below)
  --exit-code          exit 1 if any subtree has a change
  --no-status          skip the uncommitted count (reported as '-'); for callers
                       such as Magit that already know the working tree state
  --owner-of <rev>     print the prefix(es) of the subtree(s) a commit belongs
                       to, one per line, and nothing else
  -h, --help           this help
  -V, --version        print the version

Upstream refs are optional git config, one per subtree:
  git config subtree.<prefix>.upstream <ref>        e.g. lib-remote/main

--porcelain v1: a '# git-subtree-status v1' line, then one line per subtree:
  prefix uncommitted since import import_files upstream_ref upstream upstream_files project_rev
  since is '-' without --since; import is same|changed|unknown; upstream is
  same|differs|missing|-; project_rev holds the subtree's own history: the
  upstream ref if set, else the last imported commit.

Discovery walks HEAD's whole history once, then is cached in
<git-dir>/git-subtree-status.cache, keyed by the HEAD commit.
";

#[derive(Default)]
struct Opts {
    dir: Option<PathBuf>,
    since: Option<String>,
    filter: Option<String>,
    all: bool,
    porcelain: bool,
    exit_code: bool,
    no_status: bool,
    owner_of: Option<String>,
}

fn parse_args() -> Opts {
    let mut o = Opts::default();
    let mut args = std::env::args().skip(1);
    while let Some(a) = args.next() {
        let mut value = |name: &str| args.next().unwrap_or_else(|| die(&format!("{name} needs a value")));
        match a.as_str() {
            "-C" => o.dir = Some(PathBuf::from(value("-C"))),
            "--since" => o.since = Some(value("--since")),
            "--filter" => o.filter = Some(value("--filter")),
            "--all" => o.all = true,
            "--porcelain" => o.porcelain = true,
            "--exit-code" => o.exit_code = true,
            "--no-status" => o.no_status = true,
            "--owner-of" => o.owner_of = Some(value("--owner-of")),
            "-h" | "--help" => {
                print!("{USAGE}");
                exit(0)
            }
            "-V" | "--version" => {
                println!("git-subtree-status {}", env!("CARGO_PKG_VERSION"));
                exit(0)
            }
            _ => die(&format!("unknown argument: {a}\n\n{USAGE}")),
        }
    }
    o
}

fn die(msg: &str) -> ! {
    eprintln!("git-subtree-status: {msg}");
    exit(2)
}

/// The newest import of one prefix, and what it brought in.
struct Import {
    /// The prefix's tree right after the import.
    tree: ObjectId,
    /// Where the subtree's own history can be read: the split commit for a
    /// full-history import, the squash commit itself for `--squash`.
    project_rev: ObjectId,
}

struct Row {
    prefix: String,
    uncommitted: Option<usize>,
    since: Option<usize>,
    import: &'static str,
    import_files: usize,
    upstream_ref: Option<String>,
    upstream: &'static str,
    upstream_files: usize,
    project_rev: String,
}

impl Row {
    /// With an upstream ref configured, drift is judged against it alone: work
    /// sent upstream with `git subtree push` leaves no trailer, so the "since
    /// the last import" difference keeps growing after every push.
    fn changed(&self) -> bool {
        let drift = if self.upstream_ref.is_some() {
            matches!(self.upstream, "differs" | "missing")
        } else {
            self.import == "changed"
        };
        self.uncommitted.unwrap_or(0) > 0 || self.since.unwrap_or(0) > 0 || drift
    }
}

/// Walk HEAD once and return, per `git-subtree-dir`, its newest import.
///
/// A full-history import's trailers sit on a mainline commit that contains the
/// prefix. A `--squash` import's trailers sit on the squash commit, whose own
/// tree is the imported content at the project root.
fn discover(repo: &gix::Repository) -> Res<HashMap<String, Import>> {
    let mut newest: HashMap<String, (i64, Import)> = HashMap::new();
    for info in repo.head_id()?.ancestors().all()? {
        let commit = info?.object()?;
        if commit.message_raw_sloppy().find(b"git-subtree-dir:").is_none() {
            continue;
        }
        let message = commit.message()?;
        let Some(body) = message.body() else { continue };
        let (mut dirs, mut split) = (Vec::new(), None);
        for t in body.trailers() {
            if t.token.eq_ignore_ascii_case(b"git-subtree-dir") {
                let d = t.value.to_str_lossy().trim().trim_end_matches('/').to_string();
                if !d.is_empty() {
                    dirs.push(d);
                }
            } else if t.token.eq_ignore_ascii_case(b"git-subtree-split") {
                split = ObjectId::from_hex(t.value.trim()).ok();
            }
        }
        let time = commit.time()?.seconds;
        let tree = commit.tree()?;
        for dir in dirs {
            if newest.get(&dir).is_some_and(|(t, _)| *t >= time) {
                continue;
            }
            let import = match tree.lookup_entry_by_path(&dir)? {
                Some(e) if e.mode().is_tree() => Import {
                    tree: e.object_id(),
                    project_rev: split.filter(|s| repo.has_object(s)).unwrap_or(commit.id),
                },
                // No prefix in the commit: a --squash commit, content at its root.
                _ => Import { tree: tree.id, project_rev: commit.id },
            };
            newest.insert(dir, (time, import));
        }
    }
    Ok(newest.into_iter().map(|(d, (_, i))| (d, i)).collect())
}

const CACHE_FILE: &str = "git-subtree-status.cache";

/// `discover`, cached on disk per HEAD commit: the walk reads every commit, the
/// cache file is one line per subtree.  A stale or unreadable cache is ignored.
fn discover_cached(repo: &gix::Repository) -> Res<HashMap<String, Import>> {
    let head = repo.head_id()?.detach();
    let path = repo.git_dir().join(CACHE_FILE);
    if let Ok(text) = std::fs::read_to_string(&path) {
        let mut lines = text.lines();
        if lines.next() == Some(&format!("v1 {head}")) {
            let parsed: Option<HashMap<String, Import>> = lines
                .map(|l| {
                    let mut f = l.split('\t');
                    let (p, t, r) = (f.next()?, f.next()?, f.next()?);
                    Some((p.to_string(), Import {
                        tree: ObjectId::from_hex(t.as_bytes()).ok()?,
                        project_rev: ObjectId::from_hex(r.as_bytes()).ok()?,
                    }))
                })
                .collect();
            if let Some(map) = parsed {
                return Ok(map);
            }
        }
    }
    let found = discover(repo)?;
    let mut text = format!("v1 {head}\n");
    for (p, i) in &found {
        text.push_str(&format!("{p}\t{}\t{}\n", i.tree, i.project_rev));
    }
    // Best effort: a read-only .git only costs the next run another walk.
    let tmp = path.with_extension("tmp");
    if std::fs::write(&tmp, text).is_ok() {
        let _ = std::fs::rename(&tmp, &path);
    }
    Ok(found)
}

/// `subtree.<prefix>.upstream` entries from git config.
fn upstreams(repo: &gix::Repository) -> HashMap<String, String> {
    let config = repo.config_snapshot();
    let mut out = HashMap::new();
    if let Some(sections) = config.plumbing().sections_by_name("subtree") {
        for s in sections {
            let (Some(name), Some(value)) = (s.header().subsection_name(), s.value("upstream")) else {
                continue;
            };
            out.insert(
                name.to_str_lossy().trim_end_matches('/').to_string(),
                value.to_str_lossy().trim().to_string(),
            );
        }
    }
    out
}

/// The tree of `spec`, or None if it does not resolve.
fn tree_of(repo: &gix::Repository, spec: &str) -> Option<ObjectId> {
    let id = repo.rev_parse_single(spec).ok()?;
    Some(id.object().ok()?.peel_to_tree().ok()?.id)
}

/// Paths of files (not directories) that differ between two trees.
fn changed_paths(repo: &gix::Repository, old: ObjectId, new: ObjectId) -> Res<Vec<String>> {
    let (old, new) = (repo.find_tree(old)?, repo.find_tree(new)?);
    let mut opts = gix::diff::Options::default();
    opts.track_path().track_rewrites(None);
    Ok(repo
        .diff_tree_to_tree(&old, &new, opts)?
        .iter()
        .filter(|c| !c.entry_mode().is_tree())
        .map(|c| c.location().to_str_lossy().into_owned())
        .collect())
}

/// Paths `git status` would list: staged, unstaged and untracked (collapsed).
fn status_paths(repo: &gix::Repository) -> Res<Vec<String>> {
    let mut out = Vec::new();
    let iter = repo
        .status(gix::progress::Discard)?
        .untracked_files(gix::status::UntrackedFiles::Collapsed)
        .into_iter(Vec::<BString>::new())?;
    for item in iter {
        out.push(item?.location().to_str_lossy().trim_end_matches('/').to_string());
    }
    Ok(out)
}

/// The commit `--since` names: a revision if it resolves, else the newest
/// first-parent commit of HEAD at or before a date.
fn since_commit(repo: &gix::Repository, since: &str) -> Res<ObjectId> {
    if let Ok(id) = repo.rev_parse_single(since) {
        if let Ok(c) = id.object()?.peel_to_commit() {
            return Ok(c.id);
        }
    }
    let at = gix::date::parse(since, Some(gix::date::Zoned::now()))
        .map_err(|_| format!("--since: '{since}' is neither a revision nor a date"))?;
    for info in repo.head_id()?.ancestors().first_parent_only().all()? {
        let commit = info?.object()?;
        if commit.time()?.seconds <= at.seconds {
            return Ok(commit.id);
        }
    }
    Err(format!("--since: no commit at or before '{since}'").into())
}

/// The longest prefix that owns `path`.
fn owner<'a>(path: &str, prefixes: &'a [String]) -> Option<&'a String> {
    prefixes
        .iter()
        .filter(|p| path == p.as_str() || path.strip_prefix(p.as_str()).is_some_and(|r| r.starts_with('/')))
        .max_by_key(|p| p.len())
}

fn count_by_owner(paths: &[String], prefixes: &[String]) -> HashMap<String, usize> {
    let mut counts = HashMap::new();
    for p in paths {
        if let Some(o) = owner(p, prefixes) {
            *counts.entry(o.clone()).or_insert(0) += 1;
        }
    }
    counts
}

fn run(o: &Opts) -> Res<Vec<Row>> {
    let repo = gix::discover(o.dir.as_deref().unwrap_or(Path::new(".")))?;
    let head_tree = repo.head_commit()?.tree()?;

    let mut found: Vec<(String, Import)> = discover_cached(&repo)?.into_iter().collect();
    found.sort_by(|a, b| a.0.cmp(&b.0));
    // Keep only subtrees still present at HEAD, with their current tree.
    let mut present = Vec::new();
    for (prefix, import) in found {
        if o.filter.as_deref().is_some_and(|f| !prefix.contains(f)) {
            continue;
        }
        if let Some(e) = head_tree.lookup_entry_by_path(&prefix)? {
            if e.mode().is_tree() {
                let head = e.object_id();
                present.push((prefix, import, head));
            }
        }
    }
    let prefixes: Vec<String> = present.iter().map(|(p, ..)| p.clone()).collect();

    let uncommitted = if o.no_status {
        None
    } else {
        Some(count_by_owner(&status_paths(&repo)?, &prefixes))
    };
    let since = match &o.since {
        Some(s) => {
            let base = since_commit(&repo, s)?;
            let base_tree = repo.find_commit(base)?.tree()?.id;
            Some(count_by_owner(&changed_paths(&repo, base_tree, head_tree.id)?, &prefixes))
        }
        None => None,
    };
    let ups = upstreams(&repo);

    let mut rows = Vec::new();
    for (prefix, import, head) in &present {
        let (imp, import_files) = if import.tree == *head {
            ("same", 0)
        } else {
            ("changed", changed_paths(&repo, import.tree, *head)?.len())
        };
        let upstream_ref = ups.get(prefix).cloned();
        let (upstream, upstream_files) = match &upstream_ref {
            None => ("-", 0),
            Some(r) => match tree_of(&repo, r) {
                None => ("missing", 0),
                Some(t) if t == *head => ("same", 0),
                Some(t) => ("differs", changed_paths(&repo, t, *head)?.len()),
            },
        };
        rows.push(Row {
            prefix: prefix.clone(),
            uncommitted: uncommitted.as_ref().map(|m| m.get(prefix).copied().unwrap_or(0)),
            since: since.as_ref().map(|m| m.get(prefix).copied().unwrap_or(0)),
            import: imp,
            import_files,
            project_rev: upstream_ref.clone().unwrap_or_else(|| import.project_rev.to_string()),
            upstream_ref,
            upstream,
            upstream_files,
        });
    }
    Ok(rows)
}

/// Prefixes of the subtree(s) commit `rev` belongs to.
///
/// An umbrella commit touches paths under a prefix, so its own diff answers.
/// An imported project commit has project-relative paths; it belongs to every
/// subtree whose own history (upstream ref, else last import) contains it.
/// A project commit only on another branch (say UAT when the mainline is
/// hg-config) is in neither, so it gets no owner.
fn owner_of(repo: &gix::Repository, rev: &str) -> Res<Vec<String>> {
    let commit = repo.rev_parse_single(rev)?.object()?.peel_to_commit()?;
    let found = discover_cached(repo)?;
    let mut prefixes: Vec<String> = found.keys().cloned().collect();
    prefixes.sort();

    let tree = commit.tree()?.id;
    let parent_tree = match commit.parent_ids().next() {
        Some(p) => p.object()?.peel_to_commit()?.tree()?.id,
        None => repo.empty_tree().id,
    };
    let mut owners: Vec<String> = count_by_owner(&changed_paths(repo, parent_tree, tree)?, &prefixes)
        .into_keys()
        .collect();
    // On HEAD's first-parent chain it is an umbrella commit: its paths are the
    // whole answer.  Imported project commits only ever arrive as second parents.
    let on_mainline = {
        let mut hit = false;
        for info in repo.head_id()?.ancestors().first_parent_only().all()? {
            if info?.id == commit.id {
                hit = true;
                break;
            }
        }
        hit
    };
    if owners.is_empty() && !on_mainline {
        let ups = upstreams(repo);
        for p in &prefixes {
            let tip = match ups.get(p) {
                Some(r) => match repo.rev_parse_single(r.as_str()) {
                    Ok(id) => id.detach(),
                    Err(_) => continue,
                },
                None => found[p].project_rev,
            };
            if repo.merge_base(commit.id, tip)?.is_some_and(|b| b == commit.id) {
                owners.push(p.clone());
            }
        }
    }
    owners.sort();
    Ok(owners)
}

fn print_porcelain(out: &mut impl Write, rows: &[&Row]) -> std::io::Result<()> {
    writeln!(out, "# git-subtree-status v1")?;
    for r in rows {
        writeln!(
            out,
            "{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}",
            r.prefix,
            r.uncommitted.map_or_else(|| "-".to_string(), |n| n.to_string()),
            r.since.map_or_else(|| "-".to_string(), |n| n.to_string()),
            r.import,
            r.import_files,
            r.upstream_ref.as_deref().unwrap_or("-"),
            r.upstream,
            r.upstream_files,
            r.project_rev
        )?;
    }
    Ok(())
}

fn print_table(out: &mut impl Write, rows: &[&Row], with_since: bool) -> std::io::Result<()> {
    if rows.is_empty() {
        return Ok(());
    }
    let w = rows.iter().map(|r| r.prefix.len()).max().unwrap_or(0).max(6);
    write!(out, "{:<w$}  {:>11}", "prefix", "uncommitted")?;
    if with_since {
        write!(out, "  {:>5}", "since")?;
    }
    writeln!(out, "  {:<15} upstream", "import")?;
    for r in rows {
        let u = r.uncommitted.map_or_else(|| "-".to_string(), |n| n.to_string());
        write!(out, "{:<w$}  {:>11}", r.prefix, u)?;
        if with_since {
            write!(out, "  {:>5}", r.since.unwrap_or(0))?;
        }
        let import = match r.import {
            "changed" => format!("changed ({})", r.import_files),
            s => s.to_string(),
        };
        let upstream = match (&r.upstream_ref, r.upstream) {
            (None, _) => "-".to_string(),
            (Some(u), "differs") => format!("differs ({}) {u}", r.upstream_files),
            (Some(u), s) => format!("{s} {u}"),
        };
        writeln!(out, "  {import:<15} {upstream}")?;
    }
    Ok(())
}

fn main() {
    let o = parse_args();
    if let Some(rev) = &o.owner_of {
        let owners = gix::discover(o.dir.as_deref().unwrap_or(Path::new(".")))
            .map_err(Into::into)
            .and_then(|repo| owner_of(&repo, rev))
            .unwrap_or_else(|e: Box<dyn std::error::Error + Send + Sync>| die(&e.to_string()));
        for p in owners {
            println!("{p}");
        }
        return;
    }
    let rows = run(&o).unwrap_or_else(|e| die(&e.to_string()));
    let listed: Vec<&Row> = rows.iter().filter(|r| o.all || r.changed()).collect();
    let changed = rows.iter().filter(|r| r.changed()).count();
    let mut out = std::io::stdout().lock();
    let written = if o.porcelain {
        print_porcelain(&mut out, &listed)
    } else {
        print_table(&mut out, &listed, o.since.is_some()).and_then(|()| {
            let since = o.since.as_deref().map(|s| format!(" (since: {s})")).unwrap_or_default();
            writeln!(out, "{} subtree(s), {changed} with a change{since}", rows.len())
        })
    };
    if written.is_err() {
        exit(2); // stdout closed, e.g. piped into `head`
    }
    if o.exit_code && changed > 0 {
        exit(1);
    }
}

#[cfg(test)]
mod tests {
    use super::owner;

    #[test]
    fn longest_prefix_wins_and_siblings_do_not_match() {
        let p = vec!["repos/a".to_string(), "repos/a/b".to_string(), "repos/ab".to_string()];
        assert_eq!(owner("repos/a/b/x.rs", &p), Some(&p[1]));
        assert_eq!(owner("repos/a/x.rs", &p), Some(&p[0]));
        assert_eq!(owner("repos/ab/x.rs", &p), Some(&p[2]));
        assert_eq!(owner("repos/a", &p), Some(&p[0]));
        assert_eq!(owner("repos/abc/x.rs", &p), None);
    }
}
