# Snippets / Templates — TempEl + YASnippet

How code templates work in this config, the full per-language trigger catalog, and how to
add your own. Companion to [the snippets section of FEATURES.md](../FEATURES.md) (the
"what keys" cheat sheet); the engine wiring lives in
[`lisp/init-snippets.el`](../lisp/init-snippets.el) and the templates themselves in the
[`templates`](../templates) file at the repo root.

Sibling language guides: [Go](GO.md), [Java](JAVA.md).

---

## 1. Architecture — two engines, split by job

This config runs **two** template engines, each doing only what it is best at (decided
2026-06-01 after a maintenance / built-in survey):

| Engine | Role | Why |
|---|---|---|
| **TempEl** | THE engine for hand-written templates | On GNU ELPA, actively maintained by minad (same author as vertico / corfu / consult / orderless — all already here), and it reuses the syntax of the **built-in `tempo.el`**, so it is the closest "official-flavoured" choice short of using core tempo/skeleton directly. |
| **YASnippet** | ONLY Eglot's LSP snippet expander | YASnippet's upkeep has slowed, but Eglot still delegates LSP snippet expansion (e.g. a language server completing a call with parameter placeholders) to `yas-expand-snippet`. So it is enabled **narrowly** on `eglot-managed-mode-hook`, not globally. |

Consequences of the split:

- Hand-written snippets are **TempEl's** job. There is no `yas-global-mode` and no
  `yasnippet-snippets` collection.
- YASnippet stays **dormant** everywhere Eglot isn't managing the buffer. With no snippet
  tables loaded, its `TAB` is a harmless pass-through to the normal indent/complete command.
- TempEl is surfaced through `completion-at-point-functions`, so it rides the **same
  `consult-completion-in-region` (Vertico minibuffer)** path as every other in-buffer
  completion — no Corfu popup required (`global-corfu-mode` is intentionally off; see
  [`lisp/init-corfu.el`](../lisp/init-corfu.el)).

---

## 2. Using templates

### Trigger keys

| Key | Command | What it does |
|---|---|---|
| `C-<tab>` | `completion-at-point` | Type a trigger name (e.g. `iferr`) then `C-<tab>` — `tempel-expand` completes and expands it inline. Also fires Eglot / cape. (Replaces the Emacs default `M-TAB`, which GNOME swallows as Alt+Tab.) |
| `C-M-i` | `completion-at-point` | Same as `C-<tab>` (Emacs default, also works). |
| `M-+` | `tempel-complete` | List **every** template for the current mode and expand the chosen one. |
| `M-*` | `tempel-insert` | Insert a template **by name** via the minibuffer (Vertico browse). |
| `TAB` / `S-TAB` | `tempel-next` / `tempel-previous` | While a template is active, jump to the next / previous field. |
| `C-g` | — | Exit the active template, leaving the text as-is. |

### There is no auto-popup

`corfu-auto` is off, so **typing `iferr` shows nothing on its own** — completion is manual.
Press `C-<tab>` (or `M-+` / `M-*`). This is deliberate; the trade-off and how to flip to an
auto-popup workflow are documented in [`lisp/init-corfu.el`](../lisp/init-corfu.el).

### Discovering what's available

You never need to memorise trigger names. In any buffer press **`M-*`** (`tempel-insert`)
and Vertico lists every template valid for that mode — type to filter, `RET` to insert. The
full catalog below is just an offline reference. Note that in a code buffer the **Global**
and **All code** groups are merged in alongside the language-specific ones.

---

## 3. Template catalog (by mode)

Generated from the [`templates`](../templates) file. In any given buffer you see the
language section **plus** the `prog-mode` ("All code") section **plus** the global
`fundamental-mode` section.

### Global (every buffer) (`fundamental-mode`)

Universal date/time stamps, dividers, and comment-tag helpers available in all buffers.

