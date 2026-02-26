{
  perSystem = {
    config,
    pkgs,
    ...
  }: {
    devShells.default = pkgs.mkShell {
      buildInputs = [
        config.packages.freenet
        config.packages.fdev
        pkgs.curl
        pkgs.jq
        pkgs.gnutar
      ];

      shellHook = ''
        echo "Freenet development shell"
        echo "  freenet - Run Freenet node (auto-updating)"
        echo "  fdev    - Run Freenet dev tools (auto-updating)"
      '';
    };
  };
}
