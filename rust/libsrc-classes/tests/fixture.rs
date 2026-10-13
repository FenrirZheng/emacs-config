//! 驗收條件 4 (helper side): a broken and a missing jar beside three real ones.
//!
//! Real jars: the first 3 `:jars` of kjw-web's libsrc state file.  Writes
//! /tmp/libsrc-classes-fixture/broken.jar; without the state file (another
//! machine) the test says so and checks nothing.

use std::fs;
use std::path::Path;

const STATE: &str = ".cache/fenrir-libsrc/proj/0c3182fdef74a5edb107922b61083d9364653696.eld";
const DIR: &str = "/tmp/libsrc-classes-fixture";

/// The first `n` strings of the `:jars (...)` list in the state file.
fn fixture_jars(n: usize) -> Option<Vec<String>> {
    let home = std::env::var("HOME").ok()?;
    let text = fs::read_to_string(Path::new(&home).join(STATE)).ok()?;
    let mut rest = &text[text.find(":jars (")? + ":jars (".len()..];
    let mut jars = Vec::new();
    while jars.len() < n {
        rest = rest.trim_start();
        if !rest.starts_with('"') {
            break;
        }
        let end = rest[1..].find('"')? + 1;
        jars.push(rest[1..end].to_owned());
        rest = &rest[end + 1..];
    }
    (jars.len() == n || (n == usize::MAX && !jars.is_empty())).then_some(jars)
}

/// Index and unreadable list of `[broken, missing] + good`, checked against
/// `good` listed alone: the bad jars must not change the good jars' index.
fn check_mixed(good: &[String]) -> usize {
    fs::create_dir_all(DIR).unwrap();
    let broken = format!("{DIR}/broken.jar");
    let missing = format!("{DIR}/missing.jar");
    fs::write(&broken, "not a zip").unwrap();
    let _ = fs::remove_file(&missing);

    let mut input = vec![broken.clone(), missing.clone()];
    input.extend(good.iter().cloned());
    let mixed = libsrc_classes::list_jars(&input);
    let alone = libsrc_classes::list_jars(good);

    assert_eq!(mixed.unreadable, [broken, missing]);
    assert!(alone.unreadable.is_empty(), "fixture jars unreadable: {:?}", alone.unreadable);
    assert_eq!(mixed.index.len(), alone.index.len());
    for name in alone.index.names() {
        assert_eq!(mixed.index.get(name), alone.index.get(name), "{name}");
    }
    alone.index.len()
}

/// The literal input: the first 3 fixture jars.  On kjw-web they are Spring
/// Boot starters with no classes, so this case shows only the unreadable list.
#[test]
fn broken_and_missing_beside_first_three_fixture_jars() {
    let Some(jars) = fixture_jars(3) else {
        eprintln!("SKIPPED: no kjw-web libsrc state file under $HOME/{STATE}");
        return;
    };
    check_mixed(&jars);
}

/// The same with the first fixture jar that does define classes, so the
/// good-jar index is not empty.
#[test]
fn broken_and_missing_beside_a_class_bearing_jar() {
    let Some(jars) = fixture_jars(usize::MAX) else {
        eprintln!("SKIPPED: no kjw-web libsrc state file under $HOME/{STATE}");
        return;
    };
    let jar = jars
        .into_iter()
        .find(|j| !libsrc_classes::list_jars(&[j.clone()]).index.is_empty())
        .expect("no fixture jar defines a class");
    assert!(check_mixed(&[jar]) > 0);
}
