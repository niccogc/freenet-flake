{
  description = "Freenet Core (Gen 2) - x86_64";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = {
    self,
    nixpkgs,
  }: let
    system = "x86_64-linux";
    pkgs = import nixpkgs {inherit system;};
    freenet-pkg = pkgs.stdenv.mkDerivation rec {
      pname = "freenet-core";
      version = "0.1.125";
      src = pkgs.fetchurl {
        url = "https://github.com/freenet/freenet-core/releases/download/v${version}/freenet-x86_64-unknown-linux-musl.tar.gz";
        # hash = pkgs.lib.fakeHash;
        hash = "sha256-1rX3rYNynfw1I5D+iHjPt4ZWrPC6GPOx93JRzKCXuJg=";
      };
      nativeBuildInputs = [pkgs.autoPatchelfHook];
      buildInputs = [pkgs.stdenv.cc.cc.lib];
      unpackPhase = "tar -xzf $src";
      installPhase = "mkdir -p $out/bin && cp freenet $out/bin/ && chmod +x $out/bin/freenet";
    };
  in {
    packages.${system}.default = freenet-pkg;

    # This is the "Service" part
    nixosModules.default = {
      config,
      lib,
      ...
    }: {
      options.services.freenet-core = {
        enable = lib.mkEnableOption "Freenet Core Node";
      };

      config = lib.mkIf config.services.freenet-core.enable {
        systemd.user.services.freenet = {
          description = "Freenet Core Node (Gen 2)";
          after = ["network.target"];
          wantedBy = ["default.target"];
          serviceConfig = {
            ExecStart = "${freenet-pkg}/bin/freenet network";
            Restart = "always";
            RestartSec = "10";
          };
        };
      };
    };
  };
}
