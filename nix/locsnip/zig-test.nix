{
  runCommand,
  src,
  zig,
}:
runCommand "locsnip-zig-test"
  {
    inherit src;
    nativeBuildInputs = [ zig ];
  }
  ''
    export HOME="$TMPDIR/home"
    export ZIG_GLOBAL_CACHE_DIR="$TMPDIR/zig-global-cache"
    export ZIG_LOCAL_CACHE_DIR="$TMPDIR/zig-local-cache"
    mkdir -p "$HOME" "$ZIG_GLOBAL_CACHE_DIR" "$ZIG_LOCAL_CACHE_DIR"
    cd "$src"
    zig build test
    touch "$out"
  ''
