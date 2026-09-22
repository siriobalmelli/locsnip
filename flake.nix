{
  description = "locsnip Zig CLI scaffold";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      imports =
        let
          inherit (inputs.nixpkgs.lib) filterAttrs hasSuffix mapAttrsToList;
          modules = filterAttrs (name: type: type == "regular" && hasSuffix ".nix" name) (
            builtins.readDir ./nix
          );
        in
        mapAttrsToList (name: _: ./nix/${name}) modules;
    };
}
