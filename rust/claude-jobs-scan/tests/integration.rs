//! End-to-end integration tests for `claude-jobs-scan`, including real `/proc`
//! child processes with RAII `Drop` cleanup.

use claude_jobs_scan::{
    scan_all, scan_uuid, write_full_lisp, write_uuid_lisp, Config, DEFAULT_HEAD_BYTES,
};
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{Duration, Instant};

static COUNTER: AtomicU64 = AtomicU64::new(0);

struct TempDir(PathBuf);

impl TempDir {
    fn new(prefix: &str) -> Self {
        let id = COUNTER.fetch_add(1, Ordering::Relaxed);
        let dir = std::env::temp_dir().join(format!("{prefix}-{}-{id}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        Self(dir)
    }

    fn path(&self) -> &Path {
        &self.0
    }
}

impl Drop for TempDir {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

struct ChildGuard(Option<Child>);

impl ChildGuard {
    fn spawn_sleep_with_args(extra_args: &[&str]) -> Self {
        let mut cmd = Command::new("python3");
        cmd.arg("-c")
            .arg("import time; time.sleep(30)")
            .args(extra_args)
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null());
        let child = cmd.spawn().expect("spawn python3 dummy process");
        // Wait until /proc/<pid>/cmdline reflects python3 args.
        let cmdline_path = PathBuf::from(format!("/proc/{}/cmdline", child.id()));
        let deadline = Instant::now() + Duration::from_secs(2);
        while Instant::now() < deadline {
            if let Ok(bytes) = fs::read(&cmdline_path) {
                if !bytes.is_empty()
                    && extra_args
                        .iter()
                        .all(|a| bytes.windows(a.len()).any(|w| w == a.as_bytes()))
                {
                    break;
                }
            }
            std::thread::sleep(Duration::from_millis(10));
        }
        Self(Some(child))
    }

    fn pid(&self) -> u32 {
        self.0.as_ref().unwrap().id()
    }
}

impl Drop for ChildGuard {
    fn drop(&mut self) {
        if let Some(mut c) = self.0.take() {
            let _ = c.kill();
            let _ = c.wait();
        }
    }
}

#[test]
fn missing_directories_yield_empty_result() {
    let tmp = TempDir::new("cjs-missing");
    let cfg = Config {
        state_dir: tmp.path().join("no-state"),
        jobs_dir: tmp.path().join("no-jobs"),
        projects_dir: tmp.path().join("no-projects"),
        proc_dir: PathBuf::from("/proc"),
        head_bytes: DEFAULT_HEAD_BYTES,
        uuid: None,
    };
    let res = scan_all(&cfg);
    assert!(res.sessions.is_empty());
    assert!(res.daemons.is_empty());
    let mut out = Vec::new();
    write_full_lisp(&mut out, &res).unwrap();
    assert_eq!(String::from_utf8(out).unwrap(), "(:sessions () :daemons ())\n");
}

#[test]
fn end_to_end_fixture_and_real_proc_and_uuid_mode() {
    let tmp = TempDir::new("cjs-e2e");
    let state_dir = tmp.path().join("state");
    let jobs_dir = tmp.path().join("jobs");
    let projects_dir = tmp.path().join("projects");
    fs::create_dir_all(&state_dir).unwrap();
    fs::create_dir_all(&jobs_dir).unwrap();
    fs::create_dir_all(&projects_dir).unwrap();

    // 1. Live session matching meta_pid (alive, not resumed)
    let sid_alive = "11111111-1111-1111-1111-111111111111";
    let child1 = ChildGuard::spawn_sleep_with_args(&["--session-id", sid_alive]);
    fs::write(
        state_dir.join(format!("{sid_alive}.meta")),
        format!(
            "sid={sid_alive}\npid={}\ncwd=/tmp/my.dot\\ dir\nagent=my\\ agent\nstarted=2026-11-25T01:00:00+08:00\n",
            child1.pid()
        ),
    )
    .unwrap();
    let p1 = projects_dir.join("-tmp-my-dot-dir");
    fs::create_dir_all(&p1).unwrap();
    fs::write(
        p1.join(format!("{sid_alive}.jsonl")),
        "{\"type\":\"user\",\"cwd\":\"/tmp/my.dot dir\",\"message\":{\"content\":\"alive prompt\"}}\n",
    )
    .unwrap();

    // 2. Resumed session (meta pid dead, two live --resume processes -> alive,resumed)
    let sid_resumed = "22222222-2222-2222-2222-222222222222";
    let child2a = ChildGuard::spawn_sleep_with_args(&["--resume", sid_resumed]);
    let child2b = ChildGuard::spawn_sleep_with_args(&[&format!("--resume={sid_resumed}")]);
    fs::write(
        state_dir.join(format!("{sid_resumed}.meta")),
        format!(
            "sid={sid_resumed}\npid=99999999\nagent=''\nstarted=2026-11-25T02:00:00+08:00\n"
        ),
    )
    .unwrap();
    // Put transcript in an unrelated project dir to exercise depth-2 fallback + cwd fallback.
    let p2 = projects_dir.join("-unrelated-subdir");
    fs::create_dir_all(&p2).unwrap();
    let mut jsonl2 = Vec::new();
    jsonl2.extend_from_slice(
        b"{\"type\":\"user\",\"cwd\":\"/tmp/fallback-cwd\",\"message\":{\"content\":[{\"type\":\"tool_result\"}]}}\n",
    );
    jsonl2.extend_from_slice(
        b"{\"type\":\"user\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"resumed\\nprompt\"}]}}\n",
    );
    fs::write(p2.join(format!("{sid_resumed}.jsonl")), jsonl2).unwrap();

    // 3. Orphan .out/.err without .meta (must be ignored)
    fs::write(state_dir.join("33333333-3333-3333-3333-333333333333.out"), "log").unwrap();
    fs::write(state_dir.join("33333333-3333-3333-3333-333333333333.err"), "err").unwrap();

    // 4. Daemons: valid CJK, pins.json non-dir, dir without state.json
    fs::write(jobs_dir.join("pins.json"), "{}").unwrap();
    fs::create_dir_all(jobs_dir.join("nostate")).unwrap();
    fs::create_dir_all(jobs_dir.join("d1")).unwrap();
    let long_cjk = format!("{}尾部", "中".repeat(62));
    fs::write(
        jobs_dir.join("d1/state.json"),
        format!(
            r#"{{"daemonShort":"d1","state":"running","updatedAt":"2026-11-25T03:00:00Z","intent":"{long_cjk}","name":"n1","cwd":"/tmp/d1"}}"#
        ),
    )
    .unwrap();

    let cfg = Config {
        state_dir,
        jobs_dir,
        projects_dir,
        proc_dir: PathBuf::from("/proc"),
        head_bytes: DEFAULT_HEAD_BYTES,
        uuid: None,
    };

    let res = scan_all(&cfg);
    assert_eq!(res.sessions.len(), 2);
    assert_eq!(res.daemons.len(), 1);

    let s1 = &res.sessions[0];
    assert_eq!(s1.sid, sid_alive);
    assert_eq!(s1.state, "alive");
    assert!(!s1.resumed);
    assert_eq!(s1.live_pids, vec![child1.pid()]);
    assert_eq!(s1.agent, "my agent");
    assert_eq!(s1.cwd.as_deref(), Some("/tmp/my.dot dir"));
    assert_eq!(s1.first_user_text.as_deref(), Some("alive prompt"));

    let s2 = &res.sessions[1];
    assert_eq!(s2.sid, sid_resumed);
    assert_eq!(s2.state, "alive");
    assert!(s2.resumed);
    let mut expected_pids = vec![child2a.pid(), child2b.pid()];
    expected_pids.sort_unstable();
    assert_eq!(s2.live_pids, expected_pids);
    assert_eq!(s2.agent, "-");
    assert_eq!(s2.cwd.as_deref(), Some("/tmp/fallback-cwd"));
    assert_eq!(s2.first_user_text.as_deref(), Some("resumed\nprompt"));

    let d1 = &res.daemons[0];
    assert_eq!(d1.short, "d1");
    assert_eq!(d1.intent.chars().count(), 60);
    assert_eq!(d1.raw_intent.chars().count(), 64);

    // --uuid mode hit & miss
    let hit = scan_uuid(&cfg, sid_resumed).unwrap();
    assert_eq!(hit.sid, sid_resumed);
    assert!(hit.resumed);
    let mut uuid_out = Vec::new();
    write_uuid_lisp(&mut uuid_out, Some(&hit)).unwrap();
    assert!(String::from_utf8(uuid_out).unwrap().starts_with("(:sid "));

    assert!(scan_uuid(&cfg, "99999999-9999-9999-9999-999999999999").is_none());
    let mut miss_out = Vec::new();
    write_uuid_lisp(&mut miss_out, None).unwrap();
    assert_eq!(String::from_utf8(miss_out).unwrap(), "nil\n");
}
