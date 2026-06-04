// junit-core.cpp -- Emacs dynamic module: JUnit test discovery for Java files.
//
// Wraps the Emacs module ABI (emacs-module.h) in C++ and uses the tree-sitter
// C API (libtree-sitter runtime + the vendored tree-sitter-java grammar) to
// answer three questions about a Java source file on disk:
//
//   * (junit-core-class-info FILE)
//       -> plist (:package :class :fqcn :is-test-file :tool :directory) or nil
//   * (junit-core-method-at-line FILE LINE)        ; LINE is 1-based
//       -> plist (:method :class :test :begin-line :end-line) or nil
//   * (junit-core-command FILE LINE-or-nil)        ; nil LINE => whole-file scope
//       -> plist (:command :directory :tool :scope :class :method :description)
//          or nil
//
// The module deliberately stops at *command construction*: it figures out the
// build tool (maven vs gradle, walking up the directory tree), the enclosing
// test class / method, and the exact shell command -- but it does NOT run
// anything.  Process launching is the elisp wrapper's job via `compile'
// (see lisp/junit-runner.el), so the user gets compilation-mode error
// navigation and `recompile' for free.
//
// Build: see ../CMakeLists.txt and ../build.sh.  Requires libtree-sitter-dev
// (apt) for <tree_sitter/api.h> + -ltree-sitter; the grammar is compiled in
// from ../vendor/tree-sitter-java/parser.c.

#include <emacs-module.h>
#include <tree_sitter/api.h>

#include <cstdint>
#include <cstring>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>
#include <filesystem>

namespace fs = std::filesystem;

// Emacs requires this symbol to certify the module is GPL-compatible.
extern "C" int plugin_is_GPL_compatible;
int plugin_is_GPL_compatible;

// The vendored grammar exposes its language constructor with C linkage.
extern "C" const TSLanguage *tree_sitter_java(void);

