//! git-nested-status — the independent clones nested inside a repository, and their state.
//!
//! An umbrella repository (such as a product checkout whose `repos/*` are separate clones,
//! gitignored by the umbrella) says nothing about those clones in its own `git status`.
//! This tool finds them — a subdirectory with its own `.git` entry — and reports, per clone:
//!
//! * branch (or detached HEAD), and the HEAD commit
//! * the upstream tracking ref, with how many commits the clone is ahead of and behind it
//! * the staged, unstaged and untracked paths (untracked directories collapsed, as `git status`)
//!
//! Read-only and offline: it reads every repository with gix, never runs `git`, never fetches
//! and never writes.

use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::exit;
use std::sync::Mutex;

use gix::bstr::{BString, ByteSlice};

type Res<T> = Result<T, Box<dyn std::error::Error + Send + Sync + 'static>>;

const USAGE: &str = "\
usage: git-nested-status [options]

  -C <dir>        run in <dir> (the umbrella repository) instead of the current directory
  --depth <n>     look <n> directory levels down for clones (0 = none); overrides the
                  git config nested.depth, whose default is 2
  --files         after each clone's row, list its uncommitted paths (porcelain: F lines)
  --all           list every clone in the table, not only those with a change
  --porcelain     tab-separated output for scripts (format below); lists every clone
  --exit-code     exit 1 if any clone has a change
  -h, --help      this help
  -V, --version   print the version

