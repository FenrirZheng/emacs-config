use std::io::Write;
use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicUsize, Ordering};

static COUNTER: AtomicUsize = AtomicUsize::new(0);

struct TempRepo {
    dir: PathBuf,
}

impl TempRepo {
    fn new(name: &str) -> Self {
        let n = COUNTER.fetch_add(1, Ordering::Relaxed);
        let dir = std::env::temp_dir().join(format!(
            "git-diff-hl-cli-test-{}-{}-{name}",
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

    fn git(&self, args: &[&str]) {
        let out = Command::new("git")
            .arg("-C")
            .arg(&self.dir)
            .args(args)
            .output()
            .unwrap();
        assert!(
            out.status.success(),
            "git {:?} failed: {}",
            args,
            String::from_utf8_lossy(&out.stderr)
        );
    }

    fn write(&self, rel: &str, bytes: &[u8]) {
        let path = self.dir.join(rel);
        if let Some(p) = path.parent() {
            std::fs::create_dir_all(p).unwrap();
        }
        std::fs::write(path, bytes).unwrap();
    }
}

impl Drop for TempRepo {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.dir);
    }
}

#[test]
fn cli_porcelain_all_stdin_nul_sexp_and_exit_code() {
    let bin = env!("CARGO_BIN_EXE_git-diff-hl");
    let repo = TempRepo::new("cli");
    let special = "dir/with spaces \"quotes\" and\ttab.txt";
    repo.write("clean.txt", b"one\n");
    repo.write(special, b"a\nb\n");
    repo.git(&["add", "-A"]);
    repo.git(&["commit", "-q", "-m", "init"]);

    // Modify special file
    repo.write(special, b"a\nb\nc\n");

    // 1. --porcelain --all
    let out = Command::new(bin)
        .arg("-C")
        .arg(&repo.dir)
        .args(["--porcelain", "--all"])
        .output()
        .unwrap();
    assert!(out.status.success());
    let stdout = String::from_utf8(out.stdout).unwrap();
    let mut lines = stdout.lines();
    assert_eq!(lines.next(), Some("# git-diff-hl v1"));
    assert!(stdout.contains("F\tup-to-date\tclean.txt\n"));
    assert!(stdout.contains(&format!("F\tedited\t{special}\nH\t3\t1\t0\tinsert\n")));

    // 2. --stdin -z with special filename
    let mut child = Command::new(bin)
        .arg("-C")
        .arg(&repo.dir)
        .args(["--porcelain", "--stdin", "-z"])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .unwrap();
    {
        let stdin = child.stdin.as_mut().unwrap();
        stdin.write_all(special.as_bytes()).unwrap();
        stdin.write_all(b"\0clean.txt\0").unwrap();
    }
    let out_z = child.wait_with_output().unwrap();
    assert!(out_z.status.success());
    let stdout_z = String::from_utf8(out_z.stdout).unwrap();
    assert!(stdout_z.starts_with("# git-diff-hl v1\n"));
    assert!(stdout_z.contains(&format!("F\tedited\t{special}\nH\t3\t1\t0\tinsert\n")));
    assert!(stdout_z.contains("F\tup-to-date\tclean.txt\n"));

    // 3. --stdin (newline-delimited) + --exit-code (exits 1 when dirty, 0 when clean)
    let mut child_nl = Command::new(bin)
        .arg("-C")
        .arg(&repo.dir)
        .args(["--sexp", "--stdin", "--exit-code"])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .unwrap();
    {
        let stdin = child_nl.stdin.as_mut().unwrap();
        stdin.write_all(b"clean.txt\n").unwrap();
    }
    let out_clean = child_nl.wait_with_output().unwrap();
    assert_eq!(out_clean.status.code(), Some(0));
    assert_eq!(
        String::from_utf8(out_clean.stdout).unwrap().trim(),
        "((\"clean.txt\" up-to-date nil))"
    );

    let out_dirty = Command::new(bin)
        .arg("-C")
        .arg(&repo.dir)
        .args(["--porcelain", "--exit-code", special])
        .output()
        .unwrap();
    assert_eq!(out_dirty.status.code(), Some(1));
}

#[test]
fn cli_submodule_staged_committed_and_nested_path() {
    let bin = env!("CARGO_BIN_EXE_git-diff-hl");
    let sub = TempRepo::new("submod-child");
    sub.write("s.txt", b"sub1\n");
    sub.git(&["add", "-A"]);
    sub.git(&["commit", "-q", "-m", "s1"]);
    let sub_head = String::from_utf8(
        Command::new("git")
            .arg("-C")
            .arg(&sub.dir)
            .args(["rev-parse", "HEAD"])
            .output()
            .unwrap()
            .stdout,
    )
    .unwrap();
    let sub_head = sub_head.trim();

    let main = TempRepo::new("submod-parent");
    main.write("r.txt", b"root\n");
    main.git(&["add", "-A"]);
    main.git(&["commit", "-q", "-m", "r1"]);

    // Clone sub into main/submod and stage gitlink 160000 without committing
    let clone_out = Command::new("git")
        .arg("-C")
        .arg(&main.dir)
        .args(["clone", "-q"])
        .arg(&sub.dir)
        .arg(main.dir.join("submod"))
        .output()
        .unwrap();
    assert!(clone_out.status.success());
    let cacheinfo = format!("160000,{sub_head},submod");
    main.git(&["update-index", "--add", "--cacheinfo", &cacheinfo]);

    // 1. Staged gitlink must NOT classify as removed
    let out_staged = Command::new(bin)
        .arg("-C")
        .arg(&main.dir)
        .args(["--porcelain", "submod"])
        .output()
        .unwrap();
    assert!(out_staged.status.success());
    let s_stdout = String::from_utf8(out_staged.stdout).unwrap();
    assert!(!s_stdout.contains("F\tremoved\tsubmod"), "got: {s_stdout}");

    // 2. Committed gitlink + querying a path inside the submodule must NOT exit 2
    main.git(&["commit", "-q", "-m", "add submod"]);
    let out_nested = Command::new(bin)
        .arg("-C")
        .arg(&main.dir)
        .args(["--porcelain", "submod/s.txt"])
        .output()
        .unwrap();
    assert!(
        out_nested.status.success(),
        "nested submodule path failed: {}",
        String::from_utf8_lossy(&out_nested.stderr)
    );
}

#[test]
fn cli_sparse_checkout_and_assume_unchanged() {
    let bin = env!("CARGO_BIN_EXE_git-diff-hl");
    let repo = TempRepo::new("sparse");
    repo.write("dir1/a.txt", b"one\n");
    repo.write("dir2/b.txt", b"two\n");
    repo.git(&["add", "-A"]);
    repo.git(&["commit", "-q", "-m", "init"]);

    repo.git(&["sparse-checkout", "init", "--cone"]);
    repo.git(&["sparse-checkout", "set", "dir1"]);

    // Staged new file with --assume-unchanged, modified on disk -> still added
    repo.write("new_assume.txt", b"v1\n");
    repo.git(&["add", "new_assume.txt"]);
    repo.git(&["update-index", "--assume-unchanged", "new_assume.txt"]);
    repo.write("new_assume.txt", b"v1\nv2\n");

    let out = Command::new(bin)
        .arg("-C")
        .arg(&repo.dir)
        .args(["--porcelain", "--all"])
        .output()
        .unwrap();
    assert!(out.status.success());
    let stdout = String::from_utf8(out.stdout).unwrap();
    assert!(stdout.contains("F\tup-to-date\tdir2/b.txt\n"), "got: {stdout}");
    assert!(stdout.contains("F\tadded\tnew_assume.txt\n"), "got: {stdout}");
}

#[test]
fn cli_errors_worktree_and_large_multithread_batch() {
    let bin = env!("CARGO_BIN_EXE_git-diff-hl");

    // 1. Non-repo, bare repo, corrupt index -> exit 2
    let nonrepo = std::env::temp_dir().join(format!("gdh-nonrepo-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&nonrepo);
    std::fs::create_dir_all(&nonrepo).unwrap();
    let out_nr = Command::new(bin)
        .arg("-C")
        .arg(&nonrepo)
        .arg("--all")
        .output()
        .unwrap();
    assert_eq!(out_nr.status.code(), Some(2));
    let _ = std::fs::remove_dir_all(&nonrepo);

    let bare = std::env::temp_dir().join(format!("gdh-bare-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&bare);
    std::fs::create_dir_all(&bare).unwrap();
    assert!(
        Command::new("git")
            .arg("-C")
            .arg(&bare)
            .args(["init", "-q", "--bare"])
            .status()
            .unwrap()
            .success()
    );
    let out_bare = Command::new(bin)
        .arg("-C")
        .arg(&bare)
        .arg("--all")
        .output()
        .unwrap();
    assert_eq!(out_bare.status.code(), Some(2));
    let _ = std::fs::remove_dir_all(&bare);

    let corrupt = TempRepo::new("corrupt-idx");
    corrupt.write("a.txt", b"hi\n");
    corrupt.git(&["add", "a.txt"]);
    corrupt.git(&["commit", "-q", "-m", "c"]);
    std::fs::write(corrupt.dir.join(".git/index"), b"CORRUPT").unwrap();
    let out_cor = Command::new(bin)
        .arg("-C")
        .arg(&corrupt.dir)
        .arg("--all")
        .output()
        .unwrap();
    assert_eq!(out_cor.status.code(), Some(2));

    // 2. Linked git worktree
    let main = TempRepo::new("wt-main");
    main.write("a.txt", b"one\n");
    main.git(&["add", "a.txt"]);
    main.git(&["commit", "-q", "-m", "init"]);
    let wt_dir = std::env::temp_dir().join(format!("gdh-wt-linked-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&wt_dir);
    main.git(&["worktree", "add", "-q", wt_dir.to_str().unwrap(), "-b", "wt-b"]);
    std::fs::write(wt_dir.join("a.txt"), b"one\ntwo\n").unwrap();
    let out_wt = Command::new(bin)
        .arg("-C")
        .arg(&wt_dir)
        .args(["--porcelain", "--all"])
        .output()
        .unwrap();
    assert!(out_wt.status.success());
    assert!(
        String::from_utf8(out_wt.stdout)
            .unwrap()
            .contains("F\tedited\ta.txt\nH\t2\t1\t0\tinsert\n")
    );
    let _ = std::fs::remove_dir_all(&wt_dir);

    // 3. Large (>6 worker) multi-thread mixed batch preserving input order
    let batch = TempRepo::new("big-batch");
    batch.write(".gitignore", b"*.ign\n");
    for i in 0..10 {
        batch.write(&format!("c_{i:02}.txt"), b"a\nb\n");
        batch.write(&format!("e_{i:02}.txt"), b"1\n2\n");
        batch.write(&format!("d_{i:02}.txt"), b"del\n");
        batch.write(&format!("b_{i:02}.dat"), b"\x00\x01\x02");
    }
    batch.git(&["add", "-A"]);
    batch.git(&["commit", "-q", "-m", "init"]);
    let mut paths = Vec::new();
    for i in 0..10 {
        batch.write(&format!("e_{i:02}.txt"), b"1\n2\n3\n");
        std::fs::remove_file(batch.dir.join(format!("d_{i:02}.txt"))).unwrap();
        batch.write(&format!("b_{i:02}.dat"), b"\x00\x01\x03");
        batch.write(&format!("a_{i:02}.txt"), b"add\n");
        batch.git(&["add", &format!("a_{i:02}.txt")]);
        batch.write(&format!("u_{i:02}.txt"), b"unreg\n");
        batch.write(&format!("g_{i:02}.ign"), b"ign\n");
        for p in ["c", "e", "d", "b", "a", "u", "g"] {
            let ext = if p == "b" {
                "dat"
            } else if p == "g" {
                "ign"
            } else {
                "txt"
            };
            paths.push(format!("{p}_{i:02}.{ext}"));
        }
    }
    let mut child = Command::new(bin)
        .arg("-C")
        .arg(&batch.dir)
        .args(["--porcelain", "--stdin", "-z"])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .unwrap();
    {
        let stdin = child.stdin.as_mut().unwrap();
        for p in &paths {
            stdin.write_all(p.as_bytes()).unwrap();
            stdin.write_all(b"\0").unwrap();
        }
    }
    let out_b = child.wait_with_output().unwrap();
    assert!(out_b.status.success());
    let stdout_b = String::from_utf8(out_b.stdout).unwrap();
    let emitted: Vec<&str> = stdout_b
        .lines()
        .filter_map(|l| l.strip_prefix("F\t"))
        .map(|rest| rest.split_once('\t').unwrap().1)
        .collect();
    assert_eq!(emitted, paths.iter().map(String::as_str).collect::<Vec<_>>());
}
