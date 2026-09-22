args@{
  lib,
  stdenvNoCC,
  zig,
  callPackage,
  target ? null,
}:
let
  targets = {
    # platform.system -> targetMetadata
    x86_64-linux = {
      expectedHeader = "Format: elf64-x86-64";
      osFamily = "linux";
      target = "x86_64-linux-musl";
    };
    aarch64-linux = {
      expectedHeader = "Format: elf64-littleaarch64";
      osFamily = "linux";
      target = "aarch64-linux-musl";
    };
    x86_64-darwin = {
      expectedHeader = "Format: Mach-O 64-bit x86-64";
      osFamily = "macos";
      target = "x86_64-macos";
    };
    aarch64-darwin = {
      expectedHeader = "Format: Mach-O arm64";
      osFamily = "macos";
      target = "aarch64-macos";
    };
    x86_64-windows = {
      expectedHeader = "Machine: IMAGE_FILE_MACHINE_AMD64";
      osFamily = "windows";
      target = "x86_64-windows-gnu";
    };
    aarch64-windows = {
      expectedHeader = "Machine: IMAGE_FILE_MACHINE_ARM64";
      osFamily = "windows";
      target = "aarch64-windows-gnu";
    };
  };
  defaultTarget = targets.${stdenvNoCC.buildPlatform.system}.target;
  requestedTarget = if target == null then defaultTarget else target;
  selectedBuild = lib.findFirst (
    metadata: metadata.target == requestedTarget
  ) (throw "unsupported locsnip target: ${requestedTarget}") (builtins.attrValues targets);
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "locsnip-${selectedBuild.target}";
  version = builtins.head (
    builtins.match ''.*[[:space:]]\.version[[:space:]]*=[[:space:]]*"([0-9][A-Za-z0-9.+-]*)".*'' (
      builtins.readFile ../../build.zig.zon
    )
  );

  src = lib.fileset.toSource {
    root = ../../.;
    fileset = lib.fileset.unions [
      ../../build.zig
      ../../build.zig.zon
      ../../LICENSE
      ../../README.md
      ../../src
    ];
  };

  nativeBuildInputs = [ zig ];

  dontFixup = true; # implies dontStrip

  buildPhase = ''
    runHook preBuild
    export HOME="$TMPDIR/home"
    export ZIG_GLOBAL_CACHE_DIR="$TMPDIR/zig-global-cache"
    export ZIG_LOCAL_CACHE_DIR="$TMPDIR/zig-local-cache"
    mkdir -p "$HOME" "$ZIG_GLOBAL_CACHE_DIR" "$ZIG_LOCAL_CACHE_DIR"
    zig build -Dtarget=${selectedBuild.target} -Doptimize=ReleaseSafe -Dcpu=baseline -Dstrip=true
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    cp -r zig-out/* "$out"
    runHook postInstall
  '';

  passthru = {
    inherit zig;
    inherit (selectedBuild) expectedHeader osFamily target;
    cross = lib.mapAttrs (
      _: metadata:
      if metadata.target == selectedBuild.target then
        finalAttrs.finalPackage
      else
        callPackage ./default.nix (args // { inherit (metadata) target; })
    ) targets;

    tests = lib.optionalAttrs (selectedBuild.target == defaultTarget) {
      artifact = callPackage ./artifact-check.nix {
        inherit (selectedBuild) expectedHeader osFamily target;
        package = finalAttrs.finalPackage;
      };

      cli = callPackage ./cli-check.nix {
        package = finalAttrs.finalPackage;
      };

      format = callPackage ./format-check.nix {
        inherit (finalAttrs) src;
        inherit zig;
      };

      zig-test = callPackage ./zig-test.nix {
        inherit (finalAttrs) src;
        inherit zig;
      };
    };
  };

  meta = {
    description = "identifies source-code context using Git and unified-diff conventions";
    license = lib.licenses.lgpl21Only;
    mainProgram = "locsnip";
  };
})
