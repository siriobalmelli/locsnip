#!/usr/bin/env bash
set -euo pipefail

binary=$1
version=$2
scratch_dir=${TMPDIR:-"$PWD/.opencode"}
mkdir -p "$scratch_dir"
scratch_dir=$(realpath "$scratch_dir")
binary=$(realpath "$binary")
workdir=$(mktemp -d "$scratch_dir/locsnip-cli.XXXXXX")

cleanup() {
  rm -rf "$workdir"
}

trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

run_case() {
  local name=$1
  local expected_status=$2
  local expected_stdout=$3
  local expected_stderr=$4
  shift 4
  local stdout="$workdir/$name.stdout"
  local stderr="$workdir/$name.stderr"
  local status

  if "$binary" "$@" >"$stdout" 2>"$stderr"; then
    status=0
  else
    status=$?
  fi
  test "$status" -eq "$expected_status" || fail "$name returned $status, expected $expected_status"
  cmp "$expected_stdout" "$stdout" || fail "$name stdout differs"
  cmp "$expected_stderr" "$stderr" || fail "$name stderr differs"
}

write_focused_bytes() {
  local output=$1
  local path=$2
  local line=$3
  local source=$4
  local offset=$5
  local length=$6
  local missing_newline=$7

  printf 'Index: %s\n@@ -%s,1 +%s,1 @@\n-' "$path" "$line" "$line" >"$output"
  dd if="$source" bs=1 skip="$offset" count="$length" status=none >>"$output"
  printf '\n' >>"$output"
  if [[ $missing_newline == yes ]]; then
    printf '\\ No newline at end of file\n' >>"$output"
  fi
  {
    printf '+'
    dd if="$source" bs=1 skip="$offset" count="$length" status=none
    printf '\n'
    if [[ $missing_newline == yes ]]; then
      printf '\\ No newline at end of file\n'
    fi
  } >>"$output"
}

expect_text() {
  local path=$1
  shift
  printf '%s' "$*" >"$path"
}

empty="$workdir/empty"
: >"$empty"
invalid="$workdir/invalid"
expect_text "$invalid" $'locsnip: InvalidArguments\n'
missing_command="$workdir/missing-command"
expect_text "$missing_command" $'locsnip: MissingCommand\n'
unknown_command="$workdir/unknown-command"
expect_text "$unknown_command" $'locsnip: UnknownCommand\n'
not_implemented="$workdir/not-implemented"
expect_text "$not_implemented" $'locsnip: NotImplemented\n'
line_out_of_range="$workdir/line-out-of-range"
expect_text "$line_out_of_range" $'locsnip: LineOutOfRange\n'
file_not_found="$workdir/file-not-found"
expect_text "$file_not_found" $'locsnip: FileNotFound\n'
help="$workdir/help"
expect_text "$help" $'Usage: locsnip <command>\nCommands:\n  help, --help, -h       Show this help.\n  version, --version, -v Print version.\n  snip FILE LINE [N]     Show a location (default context: 8).\n  snip FILE FIRST,LAST   Show an inclusive range.\n  diff ...               Not implemented.\n'
version_output="$workdir/version"
expect_text "$version_output" "locsnip $version"$'\n'

run_case help 0 "$help" "$empty" help
run_case long-help 0 "$help" "$empty" --help
run_case short-help 0 "$help" "$empty" -h
run_case version 0 "$version_output" "$empty" version
run_case long-version 0 "$version_output" "$empty" --version
run_case version-extra 2 "$empty" "$invalid" version extra
run_case no-command 2 "$empty" "$missing_command"
run_case help-extra 0 "$help" "$empty" help extra
run_case unknown-option 2 "$empty" "$unknown_command" --unknown
run_case unknown-command 2 "$empty" "$unknown_command" unknown
run_case diff-bare 1 "$empty" "$not_implemented" diff
run_case diff-malformed 1 "$empty" "$not_implemented" diff HEAD
run_case diff 1 "$empty" "$not_implemented" diff HEAD src/main.zig

fixture_dir="$workdir/fixtures"
mkdir "$fixture_dir"
cd "$fixture_dir"

