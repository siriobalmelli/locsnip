{
  perSystem =
    {
      config,
      pkgs,
      ...
    }:
    {
      apps.default = {
        type = "app";
        meta.description = config.packages.default.meta.description;
        program = pkgs.lib.getExe config.packages.default;
      };
    };
}
