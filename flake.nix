{
  description = "Freenet Core - x86_64";

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
        hash = "sha256-1rX3rYNynfw1I5D+iHjPt4ZWrPC6GPOx93JRzKCXuJg=";
      };
      nativeBuildInputs = [pkgs.autoPatchelfHook];
      buildInputs = [pkgs.stdenv.cc.cc.lib];
      unpackPhase = "tar -xzf $src";
      installPhase = "mkdir -p $out/bin && cp freenet $out/bin/ && chmod +x $out/bin/freenet";
    };
  in {
    packages.${system}.default = freenet-pkg;

    nixosModules.default = {
      config,
      lib,
      ...
    }: let
      cfg = config.services.freenet-core;
    in {
      options.services.freenet-core = {
        enable = lib.mkEnableOption "Freenet Core Node";

        autostart = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Automatically start Freenet on login.";
        };

        telemetry = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable anonymous telemetry.";
        };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [freenet-pkg];

        systemd.user.services.freenet = {
          description = "Freenet Core Node";
          after = ["network.target"];
          wantedBy =
            if cfg.autostart
            then ["default.target"]
            else [];

          serviceConfig = {
            ExecStart = "${freenet-pkg}/bin/freenet network";
            Environment = [
              "FREENET_TELEMETRY_ENABLED=${
                if cfg.telemetry
                then "true"
                else "false"
              }"
            ];
            Restart = "always";
            RestartSec = "10";
          };
        };
      };
    };
  };
}
