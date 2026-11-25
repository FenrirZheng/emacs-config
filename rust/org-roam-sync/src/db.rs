use std::collections::HashMap;
use std::fs;
use std::path::Path;

use rusqlite::{params, Connection, ErrorCode, TransactionBehavior};

use crate::parser::ParsedOrgData;
use crate::sexpr::{opt_prin1_string, prin1_string};

pub const ORG_ROAM_DB_VERSION: i32 = 20;

const SCHEMA_SQL: &str = "\
PRAGMA user_version = 20;
CREATE TABLE files (file UNIQUE PRIMARY KEY, title , hash NOT NULL, atime NOT NULL, mtime NOT NULL);
CREATE TABLE nodes (id NOT NULL PRIMARY KEY, file NOT NULL, level NOT NULL, pos NOT NULL, todo , priority , scheduled text, deadline text, title , properties , olp , FOREIGN KEY (file) REFERENCES files (file) ON DELETE CASCADE);
CREATE TABLE aliases (node_id NOT NULL, alias , FOREIGN KEY (node_id) REFERENCES nodes (id) ON DELETE CASCADE);
CREATE TABLE citations (node_id NOT NULL, cite_key NOT NULL, pos NOT NULL, properties , FOREIGN KEY (node_id) REFERENCES nodes (id) ON DELETE CASCADE);
CREATE TABLE refs (node_id NOT NULL, ref NOT NULL, type NOT NULL, FOREIGN KEY (node_id) REFERENCES nodes (id) ON DELETE CASCADE);
CREATE TABLE tags (node_id NOT NULL, tag , FOREIGN KEY (node_id) REFERENCES nodes (id) ON DELETE CASCADE);
CREATE TABLE links (pos NOT NULL, source NOT NULL, dest NOT NULL, type NOT NULL, properties NOT NULL, FOREIGN KEY (source) REFERENCES nodes (id) ON DELETE CASCADE);
CREATE INDEX alias_node_id ON aliases (node_id );
CREATE INDEX refs_node_id ON refs (node_id );
CREATE INDEX tags_node_id ON tags (node_id );
";

pub struct FileUpdate {
    pub file: String,
    pub hash: String,
    pub atime: String,
    pub mtime: String,
    pub parsed: ParsedOrgData,
}

/// Open or initialize `db_path`, ensuring `user_version == 20`, `busy_timeout = 20000`,
/// and `foreign_keys = ON`. If `force` is true or existing `user_version < 20` (non-zero),
/// the DB file is recreated cleanly.
pub fn open_db(db_path: &Path, force: bool) -> Result<Connection, String> {
    if let Some(parent) = db_path.parent() {
        if !parent.as_os_str().is_empty() {
            fs::create_dir_all(parent)
                .map_err(|e| format!("failed to create {}: {}", parent.display(), e))?;
        }
    }

    if force && db_path.exists() {
        fs::remove_file(db_path)
            .map_err(|e| format!("failed to remove {}: {}", db_path.display(), e))?;
    }

    let mut conn = Connection::open(db_path)
        .map_err(|e| format!("failed to open {}: {}", db_path.display(), e))?;
    configure_pragmas(&conn)?;

    let version: i32 = conn
        .query_row("PRAGMA user_version", [], |r| r.get(0))
        .map_err(|e| format!("failed to read user_version: {}", e))?;

    if version > ORG_ROAM_DB_VERSION {
        return Err(format!(
            "database schema version {} is newer than supported version {}",
            version, ORG_ROAM_DB_VERSION
        ));
    }

    if version > 0 && version < ORG_ROAM_DB_VERSION {
        drop(conn);
        fs::remove_file(db_path)
            .map_err(|e| format!("failed to remove old-version {}: {}", db_path.display(), e))?;
        conn = Connection::open(db_path)
            .map_err(|e| format!("failed to reopen {}: {}", db_path.display(), e))?;
        configure_pragmas(&conn)?;
        conn.execute_batch(SCHEMA_SQL)
            .map_err(|e| format!("failed to initialize v20 schema: {}", e))?;
    } else if version == 0 {
        let table_count: i64 = conn
            .query_row(
                "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='files'",
                [],
                |r| r.get(0),
            )
            .map_err(|e| format!("failed to check sqlite_master: {}", e))?;
        if table_count == 0 {
            conn.execute_batch(SCHEMA_SQL)
                .map_err(|e| format!("failed to initialize v20 schema: {}", e))?;
        } else {
            conn.execute_batch("PRAGMA user_version = 20;")
                .map_err(|e| format!("failed to set user_version: {}", e))?;
        }
    }

    Ok(conn)
}

fn configure_pragmas(conn: &Connection) -> Result<(), String> {
    conn.execute_batch("PRAGMA busy_timeout = 20000; PRAGMA foreign_keys = ON;")
        .map_err(|e| format!("failed to set PRAGMAs: {}", e))
}

