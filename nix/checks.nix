{
  perSystem =
    { config, ... }:
    {
      checks = config.packages.default.tests;
    };
}