| Trigger | Expands to |
|---|---|
| `today` | Current date in `YYYY-MM-DD` format |
| `now` | Current date and time in `YYYY-MM-DD HH:MM` format |
| `nowtz` | Current date, time, and timezone offset in `YYYY-MM-DD HH:MM z` format |
| `time` | Current time in `HH:MM:SS` format |
| `iso` | ISO 8601 timestamp with timezone in `YYYY-MM-DDTHH:MM:SSz` format |
| `stamp` | `YYYY-MM-DD HH:MM` plus editable field (cursor stop) |
| `date` | Current date in `YYYYMMDD` format |
| `div` | Comment prefix (if any) followed by dashes: `----------------------------------------` |
| `box` | Boxed title with 60-char borders: comment prefix + `=`×60, title line, `=`×60 |
| `sep` | 72-character dash divider |
| `todo` | Comment prefix + ` TODO: ` plus editable field |
| `fixme` | Comment prefix + ` FIXME: ` plus editable field |

### All code (prog-mode) (`prog-mode`)

Language-agnostic comment templates that adapt to each language's comment syntax via `comment-start`.

| Trigger | Expands to |
|---|---|
| `note` | `NOTE: ` + editable field (adapts comment syntax per language) |
| `hack` | `HACK: ` + editable field (adapts comment syntax per language) |
| `xxx` | `XXX: ` + editable field (adapts comment syntax per language) |
| `bug` | `BUG: ` + editable field (adapts comment syntax per language) |
| `optimize` | `OPTIMIZE: ` + editable field (adapts comment syntax per language) |
| `noteauthor` | `NOTE(` + username + `): ` + editable field (adapts comment syntax per language) |
| `todoauthor` | `TODO(` + username + `): ` + editable field (adapts comment syntax per language) |
| `datedtodo` | `TODO(` + YYYY-MM-DD + `): ` + editable field (adapts comment syntax per language) |
| `banner` | `==========…==========` section divider with named field for title; final cursor after bottom divider |

### Emacs Lisp (`emacs-lisp-mode`)

Templates for defining Lisp code structure and common patterns like functions, custom variables, and control flow constructs.

| Trigger | Expands to |
|---|---|
| `header` | File header with module docstring, commentary, code section markers, and `lexical-binding: t` |
| `provide` | `(provide 'module)` statement with corresponding `.el ends here` footer comment |
| `defun` | `(defun name () "docstring" …)` function definition with prompts for name, params, docstring, and body |
| `cmd` | `(defun name () "docstring" (interactive) …)` interactive command with region or insertion point |
| `defvar` | `(defvar name value "docstring")` variable declaration |
| `defcustom` | `(defcustom name value "docstring" :type 'boolean :group '...)` customizable variable with type and group |
| `let` | `(let ((var val)) …)` lexical binding with single variable and body |
| `lets` | `(let* ((var val)) …)` sequential let bindings with dependent variables |
| `use` | `(use-package pkg :ensure t …)` package configuration block |
| `weval` | `(with-eval-after-load 'feature …)` deferred evaluation after feature load |
| `hook` | `(add-hook 'mode-hook #'function)` hook registration for major mode |
| `dolist` | `(dolist (x list) …)` list iteration macro with item and list parameters |
| `when` | `(when cond …)` conditional execution block |
| `setf` | `(setf (alist-get :key alist) value)` association list key-value update |

### Go (`go-ts-mode`)

Function, method, struct, interface, and control flow templates for Go with common patterns like error handling and testing.

