//! git-diff-hl — batch `vc-git` state and `diff-hl` hunk calculator.
//!
//! Given a list of repo-relative paths (via `--stdin [-z]` or positional arguments) or all
//! tracked paths (`--all` / default), computes each file's VC state (`up-to-date`, `edited`,
//! `added`, `removed`, `conflict`, `unregistered`, `ignored`) and 4-element `diff-hl` hunks
//! `(line inserts deletes type)` in one pass using `gix` and `imara-diff`.
//!
//! Read-only and offline: never runs `git` and never writes.

use std::io::{Read, Write};
use std::path::{Component, Path, PathBuf};
use std::process::exit;
use std::sync::Mutex;

use gix::bstr::{BStr, BString, ByteSlice};
use gix::diff::blob::pipeline::{Mode as PipelineMode, WorktreeRoots};
use gix::diff::blob::platform::prepare_diff::Operation;
use gix::diff::blob::{Diff, InternedInput, ResourceKind, sources};
use gix::index::entry::{Flags as IndexFlags, Mode as IndexMode, Stage, Stat};
use gix::index::fs::Metadata as FsMetadata;
use gix::object::tree::EntryKind;
use gix::prelude::FindExt;
use gix::worktree::stack::state::ignore::Source as IgnoreSource;

type Res<T> = Result<T, Box<dyn std::error::Error + Send + Sync + 'static>>;

