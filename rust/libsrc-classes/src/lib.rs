//! Class index for the fenrir-libsrc engine (`lisp/languages/fenrir-libsrc.el`).
//!
//! Reads each jar's zip central directory and maps every simple class name to
//! the `g:a:v` artifacts that define it, in jar order.  The name and GAV rules
//! reproduce the Elisp ones this replaced -- including Emacs's default
//! `case-fold-search', under which the literal parts of those regexps (and the
//! `\2-\3` backreference) matched case-insensitively.

use std::collections::HashMap;
use std::fs::File;
use std::io::{self, Write};

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
    let archive = zip::ZipArchive::new(File::open(path)?)?;
    Ok(archive
        .file_names()
        .filter_map(Result::ok)
        .map(|n| n.into_owned())
        .collect())
}

/// Simple name -> GAVs, keys in first-seen order, GAVs in jar order.
#[derive(Default, Debug)]
pub struct ClassIndex {
    keys: Vec<String>,
    slots: HashMap<String, Vec<String>>,
}

impl ClassIndex {
    pub fn add(&mut self, name: &str, gav: &str) {
        match self.slots.get_mut(name) {
            Some(gavs) => {
                if !gavs.iter().any(|g| g == gav) {
                    gavs.push(gav.to_owned());
                }
            }
            None => {
                self.keys.push(name.to_owned());
                self.slots.insert(name.to_owned(), vec![gav.to_owned()]);
            }
        }
    }

    pub fn get(&self, name: &str) -> Option<&[String]> {
        self.slots.get(name).map(Vec::as_slice)
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

/// List every jar; index the classes of those with a GAV.
///
/// Jars without a GAV are still opened, so an unreadable one is reported the
/// same way whatever its path looks like.
pub fn list_jars<S: AsRef<str>>(jars: &[S]) -> Listing {
    let mut out = Listing::default();
    for jar in jars {
        let jar = jar.as_ref();
        match jar_entries(jar) {
            Err(_) => out.unreadable.push(jar.to_owned()),
            Ok(names) => {
                if let Some(gav) = jar_gav(jar) {
                    for name in names.iter().filter_map(|e| class_entry_name(e)) {
                        out.index.add(name, &gav);
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
        for (j, g) in listing.index.slots[k].iter().enumerate() {
            if j > 0 {
                w.write_all(b" ")?;
            }
            lisp_string(w, g)?;
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
        assert_eq!(ix.len(), 2);
    }

    #[test]
    fn lisp_escaping() {
        let mut v = Vec::new();
        lisp_string(&mut v, r#"a"b\c"#).unwrap();
        assert_eq!(String::from_utf8(v).unwrap(), r#""a\"b\\c""#);
    }
}
