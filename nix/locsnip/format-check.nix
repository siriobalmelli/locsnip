{
  runCommand,
  src,
  zig,
}:
runCommand "locsnip-format-check"
  {
    inherit src;
    nativeBuildInputs = [ zig ];
  }
  ''
    zig fmt --check "$src/build.zig" "$src/build.zig.zon" "$src/src"
    touch "$out"
  ''
