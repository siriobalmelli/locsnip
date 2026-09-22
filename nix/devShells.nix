{
  perSystem =
    { config, pkgs, ... }:
    {
      devShells.default = pkgs.mkShellNoCC {
        inputsFrom = [ config.packages.default ] ++ builtins.attrValues config.packages.default.tests;
        packages = [ pkgs.file ];
      };
    };
}