const USAGE: &str = "\
usage: git-diff-hl [options] [<path>...]

  -C <dir>        run in <dir> instead of the current directory
  --porcelain     emit '# git-diff-hl v1' + tab-separated F/H records
  --sexp          emit a single Elisp alist for Emacs `read'
  --all           inspect all tracked paths in index/HEAD (not only changed)
  --stdin         read repo-relative paths from stdin (newline-delimited)
  -z              with --stdin, read NUL-delimited paths from stdin
  --exit-code     exit 1 if any inspected file has state != up-to-date
  -h, --help      this help
  -V, --version   print the version

--porcelain v1: a '# git-diff-hl v1' line, then per inspected path:
  F\t<state>\t<path>
  H\t<line>\t<inserts>\t<deletes>\t<type>
";

#[derive(Default)]
struct Opts {
    dir: Option<PathBuf>,
    porcelain: bool,
    sexp: bool,
    all: bool,
    stdin: bool,
    nul: bool,
    exit_code: bool,
    paths: Vec<String>,
}

fn parse_args_from<I>(args: I) -> Result<Opts, (i32, String)>
where
    I: IntoIterator<Item = String>,
{
    let mut o = Opts::default();
    let mut iter = args.into_iter();
    let mut positional_only = false;
    while let Some(a) = iter.next() {
        if positional_only {
            o.paths.push(a);
            continue;
        }
        match a.as_str() {
            "--" => positional_only = true,
            "-C" => {
                let v = iter
                    .next()
                    .ok_or_else(|| (2, "-C needs a value".to_string()))?;
                o.dir = Some(PathBuf::from(v));
            }
            "--porcelain" => o.porcelain = true,
            "--sexp" => o.sexp = true,
            "--all" => o.all = true,
            "--stdin" => o.stdin = true,
            "-z" => o.nul = true,
            "--exit-code" => o.exit_code = true,
            "-h" | "--help" => return Err((0, USAGE.to_string())),
            "-V" | "--version" => {
                return Err((0, format!("git-diff-hl {}\n", env!("CARGO_PKG_VERSION"))));
            }
            _ if a.starts_with('-') && a.len() > 1 => {
                return Err((2, format!("unknown argument: {a}\n\n{USAGE}")));
            }
            _ => o.paths.push(a),
        }
    }
    if o.porcelain && o.sexp {
        return Err((2, "--porcelain and --sexp are mutually exclusive".to_string()));
    }
    if o.nul && !o.stdin {
        return Err((2, "-z requires --stdin".to_string()));
    }
    if o.all && (o.stdin || !o.paths.is_empty()) {
        return Err((2, "--all cannot be combined with --stdin or positional paths".to_string()));
    }
    if o.stdin && !o.paths.is_empty() {
        return Err((2, "--stdin cannot be combined with positional paths".to_string()));
    }
    Ok(o)
}

fn die(msg: &str) -> ! {
    eprintln!("git-diff-hl: {msg}");
    exit(2)
}

// ---- data model ---------------------------------------------------------

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
enum VcState {
    UpToDate,
    Edited,
    Added,
    Removed,
    Conflict,
    Unregistered,
    Ignored,
}

impl VcState {
    fn as_str(self) -> &'static str {
        match self {
            VcState::UpToDate => "up-to-date",
            VcState::Edited => "edited",
            VcState::Added => "added",
            VcState::Removed => "removed",
            VcState::Conflict => "conflict",
            VcState::Unregistered => "unregistered",
            VcState::Ignored => "ignored",
        }
    }
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
enum HunkType {
    Insert,
    Delete,
    Change,
}

impl HunkType {
    fn as_str(self) -> &'static str {
        match self {
            HunkType::Insert => "insert",
            HunkType::Delete => "delete",
            HunkType::Change => "change",
        }
    }
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
struct DiffHunk {
    line: u32,
    inserts: u32,
    deletes: u32,
    kind: HunkType,
}

#[derive(Clone, Debug)]
struct FileResult {
    path: String,
    state: VcState,
    hunks: Vec<DiffHunk>,
}

// ---- path normalization & collection ------------------------------------

fn normalize_input_path(
    raw: &str,
    workdir: &Path,
    workdir_canon: Option<&Path>,
) -> Res<String> {
    let p = Path::new(raw);
    let rel_path: CowPath = if p.is_absolute() {
        if let Ok(stripped) = p.strip_prefix(workdir) {
            CowPath::Borrowed(stripped)
        } else if let Some(canon) = workdir_canon {
            if let Ok(stripped) = p.strip_prefix(canon) {
                CowPath::Borrowed(stripped)
            } else if let Some(parent) = p.parent().and_then(|d| std::fs::canonicalize(d).ok()) {
                let candidate = match p.file_name() {
                    Some(name) => parent.join(name),
                    None => parent,
                };
                if let Ok(stripped) = candidate.strip_prefix(canon) {
                    CowPath::Owned(stripped.to_path_buf())
                } else {
                    return Err(format!("path '{}' is outside repository workdir", raw).into());
                }
            } else {
                return Err(format!("path '{}' is outside repository workdir", raw).into());
            }
        } else {
            return Err(format!("path '{}' is outside repository workdir", raw).into());
        }
    } else {
        CowPath::Borrowed(p)
    };

    let mut parts: Vec<String> = Vec::new();
    for comp in rel_path.as_path().components() {
        match comp {
            Component::CurDir => {}
            Component::Normal(os) => {
                let s = os
                    .to_str()
                    .ok_or_else(|| format!("non-UTF-8 path component in '{raw}'"))?;
                parts.push(s.to_string());
            }
            Component::ParentDir | Component::RootDir | Component::Prefix(_) => {
                return Err(format!("invalid path '{raw}'").into());
            }
        }
    }
    if parts.is_empty() {
        return Err(format!("empty path '{raw}'").into());
    }
    Ok(parts.join("/"))
}

enum CowPath<'a> {
    Borrowed(&'a Path),
    Owned(PathBuf),
}

impl<'a> CowPath<'a> {
    fn as_path(&self) -> &Path {
        match self {
            CowPath::Borrowed(p) => p,
            CowPath::Owned(p) => p.as_path(),
        }
    }
}

fn read_stdin_paths(nul: bool) -> Res<Vec<String>> {
    let mut buf = Vec::new();
    std::io::stdin().read_to_end(&mut buf)?;
    let mut out = Vec::new();
    if nul {
        for chunk in buf.split(|&b| b == 0) {
            if chunk.is_empty() {
                continue;
            }
            let s = std::str::from_utf8(chunk)
                .map_err(|_| "non-UTF-8 path on stdin")?;
            out.push(s.to_string());
        }
    } else {
        for line in buf.split(|&b| b == b'\n') {
            let line = line.strip_suffix(b"\r").unwrap_or(line);
            if line.is_empty() {
                continue;
            }
            let s = std::str::from_utf8(line)
                .map_err(|_| "non-UTF-8 path on stdin")?;
            out.push(s.to_string());
        }
    }
    Ok(out)
}

fn collect_tree_blobs(
    tree: &gix::Tree<'_>,
    prefix: &mut String,
    out: &mut Vec<String>,
) -> Res<()> {
    for entry in tree.iter() {
        let entry = entry?;
        let name = entry.filename().to_str_lossy();
        let saved_len = prefix.len();
        if !prefix.is_empty() {
            prefix.push('/');
        }
        prefix.push_str(&name);
        match entry.mode().kind() {
            EntryKind::Tree => {
                let subtree = entry.object()?.into_tree();
                collect_tree_blobs(&subtree, prefix, out)?;
            }
            EntryKind::Blob | EntryKind::BlobExecutable | EntryKind::Link => {
                out.push(prefix.clone());
            }
            EntryKind::Commit => {}
        }
        prefix.truncate(saved_len);
    }
    Ok(())
}

fn collect_tracked_paths(index: &gix::index::State, head_tree: &gix::Tree<'_>) -> Res<Vec<String>> {
    let mut paths = Vec::with_capacity(index.entries().len());
    for entry in index.entries() {
        if entry.mode.contains(IndexMode::DIR) || entry.mode.contains(IndexMode::COMMIT) {
            continue;
        }
        paths.push(entry.path(index).to_str_lossy().into_owned());
    }
    let mut prefix = String::new();
    collect_tree_blobs(head_tree, &mut prefix, &mut paths)?;
    paths.sort();
    paths.dedup();
    Ok(paths)
}

// ---- hunk conversion & diffing ------------------------------------------

fn hunks_from_slices(
    old: &[u8],
    new: &[u8],
    algorithm: gix::diff::blob::Algorithm,
) -> Vec<DiffHunk> {
    let input = InternedInput::new(sources::byte_lines(old), sources::byte_lines(new));
    let mut diff = Diff::compute(algorithm, &input);
    diff.postprocess_lines(&input);
    diff.hunks()
        .map(|h| {
            let inserts = h.after.len() as u32;
            let deletes = h.before.len() as u32;
            let kind = match (deletes, inserts) {
                (0, _) => HunkType::Insert,
                (_, 0) => HunkType::Delete,
                _ => HunkType::Change,
            };
            DiffHunk {
                line: h.after.start + 1,
                inserts,
                deletes,
                kind,
            }
        })
        .collect()
}

fn count_byte_lines(bytes: &[u8]) -> u32 {
    sources::byte_lines(bytes).count() as u32
}

// ---- index & HEAD inspection --------------------------------------------

struct IndexLookup<'a> {
    unconflicted: Option<&'a gix::index::Entry>,
    has_conflict: bool,
}

fn lookup_index<'a>(index: &'a gix::index::State, rela: &BStr) -> IndexLookup<'a> {
    let entries = index.entries();
    let Ok(pos) = entries.binary_search_by(|e| e.path(index).cmp(rela)) else {
        return IndexLookup {
            unconflicted: None,
            has_conflict: false,
        };
    };
    let mut start = pos;
    while start > 0 && entries[start - 1].path(index) == rela {
        start -= 1;
    }
    let mut end = pos + 1;
    while end < entries.len() && entries[end].path(index) == rela {
        end += 1;
    }
    let mut unconflicted = None;
    let mut has_conflict = false;
    for entry in &entries[start..end] {
        if entry.stage() == Stage::Unconflicted {
            unconflicted = Some(entry);
        } else {
            has_conflict = true;
        }
    }
    IndexLookup {
        unconflicted,
        has_conflict,
    }
}

fn entry_kind_from_index_mode(mode: IndexMode) -> Option<EntryKind> {
    if mode.contains(IndexMode::DIR) || mode.contains(IndexMode::COMMIT) {
        None
    } else if mode.contains(IndexMode::SYMLINK) {
        Some(EntryKind::Link)
    } else if mode.contains(IndexMode::FILE_EXECUTABLE) {
        Some(EntryKind::BlobExecutable)
    } else if mode.contains(IndexMode::FILE) {
        Some(EntryKind::Blob)
    } else {
        None
    }
}

fn lookup_head_entry(
    repo: &gix::Repository,
    head_tree: &gix::Tree<'_>,
    path_str: &str,
) -> Res<Option<(gix::ObjectId, EntryKind)>> {
    let mut comps = path_str
        .as_bytes()
        .split(|&b| b == b'/')
        .filter(|c| !c.is_empty());
    let Some(first) = comps.next() else {
        return Ok(None);
    };
    let (mut cur_oid, mut cur_kind) = match head_tree.find_entry(first) {
        Some(e) => (e.object_id(), e.mode().kind()),
        None => return Ok(None),
    };
    for comp in comps {
        if cur_kind != EntryKind::Tree {
            // Stop cleanly on Blob, BlobExecutable, Link, or Commit (gitlink) —
            // never attempt to read a gitlink OID as a tree in the parent ODB.
            return Ok(None);
        }
        let subtree = repo.find_tree(cur_oid)?;
        match subtree.find_entry(comp) {
            Some(e) => {
                cur_oid = e.object_id();
                cur_kind = e.mode().kind();
            }
            None => return Ok(None),
        }
    }
    Ok(Some((cur_oid, cur_kind)))
}

fn entry_kind_from_disk(md: &FsMetadata, fs_symlink: bool) -> EntryKind {
    if md.is_symlink() && fs_symlink {
        EntryKind::Link
    } else {
        EntryKind::Blob
    }
}

fn disk_metadata(workdir: &Path, rel: &str) -> Res<Option<FsMetadata>> {
    let abs = workdir.join(rel);
    match FsMetadata::from_path_no_follow(&abs) {
        Ok(md) => {
            if md.is_dir() {
                Ok(None)
            } else {
                Ok(Some(md))
            }
        }
        Err(e) => {
            // Treat missing file or non-directory parent component as absent on disk.
            if e.kind() == std::io::ErrorKind::NotFound
                || e.raw_os_error() == Some(libc_enotdir())
            {
                Ok(None)
            } else {
                Err(e.into())
            }
        }
    }
}

#[cfg(unix)]
const fn libc_enotdir() -> i32 {
    20 // ENOTDIR on Linux/Unix
}

#[cfg(not(unix))]
const fn libc_enotdir() -> i32 {
    -1
}

// ---- work items & parallel execution ------------------------------------

enum WorkAction {
    /// Diff optional HEAD object against optional worktree file.
    /// If `check_clean_against_head` is true (i.e. head_oid == index_oid and no mode change),
    /// matching bytes classify the file as `UpToDate` rather than `Edited`.
    DiffHeadVsWorktree {
        base_state: VcState,
        old: Option<(gix::ObjectId, EntryKind)>,
        new_worktree: Option<(gix::ObjectId, EntryKind)>,
        check_clean_against_head: bool,
    },
    /// File is absent from HEAD and present in index + on disk (`A ` vs `AM`).
    /// Compare `ToGit` worktree against `index_oid` (unless `stat_clean` already proved it).
    AddedOrModified {
        index_oid: gix::ObjectId,
        index_kind: EntryKind,
        worktree_kind: EntryKind,
        stat_clean: bool,
        intent_to_add: bool,
    },
}

struct WorkItem {
    slot: usize,
    rela_path: BString,
    action: WorkAction,
}

fn run_work_item(
    item: &WorkItem,
    workdir: &Path,
    objects: &gix::OdbHandle,
    platform_wt: &mut gix::diff::blob::Platform,
    platform_odb: &mut gix::diff::blob::Platform,
    null_id: gix::ObjectId,
    fs_symlink: bool,
) -> Res<(VcState, Vec<DiffHunk>)> {
    let rela = item.rela_path.as_bstr();
    let res = match &item.action {
        WorkAction::DiffHeadVsWorktree {
            base_state,
            old,
            new_worktree,
            check_clean_against_head,
        } => {
            match (old, new_worktree) {
                (None, None) => Ok((*base_state, Vec::new())),
                (Some((old_id, old_kind)), None) => {
                    platform_odb.set_resource(
                        *old_id,
                        *old_kind,
                        rela,
                        ResourceKind::OldOrSource,
                        objects,
                    )?;
                    platform_odb.set_resource(
                        null_id,
                        EntryKind::Blob,
                        rela,
                        ResourceKind::NewOrDestination,
                        objects,
                    )?;
                    let outcome = platform_odb.prepare_diff()?;
                    let hunks = match outcome.operation {
                        Operation::SourceOrDestinationIsBinary
                        | Operation::ExternalCommand { .. } => Vec::new(),
                        Operation::InternalDiff { algorithm } => {
                            let old_bytes = outcome.old.data.as_slice().unwrap_or_default();
                            hunks_from_slices(old_bytes, b"", algorithm)
                        }
                    };
                    platform_odb.clear_resource_cache_keep_allocation();
                    Ok((*base_state, hunks))
                }
                (old_opt, Some((idx_oid, wt_kind))) => {
                    let (old_id, old_kind) = old_opt.unwrap_or((null_id, EntryKind::Blob));
                    let safe_wt_kind = if *wt_kind == EntryKind::Link && !fs_symlink {
                        EntryKind::Blob
                    } else {
                        *wt_kind
                    };
                    platform_wt.set_resource(
                        old_id,
                        old_kind,
                        rela,
                        ResourceKind::OldOrSource,
                        objects,
                    )?;
                    platform_wt.set_resource(
                        *idx_oid,
                        safe_wt_kind,
                        rela,
                        ResourceKind::NewOrDestination,
                        objects,
                    )?;
                    let outcome = platform_wt.prepare_diff()?;
                    let (state, hunks) = match outcome.operation {
                        Operation::SourceOrDestinationIsBinary => {
                            if *check_clean_against_head {
                                let mut blob_buf = Vec::new();
                                let same = match (
                                    objects.find_blob(&old_id, &mut blob_buf),
                                    std::fs::read(workdir.join(rela.to_str_lossy().as_ref())),
                                ) {
                                    (Ok(blob), Ok(wt_bytes)) => blob.data == wt_bytes.as_slice(),
                                    _ => false,
                                };
                                if same {
                                    (VcState::UpToDate, Vec::new())
                                } else {
                                    (*base_state, Vec::new())
                                }
                            } else {
                                (*base_state, Vec::new())
                            }
                        }
                        Operation::ExternalCommand { .. } => (*base_state, Vec::new()),
                        Operation::InternalDiff { algorithm } => {
                            let old_bytes = outcome.old.data.as_slice().unwrap_or_default();
                            let new_bytes = outcome.new.data.as_slice().unwrap_or_default();
                            if *check_clean_against_head && old_bytes == new_bytes {
                                (VcState::UpToDate, Vec::new())
                            } else {
                                (*base_state, hunks_from_slices(old_bytes, new_bytes, algorithm))
                            }
                        }
                    };
                    platform_wt.clear_resource_cache_keep_allocation();
                    Ok((state, hunks))
                }
            }
        }
        WorkAction::AddedOrModified {
            index_oid,
            index_kind,
            worktree_kind,
            stat_clean,
            intent_to_add,
        } => {
            let safe_wt_kind = if *worktree_kind == EntryKind::Link && !fs_symlink {
                EntryKind::Blob
            } else {
                *worktree_kind
            };
            let old_id = if *stat_clean || *intent_to_add {
                null_id
            } else {
                *index_oid
            };
            let old_kind = if *stat_clean || *intent_to_add {
                EntryKind::Blob
            } else {
                *index_kind
            };
            platform_wt.set_resource(
                old_id,
                old_kind,
                rela,
                ResourceKind::OldOrSource,
                objects,
            )?;
            platform_wt.set_resource(
                *index_oid,
                safe_wt_kind,
                rela,
                ResourceKind::NewOrDestination,
                objects,
            )?;
            let outcome = platform_wt.prepare_diff()?;
            let result = match outcome.operation {
                Operation::SourceOrDestinationIsBinary | Operation::ExternalCommand { .. } => {
                    let state = if *stat_clean || *intent_to_add {
                        VcState::Added
                    } else {
                        let mut blob_buf = Vec::new();
                        let same = match (
                            objects.find_blob(index_oid, &mut blob_buf),
                            std::fs::read(workdir.join(rela.to_str_lossy().as_ref())),
                        ) {
                            (Ok(blob), Ok(wt_bytes)) => blob.data == wt_bytes.as_slice(),
                            _ => false,
                        };
                        if same {
                            VcState::Added
                        } else {
                            VcState::Edited
                        }
                    };
                    (state, Vec::new())
                }
                Operation::InternalDiff { algorithm } => {
                    let new_bytes = outcome.new.data.as_slice().unwrap_or_default();
                    let is_added = if *stat_clean || *intent_to_add {
                        true
                    } else {
                        let old_bytes = outcome.old.data.as_slice().unwrap_or_default();
                        old_bytes == new_bytes
                    };
                    if is_added {
                        let lines = count_byte_lines(new_bytes);
                        let hunks = if lines == 0 {
                            Vec::new()
                        } else {
                            vec![DiffHunk {
                                line: 1,
                                inserts: lines,
                                deletes: 0,
                                kind: HunkType::Insert,
                            }]
                        };
                        (VcState::Added, hunks)
                    } else {
                        (VcState::Edited, hunks_from_slices(b"", new_bytes, algorithm))
                    }
                }
            };
            platform_wt.clear_resource_cache_keep_allocation();
            Ok(result)
        }
    };
    res
}

fn inspect_repo(opts: &Opts) -> Res<Vec<FileResult>> {
    let dir = opts.dir.as_deref().unwrap_or(Path::new("."));
    let repo = gix::discover(dir)?;
    let workdir = repo
        .workdir()
        .ok_or("repository is bare (no working tree)")?
        .to_path_buf();
    let workdir_canon = std::fs::canonicalize(&workdir).ok();

    let head_tree_id = repo.head_tree_id_or_empty()?;
    let head_tree = repo.find_tree(head_tree_id)?;
    let index = repo.index_or_empty()?;
    let stat_opts = repo.stat_options()?;
    let fs_caps = repo.filesystem_options()?;
    let null_id = repo.object_hash().null();

    let explicit_paths = opts.stdin || !opts.paths.is_empty();
    let target_paths: Vec<String> = if opts.stdin {
        let raw = read_stdin_paths(opts.nul)?;
        raw.into_iter()
            .map(|p| normalize_input_path(&p, &workdir, workdir_canon.as_deref()))
            .collect::<Res<Vec<_>>>()?
    } else if !opts.paths.is_empty() {
        opts.paths
            .iter()
            .map(|p| normalize_input_path(p, &workdir, workdir_canon.as_deref()))
            .collect::<Res<Vec<_>>>()?
    } else {
        collect_tracked_paths(&index, &head_tree)?
    };

    let mut results: Vec<Option<FileResult>> = vec![None; target_paths.len()];
    let mut work_items: Vec<WorkItem> = Vec::new();
    let mut excludes: Option<gix::AttributeStack<'_>> = None;

    for (slot, path_str) in target_paths.iter().enumerate() {
        let rela_bstr: &BStr = path_str.as_bytes().as_bstr();
        let idx_lookup = lookup_index(&index, rela_bstr);

        let head_entry = lookup_head_entry(&repo, &head_tree, path_str)?;

        // Skip tree/submodule entries cleanly.
        if let Some((_, kind)) = head_entry
            && matches!(kind, EntryKind::Tree | EntryKind::Commit)
        {
            results[slot] = Some(FileResult {
                path: path_str.clone(),
                state: VcState::UpToDate,
                hunks: Vec::new(),
            });
            continue;
        }
        if let Some(idx) = idx_lookup.unconflicted
            && entry_kind_from_index_mode(idx.mode).is_none()
        {
            results[slot] = Some(FileResult {
                path: path_str.clone(),
                state: VcState::UpToDate,
                hunks: Vec::new(),
            });
            continue;
        }

        let on_disk = disk_metadata(&workdir, path_str)?;
        let head_blob = head_entry.filter(|(_, k)| !matches!(k, EntryKind::Tree | EntryKind::Commit));

        if idx_lookup.has_conflict {
            let wt = on_disk
                .as_ref()
                .map(|md| (null_id, entry_kind_from_disk(md, fs_caps.symlink)));
            work_items.push(WorkItem {
                slot,
                rela_path: BString::from(path_str.as_str()),
                action: WorkAction::DiffHeadVsWorktree {
                    base_state: VcState::Conflict,
                    old: head_blob,
                    new_worktree: wt,
                    check_clean_against_head: false,
                },
            });
            continue;
        }

        match (head_blob, idx_lookup.unconflicted, on_disk) {
            (None, None, None) => {
                results[slot] = Some(FileResult {
                    path: path_str.clone(),
                    state: VcState::UpToDate,
                    hunks: Vec::new(),
                });
            }
            (None, None, Some(_)) => {
                let stack = match &mut excludes {
                    Some(s) => s,
                    None => {
                        excludes = Some(repo.excludes(
                            &index,
                            None,
                            IgnoreSource::WorktreeThenIdMappingIfNotSkipped,
                        )?);
                        excludes.as_mut().unwrap()
                    }
                };
                let is_ignored = stack
                    .at_entry(rela_bstr, Some(IndexMode::FILE))?
                    .is_excluded();
                results[slot] = Some(FileResult {
                    path: path_str.clone(),
                    state: if is_ignored {
                        VcState::Ignored
                    } else {
                        VcState::Unregistered
                    },
                    hunks: Vec::new(),
                });
            }
            (None, Some(_idx), None) => {
                // "AD" -> removed
                results[slot] = Some(FileResult {
                    path: path_str.clone(),
                    state: VcState::Removed,
                    hunks: Vec::new(),
                });
            }
            (None, Some(idx), Some(md)) => {
                let idx_kind = entry_kind_from_index_mode(idx.mode).unwrap_or(EntryKind::Blob);
                let wt_kind = entry_kind_from_disk(&md, fs_caps.symlink);
                let intent_to_add = idx.flags.contains(IndexFlags::INTENT_TO_ADD);
                let mode_change =
                    idx.mode
                        .change_to_match_fs(&md, fs_caps.symlink, fs_caps.executable_bit);
                let assumed_or_skipped = idx
                    .flags
                    .intersects(IndexFlags::ASSUME_VALID | IndexFlags::SKIP_WORKTREE);
                let stat_clean = !intent_to_add
                    && mode_change.is_none()
                    && (assumed_or_skipped
                        || Stat::from_fs(&md).is_ok_and(|new_stat| {
                            new_stat.matches(&idx.stat, stat_opts)
                                && (!idx.id.is_empty_blob() || idx.stat.size == 0)
                                && !new_stat.is_racy(index.timestamp(), stat_opts)
                        }));
                work_items.push(WorkItem {
                    slot,
                    rela_path: BString::from(path_str.as_str()),
                    action: WorkAction::AddedOrModified {
                        index_oid: idx.id,
                        index_kind: idx_kind,
                        worktree_kind: wt_kind,
                        stat_clean,
                        intent_to_add,
                    },
                });
            }
            (Some(_), None, None) => {
                // "D " -> removed
                work_items.push(WorkItem {
                    slot,
                    rela_path: BString::from(path_str.as_str()),
                    action: WorkAction::DiffHeadVsWorktree {
                        base_state: VcState::Removed,
                        old: head_blob,
                        new_worktree: None,
                        check_clean_against_head: false,
                    },
                });
            }
            (Some(_), None, Some(_)) => {
                // "D " + "??" (e.g. `git rm --cached` with file on disk) -> unregistered
                results[slot] = Some(FileResult {
                    path: path_str.clone(),
                    state: VcState::Unregistered,
                    hunks: Vec::new(),
                });
            }
            (Some((h_oid, h_kind)), Some(idx), None) => {
                let assumed_or_skipped = idx
                    .flags
                    .intersects(IndexFlags::SKIP_WORKTREE | IndexFlags::ASSUME_VALID);
                let head_matches_index =
                    h_oid == idx.id && Some(h_kind) == entry_kind_from_index_mode(idx.mode);
                if assumed_or_skipped && head_matches_index {
                    results[slot] = Some(FileResult {
                        path: path_str.clone(),
                        state: VcState::UpToDate,
                        hunks: Vec::new(),
                    });
                } else {
                    // Deleted from worktree -> removed
                    work_items.push(WorkItem {
                        slot,
                        rela_path: BString::from(path_str.as_str()),
                        action: WorkAction::DiffHeadVsWorktree {
                            base_state: VcState::Removed,
                            old: head_blob,
                            new_worktree: None,
                            check_clean_against_head: false,
                        },
                    });
                }
            }
            (Some((h_oid, h_kind)), Some(idx), Some(md)) => {
                let idx_kind = entry_kind_from_index_mode(idx.mode).unwrap_or(EntryKind::Blob);
                let wt_kind = entry_kind_from_disk(&md, fs_caps.symlink);
                let mode_change =
                    idx.mode
                        .change_to_match_fs(&md, fs_caps.symlink, fs_caps.executable_bit);
                let assumed_or_skipped = idx
                    .flags
                    .intersects(IndexFlags::ASSUME_VALID | IndexFlags::SKIP_WORKTREE);
                let head_matches_index = h_oid == idx.id && h_kind == idx_kind;

                let is_fast_clean = head_matches_index
                    && mode_change.is_none()
                    && (assumed_or_skipped
                        || (!idx.flags.contains(IndexFlags::INTENT_TO_ADD)
                            && Stat::from_fs(&md).is_ok_and(|new_stat| {
                                new_stat.matches(&idx.stat, stat_opts)
                                    && (!idx.id.is_empty_blob() || idx.stat.size == 0)
                                    && !new_stat.is_racy(index.timestamp(), stat_opts)
                            })));

                if is_fast_clean {
                    results[slot] = Some(FileResult {
                        path: path_str.clone(),
                        state: VcState::UpToDate,
                        hunks: Vec::new(),
                    });
                } else {
                    let check_clean_against_head = head_matches_index && mode_change.is_none();
                    work_items.push(WorkItem {
                        slot,
                        rela_path: BString::from(path_str.as_str()),
                        action: WorkAction::DiffHeadVsWorktree {
                            base_state: VcState::Edited,
                            old: Some((h_oid, h_kind)),
                            new_worktree: Some((idx.id, wt_kind)),
                            check_clean_against_head,
                        },
                    });
                }
            }
        }
    }

    drop(excludes);
    drop(head_tree);
    drop(index);

    if work_items.len() == 1 {
        let item = &work_items[0];
        let mut platform_wt = repo.diff_resource_cache(
            PipelineMode::ToGit,
            WorktreeRoots {
                old_root: None,
                new_root: Some(workdir.clone()),
            },
        )?;
        let mut platform_odb = repo.diff_resource_cache(
            PipelineMode::ToGit,
            WorktreeRoots {
                old_root: None,
                new_root: None,
            },
        )?;
        let (state, hunks) = run_work_item(
            item,
            &workdir,
            &repo.objects,
            &mut platform_wt,
            &mut platform_odb,
            null_id,
            fs_caps.symlink,
        )?;
        results[item.slot] = Some(FileResult {
            path: target_paths[item.slot].clone(),
            state,
            hunks,
        });
    } else if work_items.len() > 1 {
        let ts_repo = repo.into_sync();
        let next = Mutex::new(0usize);
        let completed: Mutex<Vec<(usize, VcState, Vec<DiffHunk>)>> =
            Mutex::new(Vec::with_capacity(work_items.len()));
        let worker_err: Mutex<Option<String>> = Mutex::new(None);
        let workers = std::thread::available_parallelism()
            .map_or(1, |n| n.get())
            .min(6)
            .min(work_items.len());

        std::thread::scope(|s| {
            for _ in 0..workers {
                s.spawn(|| {
                    let local_repo = ts_repo.to_thread_local();
                    let mut platform_wt = match local_repo.diff_resource_cache(
                        PipelineMode::ToGit,
                        WorktreeRoots {
                            old_root: None,
                            new_root: Some(workdir.clone()),
                        },
                    ) {
                        Ok(p) => p,
                        Err(e) => {
                            *worker_err.lock().unwrap() = Some(e.to_string());
                            return;
                        }
                    };
                    let mut platform_odb = match local_repo.diff_resource_cache(
                        PipelineMode::ToGit,
                        WorktreeRoots {
                            old_root: None,
                            new_root: None,
                        },
                    ) {
                        Ok(p) => p,
                        Err(e) => {
                            *worker_err.lock().unwrap() = Some(e.to_string());
                            return;
                        }
                    };

                    loop {
                        let idx = {
                            let mut g = next.lock().unwrap();
                            let i = *g;
                            *g += 1;
                            i
                        };
                        let Some(item) = work_items.get(idx) else {
                            break;
                        };
                        match run_work_item(
                            item,
                            &workdir,
                            &local_repo.objects,
                            &mut platform_wt,
                            &mut platform_odb,
                            null_id,
                            fs_caps.symlink,
                        ) {
                            Ok((state, hunks)) => {
                                completed.lock().unwrap().push((item.slot, state, hunks));
                            }
                            Err(e) => {
                                *worker_err.lock().unwrap() =
                                    Some(format!("{}: {e}", target_paths[item.slot]));
                                break;
                            }
                        }
                    }
                });
            }
        });

        if let Some(err) = worker_err.into_inner().unwrap() {
            return Err(err.into());
        }
        for (slot, state, hunks) in completed.into_inner().unwrap() {
            results[slot] = Some(FileResult {
                path: target_paths[slot].clone(),
                state,
                hunks,
            });
        }
    }

    let all_results: Vec<FileResult> = results.into_iter().flatten().collect();
    if explicit_paths || opts.all {
        Ok(all_results)
    } else {
        Ok(all_results
            .into_iter()
            .filter(|r| r.state != VcState::UpToDate)
            .collect())
    }
}

// ---- output formatting --------------------------------------------------

fn print_porcelain(out: &mut impl Write, rows: &[FileResult]) -> std::io::Result<()> {
    writeln!(out, "# git-diff-hl v1")?;
    for r in rows {
        writeln!(out, "F\t{}\t{}", r.state.as_str(), r.path)?;
        for h in &r.hunks {
            writeln!(
                out,
                "H\t{}\t{}\t{}\t{}",
                h.line,
                h.inserts,
                h.deletes,
                h.kind.as_str()
            )?;
        }
    }
    Ok(())
}

fn write_elisp_string(out: &mut impl Write, s: &str) -> std::io::Result<()> {
    out.write_all(b"\"")?;
    for b in s.bytes() {
        match b {
            b'\\' => out.write_all(b"\\\\")?,
            b'"' => out.write_all(b"\\\"")?,
            b'\n' => out.write_all(b"\\n")?,
            b'\r' => out.write_all(b"\\r")?,
            b'\t' => out.write_all(b"\\t")?,
            0x00..=0x1f | 0x7f => write!(out, "\\{:03o}", b)?,
            _ => out.write_all(&[b])?,
        }
    }
    out.write_all(b"\"")
}

fn print_sexp(out: &mut impl Write, rows: &[FileResult]) -> std::io::Result<()> {
    out.write_all(b"(")?;
    for (i, r) in rows.iter().enumerate() {
        if i > 0 {
            out.write_all(b"\n ")?;
        }
        out.write_all(b"(")?;
        write_elisp_string(out, &r.path)?;
        write!(out, " {} ", r.state.as_str())?;
        if r.hunks.is_empty() {
            out.write_all(b"nil")?;
        } else {
            out.write_all(b"(")?;
            for (j, h) in r.hunks.iter().enumerate() {
                if j > 0 {
                    out.write_all(b" ")?;
                }
                write!(
                    out,
                    "({} {} {} {})",
                    h.line,
                    h.inserts,
                    h.deletes,
                    h.kind.as_str()
                )?;
            }
            out.write_all(b")")?;
        }
        out.write_all(b")")?;
    }
    writeln!(out, ")")
}

fn print_table(out: &mut impl Write, rows: &[FileResult]) -> std::io::Result<()> {
    if rows.is_empty() {
        return Ok(());
    }
    let w = rows.iter().map(|r| r.path.len()).max().unwrap_or(0).max(4);
    writeln!(out, "{:<12}  {:<w$}  hunks", "state", "path")?;
    for r in rows {
        writeln!(out, "{:<12}  {:<w$}  {}", r.state.as_str(), r.path, r.hunks.len())?;
    }
    Ok(())
}

fn main() {
    let opts = match parse_args_from(std::env::args().skip(1)) {
        Ok(o) => o,
        Err((0, msg)) => {
            print!("{msg}");
            exit(0);
        }
        Err((code, msg)) => {
            eprintln!("git-diff-hl: {msg}");
            exit(code);
        }
    };

    let rows = inspect_repo(&opts).unwrap_or_else(|e| die(&e.to_string()));
    let has_changes = rows.iter().any(|r| r.state != VcState::UpToDate);

    let mut out = std::io::stdout().lock();
    let written = if opts.porcelain {
        print_porcelain(&mut out, &rows)
    } else if opts.sexp {
        print_sexp(&mut out, &rows)
    } else {
        print_table(&mut out, &rows)
    };
    if written.is_err() {
        exit(2);
    }
    if opts.exit_code && has_changes {
        exit(1);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use gix::diff::blob::Algorithm;
    use std::process::Command;
    use std::sync::atomic::{AtomicUsize, Ordering};

    static SCRATCH_COUNTER: AtomicUsize = AtomicUsize::new(0);

    struct TempRepo {
        dir: PathBuf,
    }

    impl TempRepo {
        fn new(name: &str) -> Self {
            let n = SCRATCH_COUNTER.fetch_add(1, Ordering::Relaxed);
            let dir = std::env::temp_dir().join(format!(
                "git-diff-hl-test-{}-{}-{name}",
                std::process::id(),
                n
            ));
            let _ = std::fs::remove_dir_all(&dir);
            std::fs::create_dir_all(&dir).unwrap();
            let repo = Self { dir };
            repo.git(&["init", "-q"]);
            repo.git(&["config", "user.name", "Test"]);
            repo.git(&["config", "user.email", "test@example.com"]);
            repo
        }

        fn git(&self, args: &[&str]) -> String {
            let out = Command::new("git")
                .arg("-C")
                .arg(&self.dir)
                .args(args)
                .output()
                .expect("git command failed to spawn");
            if !out.status.success() {
                panic!(
                    "git {:?} failed: {}",
                    args,
                    String::from_utf8_lossy(&out.stderr)
                );
            }
            String::from_utf8_lossy(&out.stdout).into_owned()
        }

        fn write(&self, rel: &str, bytes: &[u8]) {
            let path = self.dir.join(rel);
            if let Some(p) = path.parent() {
                std::fs::create_dir_all(p).unwrap();
            }
            std::fs::write(path, bytes).unwrap();
        }

        fn commit_all(&self, msg: &str) {
            self.git(&["add", "-A"]);
            self.git(&["commit", "-q", "-m", msg]);
        }

        fn inspect_paths(&self, paths: &[&str]) -> Vec<FileResult> {
            let opts = Opts {
                dir: Some(self.dir.clone()),
                paths: paths.iter().map(|s| s.to_string()).collect(),
                ..Default::default()
            };
            inspect_repo(&opts).unwrap()
        }

        fn inspect_all(&self) -> Vec<FileResult> {
            let opts = Opts {
                dir: Some(self.dir.clone()),
                all: true,
                ..Default::default()
            };
            inspect_repo(&opts).unwrap()
        }
    }

    impl Drop for TempRepo {
        fn drop(&mut self) {
            let _ = std::fs::remove_dir_all(&self.dir);
        }
    }

    #[test]
    fn hunk_tuple_insert_bof_mid_eof() {
        // BOF insert
        assert_eq!(
            hunks_from_slices(b"a\nb\n", b"x\ny\nz\na\nb\n", Algorithm::Myers),
            vec![DiffHunk {
                line: 1,
                inserts: 3,
                deletes: 0,
                kind: HunkType::Insert
            }]
        );
        // Mid insert
        assert_eq!(
            hunks_from_slices(b"1\n2\n3\n4\n5\n", b"1\n2\n3\n4\nx\ny\n5\n", Algorithm::Myers),
            vec![DiffHunk {
                line: 5,
                inserts: 2,
                deletes: 0,
                kind: HunkType::Insert
            }]
        );
        // EOF insert
        assert_eq!(
            hunks_from_slices(b"1\n2\n", b"1\n2\n3\n", Algorithm::Myers),
            vec![DiffHunk {
                line: 3,
                inserts: 1,
                deletes: 0,
                kind: HunkType::Insert
            }]
        );
    }

    #[test]
    fn hunk_tuple_delete_bof_mid_eof_full() {
        // BOF delete
        assert_eq!(
            hunks_from_slices(b"1\n2\n3\n", b"3\n", Algorithm::Myers),
            vec![DiffHunk {
                line: 1,
                inserts: 0,
                deletes: 2,
                kind: HunkType::Delete
            }]
        );
        // Mid delete
        assert_eq!(
            hunks_from_slices(b"1\n2\n3\n4\n5\n6\n", b"1\n2\n3\n6\n", Algorithm::Myers),
            vec![DiffHunk {
                line: 4,
                inserts: 0,
                deletes: 2,
                kind: HunkType::Delete
            }]
        );
        // EOF delete
        assert_eq!(
            hunks_from_slices(b"1\n2\n3\n", b"1\n2\n", Algorithm::Myers),
            vec![DiffHunk {
                line: 3,
                inserts: 0,
                deletes: 1,
                kind: HunkType::Delete
            }]
        );
        // Full-file delete to 0 bytes
        assert_eq!(
            hunks_from_slices(b"1\n2\n3\n", b"", Algorithm::Myers),
            vec![DiffHunk {
                line: 1,
                inserts: 0,
                deletes: 3,
                kind: HunkType::Delete
            }]
        );
    }

    #[test]
    fn hunk_tuple_changes_and_no_trailing_newline() {
        // 1-to-N, N-to-1, multi-hunk
        assert_eq!(
            hunks_from_slices(b"a\nb\nc\nd\ne\n", b"a\nx\ny\nc\nd\ne\n", Algorithm::Myers),
            vec![DiffHunk {
                line: 2,
                inserts: 2,
                deletes: 1,
                kind: HunkType::Change
            }]
        );
        assert_eq!(
            hunks_from_slices(b"a\nx\ny\nc\n", b"a\nb\nc\n", Algorithm::Myers),
            vec![DiffHunk {
                line: 2,
                inserts: 1,
                deletes: 2,
                kind: HunkType::Change
            }]
        );
        // No trailing newline -> append newline + line (requires byte_lines!)
        assert_eq!(
            hunks_from_slices(b"x\ny", b"x\ny\nz\n", Algorithm::Myers),
            vec![DiffHunk {
                line: 2,
                inserts: 2,
                deletes: 1,
                kind: HunkType::Change
            }]
        );
        // Trailing newline stripped
        assert_eq!(
            hunks_from_slices(b"x\ny\n", b"x\ny", Algorithm::Myers),
            vec![DiffHunk {
                line: 2,
                inserts: 1,
                deletes: 1,
                kind: HunkType::Change
            }]
        );
        // Both lack trailing newline, last line modified
        assert_eq!(
            hunks_from_slices(b"x\ny", b"x\nz", Algorithm::Myers),
            vec![DiffHunk {
                line: 2,
                inserts: 1,
                deletes: 1,
                kind: HunkType::Change
            }]
        );
    }

    #[test]
    fn cli_flag_validation() {
        assert!(parse_args_from(["--porcelain".into(), "--sexp".into()]).is_err());
        assert!(parse_args_from(["-z".into()]).is_err());
        assert!(parse_args_from(["--all".into(), "--stdin".into()]).is_err());
        assert!(parse_args_from(["--all".into(), "foo".into()]).is_err());
        assert!(parse_args_from(["--stdin".into(), "foo".into()]).is_err());
        assert!(parse_args_from(["--unknown".into()]).is_err());
        let ok = parse_args_from(["-C".into(), "/tmp".into(), "--porcelain".into(), "--all".into()])
            .unwrap();
        assert!(ok.porcelain && ok.all);
    }

    #[test]
    fn porcelain_and_sexp_formatting_and_escaping() {
        let rows = vec![
            FileResult {
                path: "a/b\"c\\d\t.el".into(),
                state: VcState::Edited,
                hunks: vec![DiffHunk {
                    line: 10,
                    inserts: 2,
                    deletes: 1,
                    kind: HunkType::Change,
                }],
            },
            FileResult {
                path: "clean.el".into(),
                state: VcState::UpToDate,
                hunks: vec![],
            },
        ];

        let mut p_out = Vec::new();
        print_porcelain(&mut p_out, &rows).unwrap();
        let p_str = String::from_utf8(p_out).unwrap();
        assert!(p_str.starts_with("# git-diff-hl v1\n"));
        assert!(p_str.contains("F\tedited\ta/b\"c\\d\t.el\nH\t10\t2\t1\tchange\n"));
        assert!(p_str.contains("F\tup-to-date\tclean.el\n"));

        let mut s_out = Vec::new();
        print_sexp(&mut s_out, &rows).unwrap();
        let s_str = String::from_utf8(s_out).unwrap();
        assert!(s_str.contains(r#""a/b\"c\\d\t.el" edited ((10 2 1 change))"#));
        assert!(s_str.contains(r#""clean.el" up-to-date nil"#));
    }

    #[test]
    fn repo_states_fastpath_touch_racy_and_removals() {
        let repo = TempRepo::new("states");
        repo.write("clean.txt", b"one\ntwo\n");
        repo.write("touch.txt", b"alpha\nbeta\n");
        repo.write("edit.txt", b"1\n2\n3\n");
        repo.write("rm_cached.txt", b"keep on disk\n");
        repo.write("rm_disk.txt", b"gone from disk\n");
        repo.write(".gitignore", b"*.ignored\n");
        repo.commit_all("init");

        // Touch without changing content -> still up-to-date!
        repo.write("touch.txt", b"alpha\nbeta\n");
        // Edit content (same-second racy-git safe!)
        repo.write("edit.txt", b"1\n22\n3\n4\n");
        // Added clean (A )
        repo.write("added_clean.txt", b"a\nb\n");
        repo.git(&["add", "added_clean.txt"]);
        // Added then modified (AM)
        repo.write("added_mod.txt", b"x\ny\n");
        repo.git(&["add", "added_mod.txt"]);
        repo.write("added_mod.txt", b"x\ny\nz\n");
        // Staged rm --cached with file kept on disk -> unregistered
        repo.git(&["rm", "--cached", "-q", "rm_cached.txt"]);
        // Deleted from disk
        std::fs::remove_file(repo.dir.join("rm_disk.txt")).unwrap();
        // Untracked & ignored
        repo.write("untracked.txt", b"hi\n");
        repo.write("foo.ignored", b"skip\n");

        let res = repo.inspect_paths(&[
            "clean.txt",
            "touch.txt",
            "edit.txt",
            "added_clean.txt",
            "added_mod.txt",
            "rm_cached.txt",
            "rm_disk.txt",
            "untracked.txt",
            "foo.ignored",
        ]);
        let by_path = |p: &str| res.iter().find(|r| r.path == p).unwrap();

        assert_eq!(by_path("clean.txt").state, VcState::UpToDate);
        assert!(by_path("clean.txt").hunks.is_empty());

        assert_eq!(by_path("touch.txt").state, VcState::UpToDate);
        assert!(by_path("touch.txt").hunks.is_empty());

        assert_eq!(by_path("edit.txt").state, VcState::Edited);
        assert_eq!(
            by_path("edit.txt").hunks,
            vec![
                DiffHunk { line: 2, inserts: 1, deletes: 1, kind: HunkType::Change },
                DiffHunk { line: 4, inserts: 1, deletes: 0, kind: HunkType::Insert },
            ]
        );

        assert_eq!(by_path("added_clean.txt").state, VcState::Added);
        assert_eq!(
            by_path("added_clean.txt").hunks,
            vec![DiffHunk { line: 1, inserts: 2, deletes: 0, kind: HunkType::Insert }]
        );

        assert_eq!(by_path("added_mod.txt").state, VcState::Edited);
        assert_eq!(
            by_path("added_mod.txt").hunks,
            vec![DiffHunk { line: 1, inserts: 3, deletes: 0, kind: HunkType::Insert }]
        );

        assert_eq!(by_path("rm_cached.txt").state, VcState::Unregistered);
        assert!(by_path("rm_cached.txt").hunks.is_empty());

        assert_eq!(by_path("rm_disk.txt").state, VcState::Removed);
        assert_eq!(
            by_path("rm_disk.txt").hunks,
            vec![DiffHunk { line: 1, inserts: 0, deletes: 1, kind: HunkType::Delete }]
        );

        assert_eq!(by_path("untracked.txt").state, VcState::Unregistered);
        assert_eq!(by_path("foo.ignored").state, VcState::Ignored);

        // --all reports tracked paths (HEAD/index) and emits clean.txt too
        let all = repo.inspect_all();
        assert!(all.iter().any(|r| r.path == "clean.txt" && r.state == VcState::UpToDate));
        assert!(all.iter().any(|r| r.path == "rm_disk.txt" && r.state == VcState::Removed));
    }

    #[test]
    fn unborn_head_and_binary_and_reverted_staged() {
        let repo = TempRepo::new("unborn");
        repo.write(".gitignore", b"*.ign\n");
        repo.write("a.txt", b"1\n2\n");
        repo.git(&["add", "a.txt"]);
        repo.write("am.txt", b"1\n");
        repo.git(&["add", "am.txt"]);
        repo.write("am.txt", b"1\n2\n3\n");
        repo.write("u.txt", b"untracked\n");
        repo.write("x.ign", b"ignored\n");

        let res = repo.inspect_paths(&["a.txt", "am.txt", "u.txt", "x.ign"]);
        assert_eq!(res[0].state, VcState::Added);
        assert_eq!(res[1].state, VcState::Edited);
        assert_eq!(
            res[1].hunks,
            vec![DiffHunk { line: 1, inserts: 3, deletes: 0, kind: HunkType::Insert }]
        );
        assert_eq!(res[2].state, VcState::Unregistered);
        assert_eq!(res[3].state, VcState::Ignored);

        // Commit, then test binary (\0 bytes) and MM reverted to HEAD
        repo.commit_all("initial");
        repo.write("bin.dat", b"\x00\x01\x02");
        repo.write("attr.bin", b"text\n");
        repo.write(".gitattributes", b"*.bin binary\n");
        repo.write("rev.txt", b"orig\n");
        repo.commit_all("add bin and rev");

        repo.write("bin.dat", b"\x00\x01\x02\x03");
        repo.write("attr.bin", b"text\nmore\n");
        // Stage change, then revert working tree back to HEAD (MM with wt == HEAD)
        repo.write("rev.txt", b"staged\n");
        repo.git(&["add", "rev.txt"]);
        repo.write("rev.txt", b"orig\n");

        let res2 = repo.inspect_paths(&["bin.dat", "attr.bin", "rev.txt"]);
        assert_eq!(res2[0].state, VcState::Edited);
        assert!(res2[0].hunks.is_empty());
        assert_eq!(res2[1].state, VcState::Edited);
        assert!(res2[1].hunks.is_empty());
        assert_eq!(res2[2].state, VcState::Edited);
        assert!(res2[2].hunks.is_empty());
    }

    #[test]
    fn merge_conflict_and_crlf_and_symlinks() {
        let repo = TempRepo::new("conflict");
        repo.write("c.txt", b"base\n");
        repo.commit_all("base");
        let default_branch = repo.git(&["branch", "--show-current"]).trim().to_string();
        repo.git(&["checkout", "-q", "-b", "side"]);
        repo.write("c.txt", b"side\n");
        repo.commit_all("side");
        repo.git(&["checkout", "-q", &default_branch]);
        repo.write("c.txt", b"main\n");
        repo.commit_all("main");
        let _ = Command::new("git")
            .arg("-C")
            .arg(&repo.dir)
            .args(["merge", "-q", "side"])
            .output()
            .unwrap();

        let res = repo.inspect_paths(&["c.txt"]);
        assert_eq!(res[0].state, VcState::Conflict);
        assert!(!res[0].hunks.is_empty());

        // CRLF with core.autocrlf=input (ToGit)
        let crlf_repo = TempRepo::new("crlf");
        crlf_repo.git(&["config", "core.autocrlf", "input"]);
        crlf_repo.write("line.txt", b"one\ntwo\n");
        crlf_repo.commit_all("lf");
        // Write CRLF to worktree with same LF content -> ToGit converts to LF -> up-to-date
        crlf_repo.write("line.txt", b"one\r\ntwo\r\n");
        let crlf_res = crlf_repo.inspect_paths(&["line.txt"]);
        assert_eq!(crlf_res[0].state, VcState::UpToDate);
        assert!(crlf_res[0].hunks.is_empty());

        // Symlink test (Unix)
        #[cfg(unix)]
        {
            let sym_repo = TempRepo::new("symlink");
            std::os::unix::fs::symlink("target-a", sym_repo.dir.join("link")).unwrap();
            sym_repo.commit_all("link");
            assert_eq!(sym_repo.inspect_paths(&["link"])[0].state, VcState::UpToDate);
            std::fs::remove_file(sym_repo.dir.join("link")).unwrap();
            std::os::unix::fs::symlink("target-b", sym_repo.dir.join("link")).unwrap();
            let sym_res = sym_repo.inspect_paths(&["link"]);
            assert_eq!(sym_res[0].state, VcState::Edited);
            assert_eq!(
                sym_res[0].hunks,
                vec![DiffHunk { line: 1, inserts: 1, deletes: 1, kind: HunkType::Change }]
            );
        }
    }

    #[test]
    fn histogram_diff_algorithm_and_parallel_batch() {
        let repo = TempRepo::new("histogram");
        repo.git(&["config", "diff.algorithm", "histogram"]);
        for i in 0..8 {
            let name = format!("f{i}.txt");
            repo.write(&name, b"a\nb\nc\nd\n");
        }
        repo.commit_all("batch");
        // Modify multiple files to exercise std::thread::scope parallel workers
        for i in 0..5 {
            let name = format!("f{i}.txt");
            repo.write(&name, b"a\nb\nx\nc\nd\n");
        }
        let paths: Vec<String> = (0..8).map(|i| format!("f{i}.txt")).collect();
        let refs: Vec<&str> = paths.iter().map(String::as_str).collect();
        let res = repo.inspect_paths(&refs);
        assert_eq!(res.len(), 8);
        for i in 0..5 {
            assert_eq!(res[i].state, VcState::Edited);
            assert_eq!(
                res[i].hunks,
                vec![DiffHunk { line: 3, inserts: 1, deletes: 0, kind: HunkType::Insert }]
            );
        }
        for i in 5..8 {
            assert_eq!(res[i].state, VcState::UpToDate);
            assert!(res[i].hunks.is_empty());
        }
    }
}