| Trigger | Expands to |
|---|---|
| `func` | `func name(…) … { … }` with name and signature fields |
| `meth` | Method receiver syntax: `func (r Type) name(…) … { … }` with receiver and type |
| `struct` | Type struct with constructor: `type Name struct { … }` mirrored into `NewName(…) *Name { … }` |
| `iface` | `type Name interface { … }` for interface definition |
| `iferr` | `if err != nil { return … }` with return value field |
| `wraperr` | `return fmt.Errorf("context: %w", err)` with context field |
| `test` | `func TestName(t *testing.T) { tests := []struct { … }; for _, tt := range tests { t.Run(…) } }` |
| `main` | `func main() { … }` with region placeholder |
| `pkg` | `package name` with import block, name defaulted to filename |
| `goroutine` | `go func() { … }()` anonymous goroutine with region |
| `chan` | `ch := make(chan T)` with channel name and type fields |
| `defer` | `defer …` statement |
| `println` | `fmt.Println(…)` with region |
| `for` | C-style loop: `for i := 0; i < n; i++ { … }` with i mirrored across bounds |
| `forr` | Range loop: `for i, v := range coll { … }` with index, value, collection fields |
| `forc` | Conditional loop: `for cond { … }` |
| `forinf` | Infinite loop: `for { … }` |

### Python (`python-ts-mode python-mode`)

Provides templates for functions, classes, testing, control flow, comprehensions, logging, docstrings, and imports.

| Trigger | Expands to |
|---|---|
| `def` | Function definition with name, parameters, return type annotation, docstring, and body |
| `adef` | Async function definition with name, parameters, return type annotation, and body |
| `m` | Method definition with `self`, parameters, return type annotation, and body |
| `class` | Class with docstring, `__init__` constructor with self and parameters, return type |
| `dataclass` | `@dataclass` decorator with class definition, field name, and type annotation |
| `main` | Main entry point function with `if __name__ == "__main__":` guard |
| `ifmain` | `if __name__ == "__main__":` block |
| `test` | Pytest test function with `test_` prefix, parameters, return type, and body |
| `fixture` | `@pytest.fixture` decorated function with return statement |
| `param` | `@pytest.mark.parametrize` decorator (arg name mirrored into test function signature) with test function |
| `try` | `try:` block with `except` clause capturing exception as variable |
| `tryf` | `try:` block with `except` clause and `finally:` block |
| `with` | `with` statement binding expression to variable with indented body |
| `forr` | `for item in iterable:` loop with body (item name mirrored as field) |
| `whilet` | `while condition:` loop with body |
| `lc` | List comprehension `[expr for x in iterable]` (x named for potential mirror) |
| `dc` | Dict comprehension `{k: v for x in iterable}` (x named for potential mirror) |
| `log` | Logger method call with f-string `logger.info(f"…")` |
| `fstr` | F-string literal `f"…"` |
| `doc` | Google-style docstring with summary, Args, Returns, Raises sections |
| `imp` | `import module` statement |
| `from` | `from module import names` statement |

### Rust (`rust-ts-mode`)

Function and struct definitions, control flow, and common testing patterns for Rust.

| Trigger | Expands to |
|---|---|
| `fn` | `fn name(…) -> () { … }` with name, params, return type, and body |
| `pfn` | `pub fn name(…) -> () { … }` (public function) |
| `struct` | `struct Name { … }` with impl block and `new()` constructor, name mirrored throughout |
| `enum` | `enum Name { … }` with variants |
| `impl` | `impl Type { … }` for inherent implementation |
| `implt` | `impl Trait for Type { … }` for trait implementation |
| `trait` | `trait Name { fn …(&self)…; }` with method signature |
| `der` | `#[derive(Debug, Clone)]` attribute |
| `match` | `match expr { pattern => …, _ => … }` with arm patterns |
| `iflet` | `if let Some(x) = opt { … }` pattern matching |
| `tryret` | `fn name(…) -> Result<(), Box<dyn std::error::Error>> { … Ok(()) }` function returning Result |
| `test` | `#[test]` annotated test function |
| `ttest` | `#[tokio::test]` async test function |
| `doc` | `/// …` doc comment line |
| `pln` | `println!("…", …);` print statement |
| `dbg` | `dbg!(…);` debug macro with region |
| `map` | `let mut map = std::collections::HashMap::new();` with name mirrored into `.insert()` call |

### Java (`java-ts-mode java-mode`)