/// Read current `(prin1_file_path -> (raw_file_path, raw_hash))` map from `files`.
pub fn load_existing_file_hashes(conn: &Connection) -> Result<HashMap<String, String>, String> {
    let mut stmt = conn
        .prepare("SELECT file, hash FROM files")
        .map_err(|e| format!("failed to prepare file hash query: {}", e))?;
    let rows = stmt
        .query_map([], |row| {
            let file_raw: String = row.get(0)?;
            let hash_raw: String = row.get(1)?;
            Ok((file_raw, hash_raw))
        })
        .map_err(|e| format!("failed to query existing files: {}", e))?;

    let mut map = HashMap::new();
    for r in rows {
        let (f, h) = r.map_err(|e| format!("failed to read file row: {}", e))?;
        map.insert(f, h);
    }
    Ok(map)
}

/// Apply deletions and file updates inside a single `BEGIN IMMEDIATE` transaction.
pub fn apply_updates(
    conn: &mut Connection,
    deleted_prin1_files: &[String],
    updates: &[FileUpdate],
) -> Result<(), String> {
    if deleted_prin1_files.is_empty() && updates.is_empty() {
        return Ok(());
    }

    let tx = conn
        .transaction_with_behavior(TransactionBehavior::Immediate)
        .map_err(|e| format!("failed to start transaction: {}", e))?;

    {
        let mut del_file = tx
            .prepare_cached("DELETE FROM files WHERE file = ?1")
            .map_err(|e| format!("prepare DELETE files failed: {}", e))?;
        let mut ins_file = tx
            .prepare_cached(
                "INSERT INTO files (file, title, hash, atime, mtime) VALUES (?1, ?2, ?3, ?4, ?5)",
            )
            .map_err(|e| format!("prepare INSERT files failed: {}", e))?;
        let mut ins_node = tx
            .prepare_cached(
                "INSERT INTO nodes (id, file, level, pos, todo, priority, scheduled, deadline, title, properties, olp) \
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)",
            )
            .map_err(|e| format!("prepare INSERT nodes failed: {}", e))?;
        let mut ins_alias = tx
            .prepare_cached("INSERT INTO aliases (node_id, alias) VALUES (?1, ?2)")
            .map_err(|e| format!("prepare INSERT aliases failed: {}", e))?;
        let mut ins_tag = tx
            .prepare_cached("INSERT INTO tags (node_id, tag) VALUES (?1, ?2)")
            .map_err(|e| format!("prepare INSERT tags failed: {}", e))?;
        let mut ins_ref = tx
            .prepare_cached("INSERT INTO refs (node_id, ref, type) VALUES (?1, ?2, ?3)")
            .map_err(|e| format!("prepare INSERT refs failed: {}", e))?;
        let mut ins_cit = tx
            .prepare_cached(
                "INSERT INTO citations (node_id, cite_key, pos, properties) VALUES (?1, ?2, ?3, ?4)",
            )
            .map_err(|e| format!("prepare INSERT citations failed: {}", e))?;
        let mut ins_link = tx
            .prepare_cached(
                "INSERT INTO links (pos, source, dest, type, properties) VALUES (?1, ?2, ?3, ?4, ?5)",
            )
            .map_err(|e| format!("prepare INSERT links failed: {}", e))?;

        for f_prin1 in deleted_prin1_files {
            del_file
                .execute(params![f_prin1])
                .map_err(|e| format!("delete file {} failed: {}", f_prin1, e))?;
        }

        // Delete all updated files BEFORE inserting any new/updated nodes so
        // moving an :ID: between files in any filename sort order never
        // collides on `nodes.id` PRIMARY KEY and then gets cascade-deleted.
        for u in updates {
            let f_prin1 = prin1_string(&u.file);
            del_file
                .execute(params![&f_prin1])
                .map_err(|e| format!("clear file {} failed: {}", u.file, e))?;
        }

        for u in updates {
            let f_prin1 = prin1_string(&u.file);
            let title_p = prin1_string(&u.parsed.file_title);
            let hash_p = prin1_string(&u.hash);
            ins_file
                .execute(params![&f_prin1, &title_p, &hash_p, &u.atime, &u.mtime])
                .map_err(|e| format!("insert file {} failed: {}", u.file, e))?;

            for node in &u.parsed.nodes {
                let id_p = prin1_string(&node.id);
                let todo_p = node.todo.as_deref().map(prin1_string);
                let sched_p = node.scheduled.as_deref().map(prin1_string);
                let dead_p = node.deadline.as_deref().map(prin1_string);
                let ntitle_p = prin1_string(&node.title);

                match ins_node.execute(params![
                    &id_p,
                    &f_prin1,
                    node.level,
                    node.pos,
                    todo_p,
                    node.priority,
                    sched_p,
                    dead_p,
                    &ntitle_p,
                    node.properties.as_deref(),
                    node.olp.as_deref(),
                ]) {
                    Ok(_) => {}
                    Err(rusqlite::Error::SqliteFailure(err, _))
                        if err.code == ErrorCode::ConstraintViolation =>
                    {
                        eprintln!(
                            "org-roam-sync warning: duplicate node ID {} in {}",
                            node.id, u.file
                        );
                    }
                    Err(e) => {
                        return Err(format!("insert node {} failed: {}", node.id, e));
                    }
                }
            }

            for (nid, alias) in &u.parsed.aliases {
                ins_alias
                    .execute(params![prin1_string(nid), prin1_string(alias)])
                    .map_err(|e| format!("insert alias failed: {}", e))?;
            }
            for (nid, tag) in &u.parsed.tags {
                ins_tag
                    .execute(params![prin1_string(nid), prin1_string(tag)])
                    .map_err(|e| format!("insert tag failed: {}", e))?;
            }
            for (nid, rval, rtype) in &u.parsed.refs {
                ins_ref
                    .execute(params![
                        prin1_string(nid),
                        prin1_string(rval),
                        prin1_string(rtype)
                    ])
                    .map_err(|e| format!("insert ref failed: {}", e))?;
            }
            for c in &u.parsed.citations {
                ins_cit
                    .execute(params![
                        prin1_string(&c.node_id),
                        prin1_string(&c.cite_key),
                        c.pos,
                        &c.properties
                    ])
                    .map_err(|e| format!("insert citation failed: {}", e))?;
            }
            for l in &u.parsed.links {
                ins_link
                    .execute(params![
                        l.pos,
                        prin1_string(&l.source),
                        prin1_string(&l.dest),
                        prin1_string(&l.link_type),
                        &l.properties
                    ])
                    .map_err(|e| format!("insert link failed: {}", e))?;
            }
        }
    }

    // Keep unused import check clean if opt_prin1_string isn't needed elsewhere
    let _ = opt_prin1_string;

    tx.commit()
        .map_err(|e| format!("commit transaction failed: {}", e))?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::parser::parse_org_file;
    use std::time::{SystemTime, UNIX_EPOCH};

    #[test]
    fn test_incremental_id_move_from_z_old_to_a_new() {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let tmp_dir = std::env::temp_dir().join(format!("orst-db-test-{}-{}", std::process::id(), nanos));
        fs::create_dir_all(&tmp_dir).unwrap();
        let db_path = tmp_dir.join("roam.db");

        let mut conn = open_db(&db_path, true).unwrap();
        let u1 = vec![
            FileUpdate {
                file: "/vault/a-new.org".to_string(),
                hash: "h1".to_string(),
                atime: "(0 0 0 0)".to_string(),
                mtime: "(0 0 0 0)".to_string(),
                parsed: parse_org_file(
                    "/vault/a-new.org",
                    ":PROPERTIES:\n:ID: other-id\n:END:\n#+title: A\n",
                ),
            },
            FileUpdate {
                file: "/vault/z-old.org".to_string(),
                hash: "h2".to_string(),
                atime: "(0 0 0 0)".to_string(),
                mtime: "(0 0 0 0)".to_string(),
                parsed: parse_org_file(
                    "/vault/z-old.org",
                    ":PROPERTIES:\n:ID: moved-id\n:END:\n#+title: Z\n",
                ),
            },
        ];
        apply_updates(&mut conn, &[], &u1).unwrap();

        // Move `moved-id` from `z-old.org` to `a-new.org` (which sorts earlier!)
        let u2 = vec![
            FileUpdate {
                file: "/vault/a-new.org".to_string(),
                hash: "h3".to_string(),
                atime: "(0 0 0 0)".to_string(),
                mtime: "(0 0 0 0)".to_string(),
                parsed: parse_org_file(
                    "/vault/a-new.org",
                    ":PROPERTIES:\n:ID: moved-id\n:END:\n#+title: A Moved\n#+filetags: :new:\n",
                ),
            },
            FileUpdate {
                file: "/vault/z-old.org".to_string(),
                hash: "h4".to_string(),
                atime: "(0 0 0 0)".to_string(),
                mtime: "(0 0 0 0)".to_string(),
                parsed: parse_org_file(
                    "/vault/z-old.org",
                    ":PROPERTIES:\n:ID: z-new-id\n:END:\n#+title: Z New\n",
                ),
            },
        ];
        apply_updates(&mut conn, &[], &u2).unwrap();

        let file_for_moved: String = conn
            .query_row(
                "SELECT file FROM nodes WHERE id = '\"moved-id\"'",
                [],
                |r| r.get(0),
            )
            .unwrap();
        assert_eq!(file_for_moved, "\"/vault/a-new.org\"");

        let tag_for_moved: String = conn
            .query_row(
                "SELECT tag FROM tags WHERE node_id = '\"moved-id\"'",
                [],
                |r| r.get(0),
            )
            .unwrap();
        assert_eq!(tag_for_moved, "\"new\"");

        drop(conn);
        let _ = fs::remove_dir_all(&tmp_dir);
    }
}