namespace {

// ---------------------------------------------------------------------------
// Emacs value helpers
// ---------------------------------------------------------------------------

emacs_value Qnil(emacs_env *env) { return env->intern(env, "nil"); }
emacs_value Qt(emacs_env *env) { return env->intern(env, "t"); }

emacs_value mk_str(emacs_env *env, const std::string &s) {
  return env->make_string(env, s.data(), static_cast<ptrdiff_t>(s.size()));
}

// Read an Emacs string argument into a std::string (UTF-8 bytes).
// Returns false on a non-local exit or non-string value.
bool get_string(emacs_env *env, emacs_value v, std::string &out) {
  ptrdiff_t len = 0;
  if (!env->copy_string_contents(env, v, nullptr, &len))
    return false;  // signals wrong-type-argument on a non-string
  std::string buf(static_cast<size_t>(len), '\0');
  if (!env->copy_string_contents(env, v, buf.data(), &len))
    return false;
  buf.resize(static_cast<size_t>(len) - 1);  // drop the trailing NUL
  out = std::move(buf);
  return true;
}

// Build an Emacs list from a vector of values via the `list' function.
emacs_value mk_list(emacs_env *env, std::vector<emacs_value> &items) {
  emacs_value list = env->intern(env, "list");
  return env->funcall(env, list, static_cast<ptrdiff_t>(items.size()),
                      items.data());
}

// ---------------------------------------------------------------------------
// Java parsing (tree-sitter)
// ---------------------------------------------------------------------------

struct MethodInfo {
  std::string name;          // simple method name
  std::string class_binary;  // enclosing class chain joined by '$' (JVM binary)
  uint32_t begin_line = 0;   // 1-based, inclusive
  uint32_t end_line = 0;     // 1-based, inclusive
  bool is_test = false;      // carries a JUnit @Test-family annotation
};

struct ParseResult {
  bool ok = false;
  std::string package;        // dotted package, empty for default package
  std::string primary_class;  // first top-level type name (the test class)
  bool imports_junit = false;
  std::vector<MethodInfo> methods;
};

std::string node_text(TSNode n, const std::string &src) {
  uint32_t a = ts_node_start_byte(n);
  uint32_t b = ts_node_end_byte(n);
  if (b <= a || b > src.size()) return std::string();
  return src.substr(a, b - a);
}

// The JUnit 4 + 5 annotations that mark a method as a runnable test.
bool is_test_annotation_name(const std::string &simple) {
  static const char *kNames[] = {"Test",       "ParameterizedTest",
                                 "RepeatedTest", "TestFactory",
                                 "TestTemplate"};
  for (const char *n : kNames)
    if (simple == n) return true;
  return false;
}

// Last dotted segment of an annotation name, e.g.
// "org.junit.jupiter.api.Test" -> "Test", "Test" -> "Test".
std::string last_segment(const std::string &dotted) {
  auto pos = dotted.find_last_of('.');
  return pos == std::string::npos ? dotted : dotted.substr(pos + 1);
}

// Scan a method_declaration's `modifiers' child for a test annotation.
bool method_has_test_annotation(TSNode method, const std::string &src) {
  uint32_t n = ts_node_child_count(method);
  for (uint32_t i = 0; i < n; ++i) {
    TSNode child = ts_node_child(method, i);
    if (std::strcmp(ts_node_type(child), "modifiers") != 0) continue;
    uint32_t m = ts_node_child_count(child);
    for (uint32_t j = 0; j < m; ++j) {
      TSNode mod = ts_node_child(child, j);
      const char *t = ts_node_type(mod);
      if (std::strcmp(t, "marker_annotation") != 0 &&
          std::strcmp(t, "annotation") != 0)
        continue;
      TSNode name = ts_node_child_by_field_name(mod, "name", 4);
      if (ts_node_is_null(name)) continue;
      if (is_test_annotation_name(last_segment(node_text(name, src))))
        return true;
    }
  }
  return false;
}

const char *kTypeDecls[] = {"class_declaration", "interface_declaration",
                            "enum_declaration", "record_declaration",
                            "annotation_type_declaration"};
bool is_type_decl(const char *type) {
  for (const char *t : kTypeDecls)
    if (std::strcmp(type, t) == 0) return true;
  return false;
}

void walk(TSNode node, const std::string &src, std::vector<std::string> &stack,
          ParseResult &R) {
  const char *type = ts_node_type(node);

  if (std::strcmp(type, "package_declaration") == 0) {
    uint32_t n = ts_node_named_child_count(node);
    for (uint32_t i = 0; i < n; ++i) {
      TSNode c = ts_node_named_child(node, i);
      const char *ct = ts_node_type(c);
      if (std::strcmp(ct, "scoped_identifier") == 0 ||
          std::strcmp(ct, "identifier") == 0) {
        R.package = node_text(c, src);
        break;
      }
    }
    return;
  }

  if (std::strcmp(type, "import_declaration") == 0) {
    if (node_text(node, src).find("org.junit") != std::string::npos)
      R.imports_junit = true;
    return;
  }

  if (is_type_decl(type)) {
    TSNode name = ts_node_child_by_field_name(node, "name", 4);
    std::string cname = ts_node_is_null(name) ? std::string("?")
                                              : node_text(name, src);
    if (stack.empty() && R.primary_class.empty()) R.primary_class = cname;
    stack.push_back(cname);
    // Recurse into the body so nested types and their methods are visited.
    uint32_t n = ts_node_child_count(node);
    for (uint32_t i = 0; i < n; ++i) walk(ts_node_child(node, i), src, stack, R);
    stack.pop_back();
    return;
  }

  if (std::strcmp(type, "method_declaration") == 0) {
    TSNode name = ts_node_child_by_field_name(node, "name", 4);
    if (!ts_node_is_null(name)) {
      MethodInfo mi;
      mi.name = node_text(name, src);
      std::ostringstream bin;
      for (size_t i = 0; i < stack.size(); ++i) {
        if (i) bin << '$';
        bin << stack[i];
      }
      mi.class_binary = bin.str();
      mi.begin_line = ts_node_start_point(node).row + 1;  // 0-based -> 1-based
      mi.end_line = ts_node_end_point(node).row + 1;
      mi.is_test = method_has_test_annotation(node, src);
      R.methods.push_back(std::move(mi));
    }
    return;  // don't descend into local/anonymous classes inside a method body
  }

  uint32_t n = ts_node_child_count(node);
  for (uint32_t i = 0; i < n; ++i) walk(ts_node_child(node, i), src, stack, R);
}

bool read_file(const std::string &path, std::string &out) {
  std::ifstream in(path, std::ios::binary);
  if (!in) return false;
  std::ostringstream ss;
  ss << in.rdbuf();
  out = ss.str();
  return true;
}

ParseResult parse_java_file(const std::string &path) {
  ParseResult R;
  std::string src;
  if (!read_file(path, src)) return R;

  TSParser *parser = ts_parser_new();
  if (!ts_parser_set_language(parser, tree_sitter_java())) {
    ts_parser_delete(parser);
    return R;  // grammar/runtime ABI mismatch
  }
  TSTree *tree = ts_parser_parse_string(parser, nullptr, src.data(),
                                        static_cast<uint32_t>(src.size()));
  if (!tree) {
    ts_parser_delete(parser);
    return R;
  }
  std::vector<std::string> stack;
  walk(ts_tree_root_node(tree), src, stack, R);
  R.ok = true;

  ts_tree_delete(tree);
  ts_parser_delete(parser);
  return R;
}

// Index of the innermost method whose line range covers `line', or -1.
int method_index_at_line(const ParseResult &R, uint32_t line) {
  int best = -1;
  uint32_t best_begin = 0;
  for (size_t i = 0; i < R.methods.size(); ++i) {
    const MethodInfo &m = R.methods[i];
    if (line >= m.begin_line && line <= m.end_line && m.begin_line >= best_begin) {
      best = static_cast<int>(i);
      best_begin = m.begin_line;
    }
  }
  return best;
}

bool file_has_test(const ParseResult &R) {
  for (const auto &m : R.methods)
    if (m.is_test) return true;
  return false;
}

// ---------------------------------------------------------------------------
// Build-tool detection (walk up the directory tree)
// ---------------------------------------------------------------------------

struct ToolInfo {
  bool found = false;
  std::string tool;       // "maven" | "gradle"
  std::string directory;  // dir to run the command in
  std::string launcher;   // "mvn" | "./gradlew" | "gradle"
};

bool fs_exists(const fs::path &p) {
  std::error_code ec;
  return fs::exists(p, ec);
}

ToolInfo detect_tool(const std::string &file_path) {
  ToolInfo info;
  std::error_code ec;
  fs::path dir = fs::path(file_path).parent_path();

  std::string gradle_marker_dir;  // nearest dir with build.gradle*/settings.gradle*
  std::string gradlew_root;       // nearest dir with a gradlew wrapper (project root)

  for (fs::path d = dir;; d = d.parent_path()) {
    if (fs_exists(d / "pom.xml")) {
      // Nearest pom wins: the maven module directly containing the test.
      info.found = true;
      info.tool = "maven";
      info.directory = d.string();
      info.launcher = "mvn";
      return info;
    }
    if (gradle_marker_dir.empty() &&
        (fs_exists(d / "build.gradle") || fs_exists(d / "build.gradle.kts") ||
         fs_exists(d / "settings.gradle") || fs_exists(d / "settings.gradle.kts")))
      gradle_marker_dir = d.string();
    if (gradlew_root.empty() && fs_exists(d / "gradlew"))
      gradlew_root = d.string();

    fs::path parent = d.parent_path();
    if (parent == d || parent.empty()) break;  // reached filesystem root
  }

  if (!gradle_marker_dir.empty()) {
    info.found = true;
    info.tool = "gradle";
    if (!gradlew_root.empty()) {
      info.directory = gradlew_root;   // run from the wrapper's dir
      info.launcher = "./gradlew";
    } else {
      info.directory = gradle_marker_dir;
      info.launcher = "gradle";        // rely on a gradle on PATH
    }
  }
  return info;
}

// ---------------------------------------------------------------------------
// Command construction
// ---------------------------------------------------------------------------

std::string fqcn(const std::string &pkg, const std::string &class_part) {
  return pkg.empty() ? class_part : pkg + "." + class_part;
}

// ---------------------------------------------------------------------------
// Emacs-facing functions
// ---------------------------------------------------------------------------

emacs_value Fclass_info(emacs_env *env, ptrdiff_t nargs, emacs_value *args,
                        void *) noexcept {
  std::string path;
  if (nargs < 1 || !get_string(env, args[0], path)) return Qnil(env);
  ParseResult R = parse_java_file(path);
  if (!R.ok) return Qnil(env);
  ToolInfo tool = detect_tool(path);

  bool is_test = file_has_test(R) || R.imports_junit;
  std::vector<emacs_value> kv = {
      env->intern(env, ":package"),
      R.package.empty() ? Qnil(env) : mk_str(env, R.package),
      env->intern(env, ":class"),
      R.primary_class.empty() ? Qnil(env) : mk_str(env, R.primary_class),
      env->intern(env, ":fqcn"),
      R.primary_class.empty() ? Qnil(env)
                              : mk_str(env, fqcn(R.package, R.primary_class)),
      env->intern(env, ":is-test-file"), is_test ? Qt(env) : Qnil(env),
      env->intern(env, ":tool"),
      tool.found ? mk_str(env, tool.tool) : Qnil(env),
      env->intern(env, ":directory"),
      tool.found ? mk_str(env, tool.directory) : Qnil(env),
  };
  return mk_list(env, kv);
}

emacs_value Fmethod_at_line(emacs_env *env, ptrdiff_t nargs, emacs_value *args,
                            void *) noexcept {
  std::string path;
  if (nargs < 2 || !get_string(env, args[0], path)) return Qnil(env);
  intmax_t line = env->extract_integer(env, args[1]);
  if (env->non_local_exit_check(env) != emacs_funcall_exit_return)
    return Qnil(env);

  ParseResult R = parse_java_file(path);
  if (!R.ok) return Qnil(env);
  int idx = method_index_at_line(R, static_cast<uint32_t>(line));
  if (idx < 0) return Qnil(env);
  const MethodInfo &m = R.methods[idx];

  std::vector<emacs_value> kv = {
      env->intern(env, ":method"), mk_str(env, m.name),
      env->intern(env, ":class"), mk_str(env, m.class_binary),
      env->intern(env, ":test"), m.is_test ? Qt(env) : Qnil(env),
      env->intern(env, ":begin-line"),
      env->make_integer(env, m.begin_line),
      env->intern(env, ":end-line"), env->make_integer(env, m.end_line),
  };
  return mk_list(env, kv);
}

emacs_value Fcommand(emacs_env *env, ptrdiff_t nargs, emacs_value *args,
                     void *) noexcept {
  std::string path;
  if (nargs < 1 || !get_string(env, args[0], path)) return Qnil(env);

  // LINE: an integer => method scope at that 1-based line; nil/absent => file.
  bool method_scope = false;
  intmax_t line = 0;
  if (nargs >= 2 && env->is_not_nil(env, args[1])) {
    line = env->extract_integer(env, args[1]);
    if (env->non_local_exit_check(env) != emacs_funcall_exit_return)
      return Qnil(env);
    method_scope = true;
  }

  ParseResult R = parse_java_file(path);
  if (!R.ok || R.primary_class.empty()) return Qnil(env);
  ToolInfo tool = detect_tool(path);
  if (!tool.found) return Qnil(env);

  std::string scope;          // "method" | "file"
  std::string class_binary;   // class chain for the selected scope
  std::string method_name;    // empty for file scope
  std::string command;
  std::string description;

  if (method_scope) {
    int idx = method_index_at_line(R, static_cast<uint32_t>(line));
    if (idx < 0 || !R.methods[idx].is_test) return Qnil(env);
    const MethodInfo &m = R.methods[idx];
    scope = "method";
    class_binary = m.class_binary;
    method_name = m.name;
  } else {
    scope = "file";
    class_binary = R.primary_class;
  }

  const std::string full = fqcn(R.package, class_binary);

  if (tool.tool == "maven") {
    if (method_scope)
      command = "mvn test -Dtest='" + class_binary + "#" + method_name +
                "' -DfailIfNoTests=false";
    else
      command = "mvn test -Dtest='" + class_binary + "'";
  } else {  // gradle
    const std::string selector = method_scope ? full + "." + method_name : full;
    command = tool.launcher + " test --tests '" + selector + "'";
  }

  description = "JUnit (" + tool.tool + "): " +
                (method_scope ? class_binary + "#" + method_name : class_binary);

  std::vector<emacs_value> kv = {
      env->intern(env, ":command"), mk_str(env, command),
      env->intern(env, ":directory"), mk_str(env, tool.directory),
      env->intern(env, ":tool"), mk_str(env, tool.tool),
      env->intern(env, ":scope"), mk_str(env, scope),
      env->intern(env, ":class"), mk_str(env, full),
      env->intern(env, ":method"),
      method_name.empty() ? Qnil(env) : mk_str(env, method_name),
      env->intern(env, ":description"), mk_str(env, description),
  };
  return mk_list(env, kv);
}

// ---------------------------------------------------------------------------
// Registration
// ---------------------------------------------------------------------------

void bind_function(emacs_env *env, const char *name, emacs_value fn) {
  emacs_value fset = env->intern(env, "fset");
  emacs_value sym = env->intern(env, name);
  emacs_value args[] = {sym, fn};
  env->funcall(env, fset, 2, args);
}

void provide(emacs_env *env, const char *feature) {
  emacs_value provide_fn = env->intern(env, "provide");
  emacs_value sym = env->intern(env, feature);
  emacs_value args[] = {sym};
  env->funcall(env, provide_fn, 1, args);
}

}  // namespace

