{
  binutils,
  llvm,
  ripgrep,
  runCommand,
  expectedHeader,
  osFamily,
  package,
  target,
}:
runCommand "locsnip-${target}-artifact-check"
  {
    nativeBuildInputs = [
      binutils
      llvm
      ripgrep
    ];
  }
  ''
    artifact=${package}/bin/locsnip${if osFamily == "windows" then ".exe" else ""}
    test ${if osFamily == "windows" then "-f" else "-x"} "$artifact"
    llvm-readobj --file-headers "$artifact" > "$TMPDIR/headers"
    rg -q '${expectedHeader}' "$TMPDIR/headers"
    case '${osFamily}' in
      linux)
        readelf -l "$artifact" > "$TMPDIR/program-headers"
        readelf -d "$artifact" > "$TMPDIR/dynamic"
        if rg -q 'INTERP' "$TMPDIR/program-headers"; then exit 1; else test $? -eq 1; fi
        if rg -q 'NEEDED' "$TMPDIR/dynamic"; then exit 1; else test $? -eq 1; fi
        if rg -a -q '/nix/store' "$artifact"; then exit 1; else test $? -eq 1; fi
        ;;
      macos)
        llvm-objdump --macho --dylibs-used "$artifact" > "$TMPDIR/dylibs"
        rg -v '^[^:]+:$|^[[:space:]]*/usr/lib/libSystem[.]B[.]dylib ' "$TMPDIR/dylibs" > "$TMPDIR/unexpected" || test $? -eq 1
        if test -s "$TMPDIR/unexpected"; then exit 1; fi
        ;;
      windows)
        llvm-readobj --coff-imports "$artifact" > "$TMPDIR/imports"
        rg '^  Name: ' "$TMPDIR/imports" > "$TMPDIR/dlls"
        rg -iv '^  Name: (ntdll|kernel32)[.]dll$' "$TMPDIR/dlls" > "$TMPDIR/unexpected" || test $? -eq 1
        if test -s "$TMPDIR/unexpected"; then exit 1; fi
        ;;
    esac
    touch "$out"
  ''