Templates for Java package, class, and method scaffolding, with control flow and Spring REST patterns.

| Trigger | Expands to |
|---|---|
| `pkg` | `package com.example;` with editable package name |
| `class` | `public class Name { … }` with mirrored class name |
| `iclass` | `public final class Name { private Name(…) { … } }` immutable class pattern with mirrored name |
| `interface` | `public interface Name { … }` with editable name |
| `enum` | `public enum Name { …; … }` with enum values field |
| `record` | `public record Name(…) { … }` with mirrored record name |
| `ctor` | `public Name(…) { … }` constructor with mirrored class name |
| `method` | `public void name(…) { … }` method with return type and parameters |
| `sm` | `public static void name(…) { … }` static method with return type and parameters |
| `get` | `public Type getField() { return this.field; }` getter with mirrored field name |
| `set` | `public void setField(Type value) { this.field = value; }` setter with mirrored field and value names |
| `foreach` | `for (Type item : items) { … }` enhanced for loop with mirrored item name |
| `fori` | `for (int i = 0; i < n; i++) { … }` C-style for loop with mirrored counter |
| `try` | `try { … } catch (Exception e) { throw new RuntimeException(e); }` exception handler with mirrored exception |
| `trf` | `try { … } catch (Exception e) { … } finally { … }` try-catch-finally with separate fields |
| `sout` | `System.out.println(…);` print statement with region or field |
| `controller` | `@RestController @RequestMapping("/api") public class NameController { … }` Spring REST controller |
| `getm` | `@GetMapping("/path") public ResponseEntity<?> handle(…) { return …; }` Spring GET endpoint |
| `postm` | `@PostMapping("/path") public ResponseEntity<?> handle(@RequestBody Type body) { return …; }` Spring POST endpoint |
| `test` | `@Test void should() { … }` JUnit test method |
| `testt` | `@Test @DisplayName("description") void name() { …; assertEquals(expected, actual); }` JUnit test with display name and assertion |
| `beforeeach` | `@BeforeEach void setUp() { … }` JUnit setup method |
| `doc` | `/** … */` Javadoc comment block with region |
| `param` | `@param name` Javadoc parameter tag |
| `main` | `public static void main(String[] args) { … }` main method entry point |

### TypeScript / TSX / JS (`typescript-ts-mode tsx-ts-mode js-ts-mode`)

Comprehensive templates for modern JavaScript/TypeScript covering imports, functions, React components, type definitions, and testing patterns.

| Trigger | Expands to |
|---|---|
| `im` | `import { names } from "module";` with editable names and module |
| `imd` | `import default from "module";` with editable default and module |
| `imp` | `import * as ns from "module";` with editable namespace and module |
| `exp` | `export { names } from "module";` with editable names and module |
| `fn` | `function name(…): void { … }` with editable name, params, and return type |
| `afn` | `async function name(…): Promise<void> { … }` with editable name, params, and return type |
| `arrow` | `const name = (…) => { … };` with editable name and params |
| `aarrow` | `const name = async (…) => { … };` with editable name and params |
| `int` | `interface Name { field: type; }` with field and type editable |
| `type` | `type Name = …;` with editable type definition |
| `enum` | `enum Name { Member, }` with editable name and members |
| `cls` | `class Name { constructor(…) { … } }` with editable name and constructor body |
| `comp` | React functional component with Props interface and name mirrored into export; component signature and JSX editable |
| `rafc` | React arrow function component with Props interface; name mirrored into type and export; props and JSX editable |
| `ust` | `const [state, setState] = useState<type>(initial);` with editable state name, type, and initial value |
| `ue` | `useEffect(() => { … return () => { … }; }, […]);` with setup, cleanup, and dependency array editable |
| `tc` | `try { … } catch (err) { console.error(err); }` with try body and catch handler editable |
| `tcf` | `try { … } catch (err) { … } finally { … }` with try, catch, and finally bodies editable |
| `desc` | `describe("subject", () => { it("should do something", () => { … }); });` with subject, test description, and body editable |
| `it` | `it("should do something", () => { … });` with description and body editable |
| `cl` | `console.log(…);` with argument editable |
| `cle` | `console.error(…);` with argument editable |

