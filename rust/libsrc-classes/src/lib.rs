//! Class index for the fenrir-libsrc engine (`lisp/languages/fenrir-libsrc.el`).
//!
//! Reads each jar's zip central directory and maps every simple class name to
//! the `g:a:v` artifacts that define it, in jar order.  The name and GAV rules
//! reproduce the Elisp ones this replaced -- including Emacs's default
//! `case-fold-search', under which the literal parts of those regexps (and the
//! `\2-\3` backreference) matched case-insensitively.

use std::collections::HashMap;
use std::hash::{BuildHasherDefault, Hasher};
use std::fs::File;
use std::io::{self, BufReader, Write};
use std::sync::atomic::{AtomicUsize, Ordering};

/// Simple class name for jar entry `entry`, or `None`.
///
/// Strips the package and any `$Inner` suffix; skips `module-info` and
/// `package-info`.  `Outer$1.class` is `Outer`; leading `$`s are skipped.
pub fn class_entry_name(entry: &str) -> Option<&str> {
    let comp = entry.rsplit('/').next().unwrap_or(entry);
    let b = comp.as_bytes();
    if b.len() < 6 || !b[b.len() - 6..].eq_ignore_ascii_case(b".class") {
        return None;
    }
    // The last 6 bytes are ASCII, so this is a char boundary.
    let stem = &comp[..comp.len() - 6];
    let name = stem.trim_start_matches('$').split('$').next().unwrap_or("");
    match name {
        "" | "module-info" | "package-info" => None,
        n => Some(n),
    }
}

/// The `g:a:v` of binary jar `jar`, or `None`.
///
/// Understands the `~/.m2` layout (slashed groupId) and the Gradle module
/// cache (`files-2.1/<dotted group>/<a>/<v>/<hash>/`).  Classifier jars, whose
/// file name is not exactly `<a>-<v>.jar`, have none.
pub fn jar_gav(jar: &str) -> Option<String> {
    let c: Vec<&str> = jar.split('/').collect();
    let n = c.len();
    let named = |a: &str, v: &str, file: &str| {
        !a.is_empty() && !v.is_empty() && file.eq_ignore_ascii_case(&format!("{a}-{v}.jar"))
    };
    // Gradle: /files-2.1/<g>/<a>/<v>/<hash>/<a>-<v>.jar
    if n >= 7 && c[n - 6].eq_ignore_ascii_case("files-2.1") {
        let (g, a, v, hash, file) = (c[n - 5], c[n - 4], c[n - 3], c[n - 2], c[n - 1]);
        if !g.is_empty() && !hash.is_empty() && named(a, v, file) {
            return Some(format!("{g}:{a}:{v}"));
        }
    }
    // Maven: /repository/<g/with/slashes>/<a>/<v>/<a>-<v>.jar
    if n >= 4 {
        let (a, v, file) = (c[n - 3], c[n - 2], c[n - 1]);
        if named(a, v, file) {
            let rest = c[..n - 3].join("/");
            let hay = format!("{rest}/");
            let needle = b"/repository/";
            let hb = hay.as_bytes();
            // Leftmost "/repository/" that leaves a non-empty groupId.
            for s in 0..hb.len().saturating_sub(needle.len() - 1) {
                if hb[s..s + needle.len()].eq_ignore_ascii_case(needle) {
                    let e = s + needle.len();
                    if e < rest.len() {
                        let g = rest[e..].replace('/', ".");
                        return Some(format!("{g}:{a}:{v}"));
                    }
                }
            }
        }
    }
    None
}

/// Every entry name in the jar at `path`.  A name the zip crate cannot
/// decode is skipped: it cannot be a class entry worth indexing.
pub fn jar_entries(path: &str) -> zip::result::ZipResult<Vec<String>> {
    let archive = zip::ZipArchive::new(BufReader::new(File::open(path)?))?;
    Ok(archive
        .file_names()
        .filter_map(Result::ok)
        .map(|n| n.into_owned())
        .collect())
}

/// The simple class names in the jar at `path`, duplicates included.
pub fn jar_classes(path: &str) -> zip::result::ZipResult<Vec<String>> {
    let archive = zip::ZipArchive::new(BufReader::new(File::open(path)?))?;
    Ok(archive
        .file_names()
        .filter_map(Result::ok)
        .filter_map(|n| class_entry_name(&n).map(str::to_owned))
        .collect())
}

/// FNV-1a: the index hashes ~70k short class names per run, where std's
/// DoS-resistant SipHash costs measurably more; inputs are local jar entries.
#[derive(Default)]
pub struct Fnv(u64);

impl Hasher for Fnv {
    fn finish(&self) -> u64 {
        self.0
    }
    fn write(&mut self, bytes: &[u8]) {
        let mut h = if self.0 == 0 { 0xcbf2_9ce4_8422_2325 } else { self.0 };
        for &b in bytes {
            h = (h ^ b as u64).wrapping_mul(0x0100_0000_01b3);
        }
        self.0 = h;
    }
}

