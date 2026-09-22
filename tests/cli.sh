#!/usr/bin/env bash
set -euo pipefail

binary=$1
version=$2
scratch_dir=${TMPDIR:-"$PWD/.opencode"}
mkdir -p "$scratch_dir"
workdir=$(mktemp -d "$scratch_dir/locsnip-cli.XXXXXX")

cleanup() {
  rm -rf "$workdir"
}

trap cleanup EXIT

check_case() {
  local name=$1
  local expected_status=$2
  local expected_stdout=$3
  local expected_stderr=$4
  shift 4
  local stdout="$workdir/$name.stdout"
  local stderr="$workdir/$name.stderr"
  local expected_stdout_file="$workdir/$name.expected-stdout"
  local expected_stderr_file="$workdir/$name.expected-stderr"
  local status
  if "$binary" "$@" >"$stdout" 2>"$stderr"; then
    status=0
  else
    status=$?
  fi
  test "$status" -eq "$expected_status"
  printf %s "$expected_stdout" >"$expected_stdout_file"
  printf %s "$expected_stderr" >"$expected_stderr_file"
  cmp "$expected_stdout_file" "$stdout"
  cmp "$expected_stderr_file" "$stderr"
}

help=$'Usage: locsnip <command>\nCommands:\n  help, --help, -h       Show this help.\n  version, --version, -v Print version.\n  snip ...               Not implemented.\n  diff ...               Not implemented.\n'

check_case help 0 "$help" '' help
check_case long-help 0 "$help" '' --help
check_case short-help 0 "$help" '' -h
check_case version 0 "locsnip $version"$'\n' '' version
check_case long-version 0 "locsnip $version"$'\n' '' --version
check_case version-extra 2 '' $'locsnip: InvalidArguments\n' version extra
check_case no-command 2 '' $'locsnip: MissingCommand\n'
check_case help-extra 0 "$help" '' help extra
check_case unknown-option 2 '' $'locsnip: UnknownCommand\n' --unknown
check_case unknown-command 2 '' $'locsnip: UnknownCommand\n' unknown
check_case snip-bare 1 '' $'locsnip: NotImplemented\n' snip
check_case diff-bare 1 '' $'locsnip: NotImplemented\n' diff
check_case snip-malformed 1 '' $'locsnip: NotImplemented\n' snip --bad
check_case diff-malformed 1 '' $'locsnip: NotImplemented\n' diff HEAD
check_case snip 1 '' $'locsnip: NotImplemented\n' snip src/main.zig 1
check_case diff 1 '' $'locsnip: NotImplemented\n' diff HEAD src/main.zig

if [[ -c /dev/full ]]; then
  if "$binary" help >/dev/full 2>"$workdir/write-error.stderr"; then
    exit 1
  else
    test "$?" -eq 1
  fi
  printf 'locsnip: NoSpaceLeft\n' >"$workdir/write-error.expected-stderr"
  cmp "$workdir/write-error.expected-stderr" "$workdir/write-error.stderr"
fi