plain=plain.txt
printf 'one\ntwo\nthree\nfour\nfive\nsix\nseven\neight\nnine\nten\n' >"$plain"
expected="$workdir/plain.default"
cat >"$expected" <<'EOF'
Index: plain.txt
@@ -1,10 +1,10 @@
 one
 two
 three
 four
-five
+five
 six
 seven
 eight
 nine
 ten
EOF
run_case default-context 0 "$expected" "$empty" snip "$plain" 5
cp "$expected" "$workdir/saturated-upper-location.expected"

cat >"$expected" <<'EOF'
Index: plain.txt
@@ -1,9 +1,9 @@
-one
+one
 two
 three
 four
 five
 six
 seven
 eight
 nine
EOF
run_case default-lower-clip 0 "$expected" "$empty" snip "$plain" 1

cat >"$expected" <<'EOF'
Index: plain.txt
@@ -2,9 +2,9 @@
 two
 three
 four
 five
 six
 seven
 eight
 nine
-ten
+ten
EOF
run_case default-upper-clip 0 "$expected" "$empty" snip "$plain" 10

cat >"$expected" <<'EOF'
Index: plain.txt
@@ -5,1 +5,1 @@
-five
+five
EOF
run_case explicit-zero 0 "$expected" "$empty" snip "$plain" 5 0
run_case singleton-range 0 "$expected" "$empty" snip "$plain" 5,5
run_case leading-zero-location 0 "$expected" "$empty" snip "$plain" 005 00
run_case saturated-upper-location 0 "$workdir/saturated-upper-location.expected" "$empty" snip "$plain" 5 18446744073709551615

cat >"$expected" <<'EOF'
Index: plain.txt
@@ -2,3 +2,3 @@
-two
+two
 three
-four
+four
EOF
run_case inclusive-range 0 "$expected" "$empty" snip "$plain" 2,4

for selector in '' 0 +1 '1 ' 1x 1_0 1.0 1/2 1,,2 ,2 '1,' 1,2,3 2,1 0,1 1,0 0,0 18446744073709551616; do
  run_case "invalid-${selector//[^a-zA-Z0-9]/x}" 2 "$empty" "$invalid" snip "$plain" "$selector"
done
run_case invalid-context-negative 2 "$empty" "$invalid" snip "$plain" 1 -1
run_case invalid-context-overflow 2 "$empty" "$invalid" snip "$plain" 1 18446744073709551616
run_case invalid-extra 2 "$empty" "$invalid" snip "$plain" 1 0 extra
run_case snip-bare 2 "$empty" "$invalid" snip
run_case snip-file-only 2 "$empty" "$invalid" snip "$plain"
run_case range-with-context 2 "$empty" "$invalid" snip "$plain" 1,2 0
run_case no-line-number-command 2 "$empty" "$unknown_command" "$plain"
run_case missing-focus 1 "$empty" "$line_out_of_range" snip "$plain" 11
run_case missing-range-end 1 "$empty" "$line_out_of_range" snip "$plain" 9,11
run_case missing-file 1 "$empty" "$file_not_found" snip absent 1

mkdir read-error-directory
if "$binary" snip read-error-directory 1 >"$workdir/read-error.stdout" 2>"$workdir/read-error.stderr"; then
  fail "directory read unexpectedly succeeded"
else
  read_status=$?
fi
test "$read_status" -eq 1 || fail "directory read returned $read_status"
test ! -s "$workdir/read-error.stdout" || fail "directory read wrote stdout"
test -s "$workdir/read-error.stderr" || fail "directory read omitted diagnostic"

empty_source="empty-source"
: >"$empty_source"
run_case empty-source 1 "$empty" "$line_out_of_range" snip "$empty_source" 1

one_line=one-line
printf 'only\n' >"$one_line"
run_case no-phantom-trailing-line 1 "$empty" "$line_out_of_range" snip "$one_line" 2

no_newline=no-newline
printf 'last' >"$no_newline"
cat >"$expected" <<'EOF'
Index: no-newline
@@ -1,1 +1,1 @@
-last
\ No newline at end of file
+last
\ No newline at end of file
EOF
run_case unterminated-focus 0 "$expected" "$empty" snip "$no_newline" 1