### C / C++ (`c-ts-mode c++-ts-mode c-mode c++-mode`)

Templates for common C and C++ code patterns including includes, functions, types, and control flow.

| Trigger | Expands to |
|---|---|
| `inc` | `#include <header>` |
| `incl` | `#include "header"` |
| `guard` | `#ifndef FILENAME_H`, `#define FILENAME_H`, region placeholder, `#endif /* FILENAME_H */` with filename mirrored |
| `def` | `#define MACRO` with value placeholder |
| `pragma` | `#pragma once` |
| `fun` | Function with return type, name, params, and body placeholder |
| `main` | `int main(int argc, char **argv) { … return 0; }` |
| `struct` | `struct Name { … }; typedef struct Name Name;` with name mirrored |
| `enum` | `enum Name { … };` |
| `class` | C++ class with public constructor/destructor and private section (name mirrored) |
| `ns` | `namespace name { … } // namespace name` with name mirrored |
| `for` | `for (int i = 0; i < n; ++i) { … }` |
| `forr` | `for (size_t i = 0; i < n; ++i) { … }` range loop with index mirrored |
| `fore` | `for (const auto& x : container) { … }` range-based for loop |
| `while` | `while (cond) { … }` |
| `ifel` | `if (cond) { … } else { … }` |
| `sw` | `switch (x) { case v: … break; default: … break; }` |
| `pf` | `printf("%d\n", …);` |
| `cout` | `std::cout << x << std::endl;` |
| `vec` | `std::vector<int> v;` |
| `iter` | `for (auto it = v.begin(); it != v.end(); ++it) { … }` with vector variable mirrored |
| `doc` | Javadoc-style block comment with summary, `@param`, and `@return` placeholders |

### Lua (`lua-mode`)

Standard Lua function, control flow, and module templates for common patterns.

| Trigger | Expands to |
|---|---|
| `fun` | `function name(args) … end` |
| `lfun` | `local function name(args) … end` |
| `mod` | Local module table with named function definition and return statement, module name mirrored |
| `meth` | `function M:name(args) … end` (colon syntax for methods) |
| `ipairs` | `for i, v in ipairs(t) do … end` |
| `pairs` | `for k, v in pairs(t) do … end` |
| `fornum` | `for i = 1, n do … end` (numeric loop) |
| `if` | `if cond then … elseif cond2 then … else … end` |
| `while` | `while cond do … end` |
| `req` | `local name = require("module")` |
| `pcall` | `local ok, err = pcall(fn, ...) if not ok then … end` |
| `meta` | Metatables with `__index` self-reference, `new()` constructor, and `setmetatable()` call, class name mirrored |

### Markdown / GFM (`markdown-mode gfm-mode`)

Markdown templates for code blocks, links, images, tables, task lists, collapsible sections, and text formatting.

| Trigger | Expands to |
|---|---|
| `code` | Fenced code block with language placeholder |
| `link` | Inline link: `[label](path)` |
| `img` | Image with alt text: `![alt](path)` |
| `table` | 2-column table skeleton with header separator and one data row |
| `task` | Task list item: `- [ ] task` |
| `details` | Collapsible HTML block: `<details><summary>summary</summary>…</details>` |
| `fm` | YAML front-matter block with title, date, and tags fields |
| `ha` | Heading with explicit anchor: `## Heading {#anchor}` |
| `bq` | Blockquote wrapping region: `> …` |
| `fn` | Footnote with reference and definition: `[^id]` and `[^id]: note` |
| `b` | Bold wrapper around region: `**…**` |
| `i` | Italic wrapper around region: `*…*` |

### Org (`org-mode`)