/// Simple name -> GAVs, keys in first-seen order, GAVs in jar order.
/// GAVs are interned: each class holds small ids, not a string per class.
#[derive(Default, Debug)]
pub struct ClassIndex {
    gavs: Vec<String>,
    keys: Vec<String>,
    slots: HashMap<String, Vec<u32>, BuildHasherDefault<Fnv>>,
}

impl ClassIndex {
    /// Id of `gav`, adding it on first sight.  Called once per jar.
    pub fn intern(&mut self, gav: &str) -> u32 {
        match self.gavs.iter().position(|g| g == gav) {
            Some(i) => i as u32,
            None => {
                self.gavs.push(gav.to_owned());
                (self.gavs.len() - 1) as u32
            }
        }
    }

    /// Record that class `name` is defined by the GAV with id `gav`.
    pub fn add_id(&mut self, name: String, gav: u32) {
        match self.slots.get_mut(name.as_str()) {
            Some(ids) => {
                if !ids.contains(&gav) {
                    ids.push(gav);
                }
            }
            None => {
                self.keys.push(name.clone());
                self.slots.insert(name, vec![gav]);
            }
        }
    }

    pub fn add(&mut self, name: &str, gav: &str) {
        let id = self.intern(gav);
        self.add_id(name.to_owned(), id);
    }

    pub fn get(&self, name: &str) -> Option<Vec<&str>> {
        self.slots
            .get(name)
            .map(|ids| ids.iter().map(|&i| self.gavs[i as usize].as_str()).collect())
    }

    /// Class names in first-seen order.
    pub fn names(&self) -> impl Iterator<Item = &str> {
        self.keys.iter().map(String::as_str)
    }

    pub fn len(&self) -> usize {
        self.keys.len()
    }

    pub fn is_empty(&self) -> bool {
        self.keys.is_empty()
    }
}

/// Result of listing a set of jars.
#[derive(Default, Debug)]
pub struct Listing {
    pub index: ClassIndex,
    /// Jars that could not be read as zip archives, in input order.
    pub unreadable: Vec<String>,
}

type Read = zip::result::ZipResult<Vec<String>>;

/// `jar_classes` of every jar, read on up to `available_parallelism` threads
/// (the 57 MB kotlin-compiler jar alone is ~30 ms); results in input order.
fn read_all<S: AsRef<str> + Sync>(jars: &[S]) -> Vec<Read> {
    let workers = std::thread::available_parallelism().map_or(1, |n| n.get()).min(jars.len());
    if workers <= 1 {
        return jars.iter().map(|j| jar_classes(j.as_ref())).collect();
    }
    let next = AtomicUsize::new(0);
    let mut slots: Vec<Option<Read>> = (0..jars.len()).map(|_| None).collect();
    std::thread::scope(|s| {
        let handles: Vec<_> = (0..workers)
            .map(|_| {
                s.spawn(|| {
                    let mut done = Vec::new();
                    loop {
                        let i = next.fetch_add(1, Ordering::Relaxed);
                        if i >= jars.len() {
                            break done;
                        }
                        done.push((i, jar_classes(jars[i].as_ref())));
                    }
                })
            })
            .collect();
        for h in handles {
            for (i, r) in h.join().expect("jar reader thread panicked") {
                slots[i] = Some(r);
            }
        }
    });
    slots.into_iter().map(|r| r.expect("every jar read")).collect()
}

/// List every jar; index the classes of those with a GAV.
///
/// Jars without a GAV are still opened, so an unreadable one is reported the
/// same way whatever its path looks like.  Reading is parallel; indexing runs
/// in jar order, so GAV lists keep that order.
pub fn list_jars<S: AsRef<str> + Sync>(jars: &[S]) -> Listing {
    let mut out = Listing::default();
    for (jar, classes) in jars.iter().zip(read_all(jars)) {
        let jar = jar.as_ref();
        match classes {
            Err(_) => out.unreadable.push(jar.to_owned()),
            Ok(names) => {
                if let Some(gav) = jar_gav(jar) {
                    let id = out.index.intern(&gav);
                    for name in names {
                        out.index.add_id(name, id);
                    }
                }
            }
        }
    }
    out
}

fn lisp_string(w: &mut impl Write, s: &str) -> io::Result<()> {
    w.write_all(b"\"")?;
    for part in s.split_inclusive(['"', '\\']) {
        match part.as_bytes().last() {
            Some(b'"') | Some(b'\\') => {
                let (body, last) = part.split_at(part.len() - 1);
                w.write_all(body.as_bytes())?;
                w.write_all(b"\\")?;
                w.write_all(last.as_bytes())?;
            }
            _ => w.write_all(part.as_bytes())?,
        }
    }
    w.write_all(b"\"")
}