context_eof="context-eof"
printf 'first\nlast' >"$context_eof"
cat >"$expected" <<'EOF'
Index: context-eof
@@ -1,2 +1,2 @@
-first
+first
 last
\ No newline at end of file
EOF
run_case unterminated-context 0 "$expected" "$empty" snip "$context_eof" 1 8

crlf=crlf.txt
printf 'one\r\ntwo\r\n' >"$crlf"
printf 'Index: %s\n@@ -1,2 +1,2 @@\n one\r\n-two\r\n+two\r\n' "$crlf" >"$expected"
run_case crlf 0 "$expected" "$empty" snip "$crlf" 2 1

binary_source=binary
printf 'before\n\000\377middle\nafter\n' >"$binary_source"
printf 'Index: %s\n@@ -1,3 +1,3 @@\n before\n-\000\377middle\n+\000\377middle\n after\n' "$binary_source" >"$expected"
run_case binary-bytes 0 "$expected" "$empty" snip "$binary_source" 2 1

paths=paths
mkdir "$paths"
printf 'x\n' >"$paths/with space"
printf 'x\n' >"$paths/$(printf 'tab\tname')"
printf 'x\n' >"$paths/with\"quote"
printf 'x\n' >"$paths/with\\backslash"
(
  cd "$paths"
  printf 'Index: "with space"\n@@ -1,1 +1,1 @@\n-x\n+x\n' >"$expected"
  run_case quoted-space 0 "$expected" "$empty" snip 'with space' 1
  printf 'Index: "tab\\tname"\n@@ -1,1 +1,1 @@\n-x\n+x\n' >"$expected"
  run_case quoted-tab 0 "$expected" "$empty" snip $'tab\tname' 1
  printf 'Index: "with\\"quote"\n@@ -1,1 +1,1 @@\n-x\n+x\n' >"$expected"
  run_case quoted-quote 0 "$expected" "$empty" snip 'with"quote' 1
  printf 'Index: "with\\\\backslash"\n@@ -1,1 +1,1 @@\n-x\n+x\n' >"$expected"
  run_case quoted-backslash 0 "$expected" "$empty" snip 'with\backslash' 1
  printf 'x\n' >"$(printf 'with\rreturn')"
  printf 'Index: "with\\rreturn"\n@@ -1,1 +1,1 @@\n-x\n+x\n' >"$expected"
  run_case quoted-carriage-return 0 "$expected" "$empty" snip $'with\rreturn' 1
)
absolute_plain=$(realpath "$plain")
absolute_header=$absolute_plain
if [[ $absolute_plain == *[[:space:]\"\\]* ]]; then
  absolute_header=${absolute_header//\\/\\\\}
  absolute_header=${absolute_header//\"/\\\"}
  absolute_header=${absolute_header//$'\t'/\\t}
  absolute_header=${absolute_header//$'\r'/\\r}
  absolute_header=${absolute_header//$'\n'/\\n}
  absolute_header="\"$absolute_header\""
fi
printf 'Index: %s\n@@ -1,1 +1,1 @@\n-one\n+one\n' "$absolute_header" >"$expected"
run_case absolute-path 0 "$expected" "$empty" snip "$absolute_plain" 1 0

for length in 65535 65536 65537; do
  boundary="delimiter-$length"
  head -c "$length" /dev/zero | tr '\0' x >"$boundary"
  printf '\n' >>"$boundary"
  write_focused_bytes "$expected" "$boundary" 1 "$boundary" 0 "$length" no
  run_case "delimiter-$length" 0 "$expected" "$empty" snip "$boundary" 1 0
done

long=long
{ printf 'skip\n'; head -c 262145 /dev/zero | tr '\0' q; printf '\nend\n'; } >"$long"
write_focused_bytes "$expected" "$long" 2 "$long" 5 262145 no
run_case focused-long-line 0 "$expected" "$empty" snip "$long" 2 0
printf 'Index: %s\n@@ -3,1 +3,1 @@\n-end\n+end\n' "$long" >"$expected"
run_case skipped-long-line 0 "$expected" "$empty" snip "$long" 3 0

for ending in lf none; do
  exact="exact-$ending"
  length=65536
  if [[ $ending == lf ]]; then
    length=65535
  fi
  head -c "$length" /dev/zero | tr '\0' e >"$exact"
  if [[ $ending == lf ]]; then
    printf '\n' >>"$exact"
    write_focused_bytes "$expected" "$exact" 1 "$exact" 0 65535 no
  else
    write_focused_bytes "$expected" "$exact" 1 "$exact" 0 65536 yes
  fi
  run_case "exact-boundary-$ending" 0 "$expected" "$empty" snip "$exact" 1 0
done

if ! command -v patch >/dev/null; then
  fail "GNU patch is required for CLI patch checks"
fi
patch_dir="patch"
mkdir "$patch_dir"
printf 'one\ntwo\nthree\n' >"$patch_dir/plain"
printf 'one\ntwo\nthree\n' >"$patch_dir/quoted file"
printf 'one\r\ntwo\r\nthree\r\n' >"$patch_dir/crlf"
printf 'one\ntwo' >"$patch_dir/no-newline"
(
  cd "$patch_dir"
  for spec in 'plain|2|0' 'plain|1,2|' 'plain|1,3|' 'quoted file|2|' 'crlf|2|' 'no-newline|2|' 'no-newline|1,2|'; do
    IFS='|' read -r file selector context <<<"$spec"
    patch_file="$workdir/patch-${file// /-}-$selector"
    if [[ -n $context ]]; then
      "$binary" snip "$file" "$selector" "$context" >"$patch_file"
    else
      "$binary" snip "$file" "$selector" >"$patch_file"
    fi
    patch --batch --dry-run --fuzz=0 -p0 <"$patch_file" || fail "patch rejected $file $selector"
    case "$file:$selector" in
      plain:1,3) printf 'changed\ntwo\nthree\n' >"$file" ;;
      plain:*) printf 'one\nchanged\nthree\n' >"$file" ;;
      'quoted file':*) printf 'one\nchanged\nthree\n' >"$file" ;;
      crlf:*) printf 'one\r\nchanged\r\nthree\r\n' >"$file" ;;
      no-newline:*) printf 'one\nchanged' >"$file" ;;
    esac
    if patch --batch --dry-run --fuzz=0 -p0 <"$patch_file" >/dev/null 2>&1; then
      fail "patch accepted changed focused context for $file $selector"
    fi
    case "$file" in
      plain) printf 'one\ntwo\nthree\n' >"$file" ;;
      'quoted file') printf 'one\ntwo\nthree\n' >"$file" ;;
      crlf) printf 'one\r\ntwo\r\nthree\r\n' >"$file" ;;
      no-newline) printf 'one\ntwo' >"$file" ;;
    esac
  done
)

if [[ -c /dev/full ]]; then
  if "$binary" help >/dev/full 2>"$workdir/full-help.stderr"; then
    fail "/dev/full accepted help"
  else
    full_status=$?
  fi
  test "$full_status" -eq 1 || fail "help /dev/full returned $full_status"
  test "$(<"$workdir/full-help.stderr")" = 'locsnip: NoSpaceLeft' || fail "help /dev/full error differs"
  if "$binary" snip "$plain" 5 0 >/dev/full 2>"$workdir/full-small.stderr"; then
    fail "/dev/full accepted small snippet"
  else
    full_status=$?
  fi
  test "$full_status" -eq 1 || fail "small /dev/full returned $full_status"
  test "$(<"$workdir/full-small.stderr")" = 'locsnip: NoSpaceLeft' || fail "small /dev/full error differs"
  if "$binary" snip "$long" 2 0 >/dev/full 2>"$workdir/full-large.stderr"; then
    fail "/dev/full accepted large snippet"
  else
    full_status=$?
  fi
  test "$full_status" -eq 1 || fail "large /dev/full returned $full_status"
  test "$(<"$workdir/full-large.stderr")" = 'locsnip: NoSpaceLeft' || fail "large /dev/full error differs"
fi