extern "C" int emacs_module_init(struct emacs_runtime *runtime) {
  // Refuse to load against an Emacs older than the headers we built against.
  if (static_cast<size_t>(runtime->size) < sizeof(*runtime)) return 1;
  emacs_env *env = runtime->get_environment(runtime);
  if (static_cast<size_t>(env->size) < sizeof(*env)) return 2;

  bind_function(
      env, "junit-core-class-info",
      env->make_function(env, 1, 1, Fclass_info,
                         "Return a plist describing the Java file FILE.\n"
                         "Keys: :package :class :fqcn :is-test-file :tool "
                         ":directory.  Returns nil if FILE cannot be parsed.\n"
                         "\n(fn FILE)",
                         nullptr));
  bind_function(
      env, "junit-core-method-at-line",
      env->make_function(env, 2, 2, Fmethod_at_line,
                         "Return a plist for the method enclosing LINE in FILE.\n"
                         "LINE is 1-based.  Keys: :method :class :test "
                         ":begin-line :end-line.  Returns nil if no method "
                         "covers LINE.\n\n(fn FILE LINE)",
                         nullptr));
  bind_function(
      env, "junit-core-command",
      env->make_function(env, 1, 2, Fcommand,
                         "Return a plist describing how to run a JUnit test.\n"
                         "With a non-nil 1-based LINE, target the @Test method "
                         "at LINE; otherwise target the whole file.\n"
                         "Keys: :command :directory :tool :scope :class "
                         ":method :description.  Returns nil when there is no "
                         "runnable test or no build tool.\n\n(fn FILE &optional "
                         "LINE)",
                         nullptr));

  provide(env, "junit-core");
  return 0;
}