/// Write `listing` as one Lisp form the Elisp side `read`s:
/// `(:class-index #s(hash-table test equal data (NAME (GAV...) ...)) :unreadable (JAR...))`.
pub fn write_lisp(w: &mut impl Write, listing: &Listing) -> io::Result<()> {
    w.write_all(b"(:class-index #s(hash-table test equal data (")?;
    for (i, k) in listing.index.keys.iter().enumerate() {
        if i > 0 {
            w.write_all(b"\n")?;
        }
        lisp_string(w, k)?;
        w.write_all(b" (")?;
        for (j, &g) in listing.index.slots[k].iter().enumerate() {
            if j > 0 {
                w.write_all(b" ")?;
            }
            lisp_string(w, &listing.index.gavs[g as usize])?;
        }
        w.write_all(b")")?;
    }
    w.write_all(b"))\n :unreadable (")?;
    for (i, j) in listing.unreadable.iter().enumerate() {
        if i > 0 {
            w.write_all(b" ")?;
        }
        lisp_string(w, j)?;
    }
    w.write_all(b"))\n")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn class_names() {
        assert_eq!(
            class_entry_name("org/springframework/boot/info/GitProperties.class"),
            Some("GitProperties")
        );
        assert_eq!(
            class_entry_name("org/springframework/boot/info/InfoProperties$Entry.class"),
            Some("InfoProperties")
        );
        assert_eq!(class_entry_name("a/Outer$1.class"), Some("Outer"));
        assert_eq!(class_entry_name("Top.class"), Some("Top"));
        assert_eq!(class_entry_name("module-info.class"), None);
        assert_eq!(class_entry_name("META-INF/versions/9/module-info.class"), None);
        assert_eq!(class_entry_name("org/x/package-info.class"), None);
        assert_eq!(class_entry_name("org/x/"), None);
        assert_eq!(class_entry_name("META-INF/MANIFEST.MF"), None);
    }

    #[test]
    fn class_names_regexp_corners() {
        // What the old `\([^/$]+\)\(?:\$[^/]*\)?\.class\'` (case-folded) gave.
        assert_eq!(class_entry_name("x/$$Foo$Bar.class"), Some("Foo"));
        assert_eq!(class_entry_name("x/A$B$C.class"), Some("A"));
        assert_eq!(class_entry_name("x/Foo$.class"), Some("Foo"));
        assert_eq!(class_entry_name("x/Foo.CLASS"), Some("Foo"));
        assert_eq!(class_entry_name("x/$.class"), None);
        assert_eq!(class_entry_name(".class"), None);
        assert_eq!(class_entry_name("x/Ünï.class"), Some("Ünï"));
        assert_eq!(class_entry_name("x/ü.cl"), None);
    }

    #[test]
    fn gav_m2() {
        assert_eq!(
            jar_gav("/home/u/.m2/repository/org/springframework/boot/spring-boot/3.0.2/spring-boot-3.0.2.jar")
                .as_deref(),
            Some("org.springframework.boot:spring-boot:3.0.2")
        );
    }

    #[test]
    fn gav_gradle() {
        assert_eq!(
            jar_gav("/home/u/.gradle/caches/modules-2/files-2.1/org.springframework.boot/spring-boot/3.2.2/9f274d1bd822c4c57bb5b37ecae2380b980f567/spring-boot-3.2.2.jar")
                .as_deref(),
            Some("org.springframework.boot:spring-boot:3.2.2")
        );
    }

    #[test]
    fn gav_unparseable() {
        assert_eq!(
            jar_gav("/home/u/.m2/repository/io/netty/netty-x/4.1/netty-x-4.1-linux-x86_64.jar"),
            None
        );
        assert_eq!(jar_gav("/work/app/build/libs/app-1.0.jar"), None);
        assert_eq!(jar_gav("/work/app/target/classes"), None);
        // groupId must be non-empty
        assert_eq!(jar_gav("/h/repository/a/1/a-1.jar"), None);
    }

    #[test]
    fn gav_case_folded() {
        assert_eq!(jar_gav("/h/Repository/org/x/A/1/a-1.JAR").as_deref(), Some("org.x:A:1"));
    }

    #[test]
    fn index_order_and_dedup() {
        let mut ix = ClassIndex::default();
        ix.add("Foo", "org.x:a:1.0");
        ix.add("Foo", "org.y:b:2.0");
        ix.add("Foo", "org.x:a:1.0");
        ix.add("Bar", "org.y:b:2.0");
        assert_eq!(ix.get("Foo").unwrap(), ["org.x:a:1.0", "org.y:b:2.0"]);
        assert_eq!(ix.get("Bar").unwrap(), ["org.y:b:2.0"]);
        assert_eq!(ix.len(), 2);
    }

    #[test]
    fn lisp_escaping() {
        let mut v = Vec::new();
        lisp_string(&mut v, r#"a"b\c"#).unwrap();
        assert_eq!(String::from_utf8(v).unwrap(), r#""a\"b\\c""#);
    }
}
