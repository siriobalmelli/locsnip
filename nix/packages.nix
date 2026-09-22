{
  perSystem =
    {
      config,
      pkgs,
      ...
    }:
    let
      default = pkgs.callPackage ./locsnip { };
      targetPackages = default.passthru.cross;
    in
    {
      packages = targetPackages // {
        inherit default;

        all = pkgs.linkFarm "locsnip-all" (
          pkgs.lib.mapAttrsToList (name: targetPackage: {
            inherit name;
            path = "${targetPackage}/bin";
          }) targetPackages
        );
      };
    };
}