Templates for common Org-mode structures: source blocks, headings with metadata, scheduling, and cross-references.

| Trigger | Expands to |
|---|---|
| `src` | `#+begin_src LANG` with region inside and `#+end_src` closing |
| `example` | `#+begin_example` … `#+end_example` block with region content |
| `quote` | `#+begin_quote` … `#+end_quote` block with region content |
| `todo` | `* TODO` heading with task name and auto-timestamped PROPERTIES drawer (CREATED) |
| `head` | `*` heading with title and PROPERTIES drawer containing ID field |
| `props` | Bare `:PROPERTIES:` … `:END:` drawer with key-value pairs |
| `sched` | `SCHEDULED: <DATE>` timestamp (date field pre-filled with today) |
| `dead` | `DEADLINE: <DATE>` timestamp (date field pre-filled with today) |
| `clock` | `* TASK` heading with `CLOCK:` timestamp (auto-inserted current time) |
| `table` | 2-column table skeleton with header separator `\|---+---\|` |
| `link` | `[[TARGET][DESCRIPTION]]` Org link with target and description fields |
| `fn` | Footnote reference `[fn:LABEL]` with definition `[fn:LABEL]:` (label mirrored) |
| `header` | Document header with `#+title:`, `#+author:` (pre-filled "fenrir"), and `#+date:` fields |

### CSS / HTML (`css-mode html-mode mhtml-mode`)

CSS and HTML template snippets for styling rules, layout patterns, and common HTML elements.

| Trigger | Expands to |
|---|---|
| `rule` | CSS rule: `selector { … }` with property prompt |
| `cls` | CSS class selector: `.class { … }` with property prompt |
| `id` | CSS ID selector: `#id { … }` with property prompt |
| `flex` | Flexbox layout: `display: flex` with direction, justify-content, align-items, and gap fields |
| `grid` | Grid layout: `display: grid` with template-columns and gap fields |
| `media` | Media query: `@media (max-width: 768px) { selector { … } }` |
| `var` | CSS custom property: `:root { --name: value; }` with mirrored name in definition |
| `varu` | CSS variable usage: `var(--name)` mirrors name from `var` template |
| `kf` | Keyframe animation: `@keyframes name { from { … } to { … } }` |
| `trans` | CSS transition property: `transition: all 0.2s ease;` with all three fields editable |
| `html5` | HTML5 boilerplate: `<!DOCTYPE html>` with charset, viewport, title, body placeholders |
| `div` | HTML div with class: `<div class="class">…</div>` |
| `span` | HTML span with class: `<span class="class">…</span>` with inline content |
| `a` | HTML anchor: `<a href="#">text</a>` with URL and text fields |
| `img` | HTML image: `<img src="path" alt="alt">` with path and alt fields |
| `ul` | Unordered list: `<ul><li>…</li></ul>` with item content |
| `input` | Labeled input: `<label for="id">Label</label><input type="text" id="id" name="id">` with id mirrored across label, input id, and name |
| `form` | HTML form: `<form action="#" method="post">…<button type="submit">Submit</button></form>` |
| `script` | Script tag: `<script src="script.js"></script>` with src editable |
| `link` | Stylesheet link: `<link rel="stylesheet" href="style.css">` with href editable |
| `tag` | Generic HTML tag: `<tag>…</tag>` with tag name mirrored in opening and closing tags |

---

## 4. Writing your own templates

### Where they live

All templates are in the single [`templates`](../templates) file at the repo root. This path
is set **explicitly** in [`lisp/init-snippets.el`](../lisp/init-snippets.el) via
`tempel-path` — a deliberate override of no-littering, which otherwise redirects the default
to `etc/tempel/templates.eld` (gitignored). Our templates are hand-authored **config** we
want version-controlled, not state, so they stay at the repo root. (See §5.)

### File format

The file is a sequence of Lisp forms read by tempel:

- A **bare symbol** line names the major mode(s) the following templates apply to, e.g.
  `go-ts-mode`, or several space-separated: `c-ts-mode c++-ts-mode c-mode c++-mode`.
- A **list** `(name element element …)` is one template. `name` is the trigger you type.
- `fundamental-mode` templates are **global** (every buffer); `prog-mode` templates apply to
  **all** programming modes. tempel matches a section if the buffer's major mode is — or
  derives from — one of the listed modes.

### Tempel element syntax (it is tempo's, NOT yasnippet's)

| Element | Meaning |
|---|---|
| `"text"` | literal string |
| `p` / `(p "PROMPT")` | an editable field / tab-stop (cursor stops here) |
| `(p "DEFAULT" name)` | a **named** field (so it can be mirrored) |
| `(p form name t)` | field whose value is computed but not inserted (source for a mirror) |
| `(s name)` | insert (mirror) the text of a previously-named field — updates live |
| `r` / `(r "PROMPT")` / `r>` | the active region, or a field; `r>` reindents |
| `n` / `>` / `n>` | newline / indent / newline-then-indent (use `n>` for code-block bodies) |
| `q` | the final cursor resting position |
| `&` / `%` | newline only if not already at line start / end |
| any other Lisp form | **evaluated**, its string result inserted — e.g. `(format-time-string "%Y-%m-%d")`, `comment-start`, `(file-name-base (or (buffer-file-name) (buffer-name)))` |

Do **not** use yasnippet's `$1` / `${1:foo}` syntax — tempel will not understand it.

### Reloading after an edit

tempel re-reads the file when its modification time changes, so a saved edit takes effect on
the next expansion — no restart needed. Validate the file parses with:

```sh
emacs --batch --eval '(with-temp-buffer (insert-file-contents "templates") \
  (goto-char (point-min)) (condition-case e (while t (read (current-buffer))) \
  (end-of-file (message "OK")) (error (message "ERR %S" e) (kill-emacs 1))))'
```

---

## 5. Gotchas & operations

- **no-littering redirects `tempel-path`** — this is load-bearing. Without the explicit
  `tempel-path` override in [`lisp/init-snippets.el`](../lisp/init-snippets.el), tempel reads
  `etc/tempel/templates.eld` (gitignored state dir) and the repo-root [`templates`](../templates)
  file is silently ignored (zero templates found). If a brand-new `templates` file "doesn't
  work," check `tempel-path` first: `M-x describe-variable RET tempel-path`.
- **First install** — `tempel` is not bundled with Emacs and `elpa/` is gitignored, so a
  fresh clone needs a one-time install. The archive is never refreshed at startup (network-free
  boot), so: `M-x my/package-refresh` **then restart** (use-package's `:ensure` installs it on
  the next launch). Note `my/package-refresh` only refreshes the package **list** — it does
  not install anything; the install happens on the restart (or via `M-x package-install RET
  tempel`).
- **No auto-popup** — `corfu-auto` is off; templates surface only on the manual `C-<tab>` /
  `M-+` / `M-*` trigger (see §2).
- **YASnippet `TAB` is inert** — yasnippet is enabled only as Eglot's LSP backend, with no
  snippet tables loaded, so its `TAB` falls through to the normal indent/complete command.
- **`tempel-collection`** — a large community template library (the TempEl analogue of
  `yasnippet-snippets`) is available but **off by default**, to keep the snippet set small and
  fully-owned. Opt in by uncommenting its block in
  [`lisp/init-snippets.el`](../lisp/init-snippets.el).

---

## See also

- [Snippets section of FEATURES.md](../FEATURES.md) — the keybinding cheat sheet.
- [`lisp/init-snippets.el`](../lisp/init-snippets.el) — the TempEl + YASnippet wiring.
- [`lisp/init-corfu.el`](../lisp/init-corfu.el) — the `C-<tab>` binding and the in-buffer
  completion routing rationale.
- [`templates`](../templates) — the template definitions themselves.