A clone is a subdirectory with its own .git (directory or file). It is opened at that
path, never found by walking upward, and nothing inside a clone is searched. Where to look
is read from the umbrella's git config:
  git config nested.depth <n>          levels below the toplevel (default 2: */ and */*/)
  git config --add nested.path <dir>   only the immediate children of <dir> (repeatable)
A clone has a change when it has uncommitted paths, is ahead of or behind its upstream,
or its HEAD is detached. A clone with no upstream is not a change by itself.

--porcelain v1: a '# git-nested-status v1' line, then per clone
  R  path  branch  head  upstream  ahead  behind  staged  unstaged  untracked
    branch is '-' when HEAD is detached; head is the abbreviated commit, '-' when unborn;
    upstream is the tracking ref ('-' when none); ahead/behind are '-' without an upstream
    or when its ref is gone
  F  kind  file          (with --files; kind is staged, unstaged or untracked)
";

#[derive(Default)]
struct Opts {
    dir: Option<PathBuf>,
    depth: Option<usize>,
    files: bool,
    all: bool,
    porcelain: bool,
    exit_code: bool,
}

fn parse_args() -> Opts {
    let mut o = Opts::default();
    let mut args = std::env::args().skip(1);
    while let Some(a) = args.next() {
        let mut value = |name: &str| args.next().unwrap_or_else(|| die(&format!("{name} needs a value")));
        match a.as_str() {
            "-C" => o.dir = Some(PathBuf::from(value("-C"))),
            "--depth" => {
                let v = value("--depth");
                o.depth = Some(v.parse().unwrap_or_else(|_| die(&format!("--depth: '{v}' is not a number"))));
            }
            "--files" => o.files = true,
            "--all" => o.all = true,
            "--porcelain" => o.porcelain = true,
            "--exit-code" => o.exit_code = true,
            "-h" | "--help" => {
                print!("{USAGE}");
                exit(0)
            }
            "-V" | "--version" => {
                println!("git-nested-status {}", env!("CARGO_PKG_VERSION"));
                exit(0)
            }
            _ => die(&format!("unknown argument: {a}\n\n{USAGE}")),
        }
    }
    o
}

fn die(msg: &str) -> ! {
    eprintln!("git-nested-status: {msg}");
    exit(2)
}

// ---- discovery ----------------------------------------------------------

/// Where clones are looked for, as resolved from the flags and the umbrella's config.
#[derive(Debug, PartialEq, Eq)]
enum Scope {
    /// Every subdirectory down to this many levels below the toplevel.
    Depth(usize),
    /// Only the immediate children of these directories (relative to the toplevel).
    Paths(Vec<PathBuf>),
}

/// `--depth` wins; else `nested.path` entries; else `nested.depth`, default 2.
/// A depth of 0, from either source, means "look nowhere" even with paths configured.
fn scope(flag_depth: Option<usize>, cfg_depth: Option<i64>, cfg_paths: Vec<String>) -> Scope {
    match (flag_depth, cfg_depth) {
        (Some(0), _) | (None, Some(0)) => return Scope::Depth(0),
        (Some(n), _) => return Scope::Depth(n),
        _ => {}
    }
    if !cfg_paths.is_empty() {
        return Scope::Paths(cfg_paths.into_iter().map(PathBuf::from).collect());
    }
    Scope::Depth(cfg_depth.and_then(|d| usize::try_from(d).ok()).unwrap_or(2))
}

/// A directory is a clone iff it has a `.git` entry — a directory, or the `gitdir:` file of a
/// linked worktree or submodule. Nothing inside a clone is ever searched.
fn is_clone(dir: &Path) -> bool {
    dir.join(".git").exists()
}

/// Clones under `root`, as paths relative to it, sorted. Symlinked directories and `.git`
/// entries are skipped; unreadable directories are skipped silently.
fn discover(root: &Path, scope: &Scope) -> Vec<PathBuf> {
    let mut out = Vec::new();
    match scope {
        Scope::Depth(n) => walk(root, Path::new(""), *n, &mut out),
        Scope::Paths(paths) => {
            for p in paths {
                walk(&root.join(p), p, 1, &mut out);
            }
        }
    }
    out.sort();
    out.dedup();
    out
}

fn walk(dir: &Path, rel: &Path, levels: usize, out: &mut Vec<PathBuf>) {
    if levels == 0 {
        return;
    }
    let Ok(entries) = std::fs::read_dir(dir) else { return };
    for entry in entries.flatten() {
        let name = entry.file_name();
        if name == ".git" {
            continue;
        }
        // symlink_metadata: a symlinked directory is skipped, it may point anywhere.
        let Ok(meta) = entry.path().symlink_metadata() else { continue };
        if !meta.is_dir() {
            continue;
        }
        let path = entry.path();
        let rel = rel.join(&name);
        if is_clone(&path) {
            out.push(rel);
        } else {
            walk(&path, &rel, levels - 1, out);
        }
    }
}

// ---- inspection ---------------------------------------------------------

#[derive(Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Debug)]
enum Kind {
    Staged,
    Unstaged,
    Untracked,
}

impl Kind {
    fn name(self) -> &'static str {
        match self {
            Kind::Staged => "staged",
            Kind::Unstaged => "unstaged",
            Kind::Untracked => "untracked",
        }
    }
}

struct Row {
    path: String,
    /// Short branch name; None when HEAD is detached.
    branch: Option<String>,
    /// Abbreviated HEAD commit; None when the branch is unborn.
    head: Option<String>,
    /// Short tracking ref name (`origin/main`); None when the branch has no upstream.
    upstream: Option<String>,
    /// (ahead, behind) against the upstream; None without one, or when its ref is gone.
    ahead_behind: Option<(usize, usize)>,
    /// Uncommitted paths, sorted by path then kind.
    files: Vec<(Kind, String)>,
}

impl Row {
    fn count(&self, kind: Kind) -> usize {
        self.files.iter().filter(|(k, _)| *k == kind).count()
    }

    fn detached(&self) -> bool {
        self.branch.is_none()
    }

    /// Uncommitted paths, ahead or behind, or detached. No upstream is not a change.
    fn changed(&self) -> bool {
        !self.files.is_empty() || self.ahead_behind.is_some_and(|(a, b)| a > 0 || b > 0) || self.detached()
    }
}

/// Commits reachable from `tip` but not from `hide` (`git rev-list tip ^hide | wc -l`).
fn count_commits(repo: &gix::Repository, tip: gix::ObjectId, hide: gix::ObjectId) -> Res<usize> {
    let mut n = 0;
    for info in repo.rev_walk([tip]).with_hidden([hide]).all()? {
        info?;
        n += 1;
    }
    Ok(n)
}

/// Open the clone at `root/rel` (at that path, never discovering upward) and read its state.
fn inspect(root: &Path, rel: &Path) -> Res<Row> {
    // Default options, not `isolated()`: the global config and the XDG ignore file
    // (~/.config/git/ignore) must apply, or the untracked list disagrees with the
    // clone's own `git status` (seen 2026-10-14: `.claude` ignored globally).
    let repo = gix::open(root.join(rel))?;
    let head = repo.head()?;
    let head_id = head.id();
    let branch = if head.is_detached() {
        None
    } else {
        head.referent_name().map(|n| n.shorten().to_string())
    };
    let head_short = head_id.map(|id| id.shorten_or_id().to_string());
    let head_oid = head_id.map(|id| id.detach());

    let mut upstream = None;
    let mut ahead_behind = None;
    if let Some(name) = head.referent_name() {
        if let Some(Ok(full)) = repo.branch_remote_tracking_ref_name(name, gix::remote::Direction::Fetch) {
            upstream = Some(full.shorten().to_string());
            if let (Some(h), Ok(Some(mut r))) = (head_oid, repo.try_find_reference(full.as_ref())) {
                if let Ok(u) = r.peel_to_id() {
                    let u = u.detach();
                    ahead_behind = Some(if u == h {
                        (0, 0)
                    } else {
                        (count_commits(&repo, h, u)?, count_commits(&repo, u, h)?)
                    });
                }
            }
        }
    }

    let mut files = Vec::new();
    let iter = repo
        .status(gix::progress::Discard)?
        .untracked_files(gix::status::UntrackedFiles::Collapsed)
        .tree_index_track_renames(gix::status::tree_index::TrackRenames::Disabled)
        // Each clone is read on its own worker thread already; don't fan out further.
        .index_worktree_options_mut(|o| o.thread_limit = Some(1))
        .into_iter(Vec::<BString>::new())?;
    for item in iter {
        match item? {
            gix::status::Item::TreeIndex(change) => {
                files.push((Kind::Staged, change.location().to_str_lossy().into_owned()));
            }
            gix::status::Item::IndexWorktree(item) => {
                let kind = match item.summary() {
                    // A stat-only difference with identical content is not a change.
                    None => continue,
                    Some(gix::status::index_worktree::iter::Summary::Added) => Kind::Untracked,
                    Some(_) => Kind::Unstaged,
                };
                let path = item.rela_path().to_str_lossy().trim_end_matches('/').to_string();
                files.push((kind, path));
            }
        }
    }
    files.sort_by(|a, b| a.1.cmp(&b.1).then(a.0.cmp(&b.0)));
    files.dedup();

    Ok(Row {
        path: rel.to_string_lossy().into_owned(),
        branch,
        head: head_short,
        upstream,
        ahead_behind,
        files,
    })
}

/// Inspect every clone on a small pool of worker threads; rows come back sorted by path.
/// A clone that cannot be read is reported on stderr and left out.
fn inspect_all(root: &Path, rels: &[PathBuf]) -> Vec<Row> {
    let next = Mutex::new(0usize);
    let rows = Mutex::new(Vec::with_capacity(rels.len()));
    // gix's own status already runs producer threads per repository, so a modest pool is
    // enough to overlap the I/O without oversubscribing the machine.
    let workers = std::thread::available_parallelism().map_or(1, |n| n.get()).min(6).min(rels.len().max(1));
    std::thread::scope(|s| {
        for _ in 0..workers {
            s.spawn(|| {
                loop {
                    let i = {
                        let mut g = next.lock().unwrap();
                        let i = *g;
                        *g += 1;
                        i
                    };
                    let Some(rel) = rels.get(i) else { break };
                    match inspect(root, rel) {
                        Ok(row) => rows.lock().unwrap().push(row),
                        Err(e) => eprintln!("git-nested-status: {}: {e}", rel.display()),
                    }
                }
            });
        }
    });
    let mut rows = rows.into_inner().unwrap();
    rows.sort_by(|a, b| a.path.cmp(&b.path));
    rows
}

// ---- output -------------------------------------------------------------

fn dash<T: ToString>(v: &Option<T>) -> String {
    v.as_ref().map_or_else(|| "-".to_string(), ToString::to_string)
}

fn porcelain_row(r: &Row) -> String {
    let (ahead, behind) = match r.ahead_behind {
        Some((a, b)) => (a.to_string(), b.to_string()),
        None => ("-".to_string(), "-".to_string()),
    };
    format!(
        "R\t{}\t{}\t{}\t{}\t{ahead}\t{behind}\t{}\t{}\t{}",
        r.path,
        dash(&r.branch),
        dash(&r.head),
        dash(&r.upstream),
        r.count(Kind::Staged),
        r.count(Kind::Unstaged),
        r.count(Kind::Untracked),
    )
}

fn print_porcelain(out: &mut impl Write, rows: &[&Row], files: bool) -> std::io::Result<()> {
    writeln!(out, "# git-nested-status v1")?;
    for r in rows {
        writeln!(out, "{}", porcelain_row(r))?;
        if files {
            for (kind, path) in &r.files {
                writeln!(out, "F\t{}\t{path}", kind.name())?;
            }
        }
    }
    Ok(())
}

fn print_table(out: &mut impl Write, rows: &[&Row], files: bool) -> std::io::Result<()> {
    if rows.is_empty() {
        return Ok(());
    }
    let w = rows.iter().map(|r| r.path.len()).max().unwrap_or(0).max(4);
    let bw = rows.iter().map(|r| r.branch.as_deref().map_or(8, |b| b.len())).max().unwrap_or(0).max(6);
    writeln!(out, "{:<w$}  {:<bw$}  {:<24}  {:>6} {:>8} {:>9}", "path", "branch", "upstream", "staged", "unstaged", "untracked")?;
    for r in rows {
        let branch = r.branch.clone().unwrap_or_else(|| "detached".to_string());
        let upstream = match (&r.upstream, r.ahead_behind) {
            (None, _) => "-".to_string(),
            (Some(u), None) => format!("{u} (gone)"),
            (Some(u), Some((0, 0))) => u.clone(),
            (Some(u), Some((a, b))) => format!("{u} +{a} -{b}"),
        };
        writeln!(
            out,
            "{:<w$}  {:<bw$}  {:<24}  {:>6} {:>8} {:>9}",
            r.path,
            branch,
            upstream,
            r.count(Kind::Staged),
            r.count(Kind::Unstaged),
            r.count(Kind::Untracked)
        )?;
        if files {
            for (kind, path) in &r.files {
                writeln!(out, "    {:<9}  {path}", kind.name())?;
            }
        }
    }
    Ok(())
}

fn run(o: &Opts) -> Res<Vec<Row>> {
    let repo = gix::discover(o.dir.as_deref().unwrap_or(Path::new(".")))?;
    let root = repo.workdir().ok_or("the umbrella repository is bare")?.to_path_buf();
    let cfg = repo.config_snapshot();
    let cfg_depth = cfg.integer("nested.depth");
    let cfg_paths: Vec<String> = cfg
        .plumbing()
        .strings("nested.path")
        .unwrap_or_default()
        .iter()
        .map(|v| v.to_str_lossy().into_owned())
        .collect();
    drop(cfg);
    let scope = scope(o.depth, cfg_depth, cfg_paths);
    let clones = discover(&root, &scope);
    Ok(inspect_all(&root, &clones))
}

fn main() {
    let o = parse_args();
    let rows = run(&o).unwrap_or_else(|e| die(&e.to_string()));
    let changed = rows.iter().filter(|r| r.changed()).count();
    // Porcelain lists every clone: the Magit heading needs the total, and a script can
    // tell a changed row from the columns.  The table shows the changed ones unless --all.
    let listed: Vec<&Row> = rows.iter().filter(|r| o.all || o.porcelain || r.changed()).collect();
    let mut out = std::io::stdout().lock();
    let written = if o.porcelain {
        print_porcelain(&mut out, &listed, o.files)
    } else {
        print_table(&mut out, &listed, o.files)
            .and_then(|()| writeln!(out, "{} nested repo(s), {changed} with a change", rows.len()))
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
    use super::*;

    /// A fresh scratch directory per test (tests run in parallel in one process).
    fn scratch(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("git-nested-status-test-{}-{name}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    fn mk_clone(root: &Path, rel: &str) {
        std::fs::create_dir_all(root.join(rel).join(".git")).unwrap();
    }

    fn rels(found: &[PathBuf]) -> Vec<String> {
        found.iter().map(|p| p.to_string_lossy().into_owned()).collect()
    }

    #[test]
    fn depth_two_finds_children_and_grandchildren_only() {
        let root = scratch("depth2");
        mk_clone(&root, "a");
        mk_clone(&root, "repos/b");
        mk_clone(&root, "deep/x/y");
        std::fs::create_dir_all(root.join("repos/plain")).unwrap();
        std::fs::write(root.join("repos/plain/file"), "x").unwrap();
        std::fs::create_dir_all(root.join(".git/modules")).unwrap(); // the umbrella's own .git
        assert_eq!(rels(&discover(&root, &Scope::Depth(2))), ["a", "repos/b"]);
        assert_eq!(rels(&discover(&root, &Scope::Depth(3))), ["a", "deep/x/y", "repos/b"]);
        assert_eq!(rels(&discover(&root, &Scope::Depth(1))), ["a"]);
        assert!(discover(&root, &Scope::Depth(0)).is_empty());
    }

    #[test]
    fn a_clone_is_not_descended_into() {
        let root = scratch("nodescend");
        mk_clone(&root, "a");
        mk_clone(&root, "a/vendor/lib"); // a clone inside a clone: the outer one owns it
        assert_eq!(rels(&discover(&root, &Scope::Depth(5))), ["a"]);
    }

    #[test]
    fn a_dot_git_file_counts_as_a_clone() {
        let root = scratch("gitfile");
        std::fs::create_dir_all(root.join("repos/wt")).unwrap();
        std::fs::write(root.join("repos/wt/.git"), "gitdir: /elsewhere/.git/worktrees/wt\n").unwrap();
        assert_eq!(rels(&discover(&root, &Scope::Depth(2))), ["repos/wt"]);
    }

    #[test]
    fn paths_scan_their_immediate_children_only() {
        let root = scratch("paths");
        mk_clone(&root, "repos/b");
        mk_clone(&root, "deep/x/y");
        mk_clone(&root, "deep/z");
        let sc = Scope::Paths(vec![PathBuf::from("deep/x"), PathBuf::from("missing")]);
        assert_eq!(rels(&discover(&root, &sc)), ["deep/x/y"]);
        let sc = Scope::Paths(vec![PathBuf::from("deep")]);
        assert_eq!(rels(&discover(&root, &sc)), ["deep/z"]);
    }

    #[cfg(unix)]
    #[test]
    fn symlinked_directories_are_skipped() {
        let root = scratch("symlink");
        mk_clone(&root, "real");
        std::os::unix::fs::symlink(root.join("real"), root.join("link")).unwrap();
        assert_eq!(rels(&discover(&root, &Scope::Depth(2))), ["real"]);
    }

    #[test]
    fn scope_resolution() {
        assert_eq!(scope(None, None, vec![]), Scope::Depth(2));
        assert_eq!(scope(None, Some(3), vec![]), Scope::Depth(3));
        assert_eq!(scope(None, Some(0), vec!["repos".into()]), Scope::Depth(0));
        assert_eq!(scope(Some(0), Some(3), vec!["repos".into()]), Scope::Depth(0));
        assert_eq!(scope(Some(1), Some(3), vec!["repos".into()]), Scope::Depth(1));
        assert_eq!(scope(None, Some(3), vec!["repos".into()]), Scope::Paths(vec![PathBuf::from("repos")]));
        assert_eq!(scope(None, Some(-4), vec![]), Scope::Depth(2));
    }

    fn row(branch: Option<&str>, ab: Option<(usize, usize)>, files: Vec<(Kind, &str)>) -> Row {
        Row {
            path: "repos/x".into(),
            branch: branch.map(String::from),
            head: Some("abc1234".into()),
            upstream: ab.map(|_| "origin/main".to_string()),
            ahead_behind: ab,
            files: files.into_iter().map(|(k, p)| (k, p.to_string())).collect(),
        }
    }

    #[test]
    fn changed_means_files_ahead_behind_or_detached() {
        assert!(!row(Some("main"), Some((0, 0)), vec![]).changed());
        assert!(!row(Some("main"), None, vec![]).changed(), "no upstream alone is not a change");
        assert!(row(Some("main"), Some((1, 0)), vec![]).changed());
        assert!(row(Some("main"), Some((0, 2)), vec![]).changed());
        assert!(row(Some("main"), Some((0, 0)), vec![(Kind::Untracked, "f")]).changed());
        assert!(row(None, None, vec![]).changed(), "detached");
    }

    #[test]
    fn porcelain_row_format() {
        let r = row(Some("main"), Some((1, 0)), vec![(Kind::Unstaged, "a.txt"), (Kind::Untracked, "new")]);
        assert_eq!(porcelain_row(&r), "R\trepos/x\tmain\tabc1234\torigin/main\t1\t0\t0\t1\t1");
        let r = row(None, None, vec![]);
        assert_eq!(porcelain_row(&r), "R\trepos/x\t-\tabc1234\t-\t-\t-\t0\t0\t0");
        let mut out = Vec::new();
        print_porcelain(&mut out, &[&r], true).unwrap();
        assert_eq!(String::from_utf8(out).unwrap(), "# git-nested-status v1\nR\trepos/x\t-\tabc1234\t-\t-\t-\t0\t0\t0\n");
    }
}
