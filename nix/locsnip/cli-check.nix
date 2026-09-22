{
  bash,
  runCommand,
  package,
}:
runCommand "locsnip-cli-check"
  {
    nativeBuildInputs = [ bash ];
  }
  ''
    ${bash}/bin/bash ${../../tests/cli.sh} ${package}/bin/locsnip ${package.version}
    touch "$out"
  ''
