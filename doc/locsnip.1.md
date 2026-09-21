# locsnip(1)

## NAME

locsnip - encode source and history locations as snippets

## SYNOPSIS

```text
locsnip snip FILE LINE [N]
locsnip snip FILE FIRST,LAST
```

```text
locsnip diff COMMIT FILE
locsnip diff COMMIT FILE a:LINE [N]
locsnip diff COMMIT FILE b:LINE [N]
```

```text
locsnip help
locsnip version
```

## DESCRIPTION

LocSnips identify source-code context using unified-diff conventions.
They come in two flavors:

`snip` reads a saved file and emits a Snippet:
a location or inclusive line range marked with identical deletion/addition pairs.

`diff` reads a commit and emits a File Diff or Hunk Diff.

Neither command modifies files or Git state.

## ARGUMENTS

Line numbers are 1-based positive integers.

`N` is a nonnegative integer.

### snip

```text
locsnip snip FILE LINE [N]
locsnip snip FILE FIRST,LAST
```

`FILE` is a relative source path on disk.
Run from the repository root for repository-relative paths.

`LINE` is a line number in the file.

`N` sets the number of lines above and below which should be captured, defaulting to 8.
`N=0` emits only `LINE` as an identical deletion/addition pair.
Less than `N` lines may be captured at file boundaries.

`FIRST,LAST` selects an inclusive range without outer context or an `N` argument.

`LINE 0` and `LINE,LINE` both select exactly one line.

### diff

```text
locsnip diff COMMIT FILE
locsnip diff COMMIT FILE a:LINE [N]
locsnip diff COMMIT FILE b:LINE [N]
```

`COMMIT` is a Git revision such as a hash, tag, or `HEAD`.

Without a line selector, `FILE` selects one changed file for a File Diff.
It may name the old or new repository-relative path.
If it matches multiple or no changed files, `diff` returns an error.

`a:LINE` selects a source line in the first-parent version (`---`);
`b:LINE` selects one in the committed version (`+++`).

With a line selector, `FILE` names the relative path on side `a` or `b`.
For renames, use the old path with `a:` and the new path with `b:`.
Line selectors for deleted files require `a:`; new files require `b:`.

Without a line selector, a File Diff contains only the Diff headers.
With a line selector but no `N`, a Hunk Diff contains the whole hunk containing that line.
With `N`, a Hunk Diff contains an excerpt with that many hunk-body rows on each side of the focus,
subject to the extraction rules below.

The line must occur in a textual hunk on the selected side;
lines outside one specific hunk yield an error.
Hunk Diffs never fall back to header-only output.

## EXAMPLES

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

## OUTPUT AND EXIT STATUS

For `snip` and `diff`:
returns 0 when a LocSnip was successfully emitted to stdout;
otherwise returns non-0, at which point stdout is guaranteed to be empty.

A File Diff requires an unambiguous changed-file path.
Hunk Diffs require a matching textual hunk.

For `help` and `version`:
emits the requested info to stdout.

## RULES AND SERIALIZATION

### Snippet Format

A Snippet starts with `Index: <path>`, followed by a hunk.
The old and new ranges have equal starts and counts covering the whole window,
including outer context.

A focused line is marked by an identical `-`/`+` pair:

```diff
Index: src/foo.py
@@ -141,3 +141,3 @@
 line before the focus
-focused line
+focused line
 line after the focus
```

A range marks its first and last lines with identical pairs:

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

A one-line range uses a single pair:

```diff
Index: src/baz.c
@@ -88,1 +88,1 @@
-singleton line text
+singleton line text
```

### Snippet Rules

### Snippet Verification

Validate a Snippet against the current on-disk target with GNU `patch`:

```sh
patch --batch --dry-run --fuzz=0 -p0 < snippet.patch
```

Run from the same directory where the snippet was generated.

This checks the represented text, not its original position:
`patch` may locate the text at a different line number.

### Diff Headers

A File Diff contains the commit hash and old/new file headers:

```text
Commit: <hash>
--- <old-path>
+++ <new-path>
```

A Hunk Diff appends the whole containing hunk or a focused excerpt:

```text
Commit: <hash>
--- <old-path>
+++ <new-path>
@@ -<old-start>,<old-count> +<new-start>,<new-count> @@
```

`<hash>` is the full object ID of the selected commit.

Paths are repository-relative, without Git's customary `a/` and `b/` prefixes.
Renames retain the distinct old and new paths.
`/dev/null` denotes the old path for file creation or the new path for deletion.
Both headers follow the path quoting rules below.

Diffs omit `Index:`, `diff --git`, blob hashes, and file-mode metadata.
`Commit:` identifies the source commit; it is a LocSnip extension to unified diff.
The headers identify paths and provenance, not binary content or mode changes.

```diff
Commit: acb845149a198065f08e8d6bd97f1bf1e8154bb2
--- src/foo.py
+++ src/foo.py
@@ -134,3 +134,4 @@
     prepare()
-    old_call()
+    new_call()
+    validate()
     finish()
```

### Diff Hunk Ranges

The old and new counts are the number of retained unchanged rows plus deletions or additions.
Missing-newline markers contribute to neither count.
A blank unchanged line still has its leading space and counts on both sides.

Each nonempty range starts at the original source line of its first retained row
on that side.
An empty range starts at the line immediately before the insertion or deletion
position on that side, or zero at the beginning of the file.
Excerpts retain original source coordinates, not numbering from one.

An excerpt from a newly created file need not include the whole file:

```diff
Commit: acb845149a198065f08e8d6bd97f1bf1e8154bb2
--- /dev/null
+++ src/new.txt
@@ -0,0 +101,3 @@
+line 101
+line 102
+line 103
```

### Paths

Snippet paths retain their working-directory-relative or absolute form.
Repository-relative paths make snippets portable.

Paths containing whitespace, double quotes, or backslashes use Git-style
C quoting: double quotes around the path and escapes for special characters.
Spaces remain literal inside the quotes;
tabs, newlines, carriage returns, double quotes, and backslashes
are written as `\t`, `\n`, `\r`, `\"`, and `\\`, respectively.
Other control bytes use three-digit octal escapes.
This header quoting is separate from shell argument quoting.

```text
Index: src/foo.py
Index: "src/my file.py"
Index: "src/with\ttab.py"
Index: "src/with\"quote.py"
Index: "src/with\\backslash.py"
```

### Missing newline

Each occurrence of a file's final unterminated line is followed by
`\ No newline at end of file`.
A Snippet's identical `-`/`+` pair has a marker after both occurrences:

```diff
Index: final.txt
@@ -1,1 +1,1 @@
-final line
\ No newline at end of file
+final line
\ No newline at end of file
```

These markers do not contribute to the hunk's old or new line counts.

## DIFF EXTRACTION

### Source and Scope

The selected commit is compared with its first parent, including for merge commits.
A root commit is compared with the empty tree.
Parent selection and combined merge diffs are not currently supported.

A File Diff gives headers for the selected changed file,
whether or not it has textual changes.

A Hunk Diff contains one textual hunk or a contiguous excerpt from it.
Binary changes, mode-only changes, empty-file creation or deletion, and pure renames
all contain no textual changes and so yield an error for Hunk Diffs.

Hunk boundaries come from locsnip's diff generation
and may not exactly match an editor or diff view.

`N` controls the excerpt size within the existing hunk;
new hunks are never inferred or generated.

### Focused Excerpts

An excerpt includes the focused row and `N` body rows on each side,
clipped at hunk boundaries.
Rows beginning with a space, `-`, or `+` count once;
headers and missing-newline markers do not count.

An unchanged-only excerpt extends to the nearest changed row within the same hunk,
including all intervening rows, even with `N=0`.

Excerpts may split runs of additions or deletions;
they do not expand to complete a change block or include both sides of a replacement.
Retained rows keep their prefixes and attached missing-newline markers.
Hunk ranges are recalculated for the excerpt.

Diffs use unified-diff hunk syntax but need not apply successfully
or reproduce the original change.

## SEE ALSO

git-diff(1), gitrevisions(7), GNU patch(1).
