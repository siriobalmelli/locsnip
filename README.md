# `locsnip`: the Location Snippet Tool

A Location Snippet identifies source-code context
using Git and unified-diff conventions.

LocSnips are designed to communicate what you're looking at to an LLM:

- Using a format already ubiquitous in their training data.
- With sufficient context to reduce follow-up searches by the LLM.
- Consuming a minimal amount of tokens.

A Snippet can also be passed to standard tooling
to check whether its represented context has changed.

The `locsnip` CLI is designed for use by text editors.
Run from the repository root to use repository-relative paths.

## Format

LocSnips come in two flavors:

### Snippet

Encodes a location or range in a file currently on disk,
in format accepted by GNU `patch`.

A location is shown as a NOP change surrounded by N lines of context:

```diff
Index: src/foo.py
@@ -134,5 +134,5 @@
 lines before the focus ...
 line before the focus
-focused line
+focused line
 line after the focus
 lines after the focus ...
```

A range marks its first and last lines as NOP changes:

```diff
Index: src/bar.ts
@@ -42,4 +42,4 @@
-line at beginning of range
+line at beginning of range
 inner context
 also inner context
-line at end of range
+line at end of range
```

A single line with no context is both a location with `N=0` context and a range over a single row:

```diff
Index: src/baz.c
@@ -88,1 +88,1 @@
-singleton line text
+singleton line text
```

See the [manual](doc/locsnip.1.md#snippet-verification) for rules and verification tooling.

### Diff

Encodes a reference to a change in a specific Git commit.

A File Diff has no line selector and emits commit and file headers only:

```diff
Commit: acb845149a198065f08e8d6bd97f1bf1e8154bb2
--- src/old-name.py
+++ src/new-name.py
```

`Commit` identifies provenance.

File headers give old/new repository-relative paths;
`/dev/null` identifies an absent side for file creation or deletion.

A Hunk Diff emits the same commit and file headers,
followed by a whole or partial textual hunk:

```diff
Commit: acb845149a198065f08e8d6bd97f1bf1e8154bb2
--- src/foo.py
+++ src/foo.py
@@ -134,3 +134,4 @@ def whatever():
     prepare()
-    old_call()
+    new_call()
+    validate()
     finish()
```

A partial Hunk Diff includes `N` displayed rows on each side of the focus,
clipped at the original hunk boundaries.

The result is context for the reader, not a patch guaranteed to apply
or reproduce the original change.

See the [manual](doc/locsnip.1.md#diff-extraction) for extraction and counting rules.

## Usage

### Shell

```text
locsnip snip FILE LINE [N]
locsnip snip FILE FIRST,LAST

locsnip diff COMMIT FILE
locsnip diff COMMIT FILE a:LINE [N]
locsnip diff COMMIT FILE b:LINE [N]
```

```sh
locsnip snip src/foo.py 142       # line 142, +/- 8 lines (default)
locsnip snip src/foo.py 77 3      # line 77, +/- 3 lines
locsnip snip src/foo.py 100 0     # line 100 only
locsnip snip src/foo.py 142,145   # lines 142-145 (inclusive) only

locsnip diff HEAD src/foo.py           # File Diff
locsnip diff HEAD src/foo.py b:142     # Hunk Diff for committed line 142
locsnip diff HEAD src/foo.py b:142 3   # Hunk Diff, +/- 3 hunk-body rows
locsnip diff HEAD src/foo.py a:139 0   # Hunk Diff on first-parent line 139 (N=0)
```

For a File Diff, `FILE` may name the old or new path;
unchanged or ambiguous paths are errors.

For a Hunk Diff, `a` selects the first-parent version and `b` the committed version.
`FILE` names the path on that side; `LINE` is a source line number.
Omitting `N` selects the whole hunk; explicit `N` selects a focused excerpt.

See [`man locsnip`](doc/locsnip.1.md) for command syntax and detailed serialization rules.
