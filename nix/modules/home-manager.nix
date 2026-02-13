{freenet-pkg}: {
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.freenet-core;
in {
  options.services.freenet-core = {
    enable = lib.mkEnableOption "Freenet Core Node (user service)";

    package = lib.mkOption {
      type = lib.types.package;
      default = freenet-pkg;
      description = "The Freenet Core package to use.";
    };

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
    home.packages = [cfg.package];

    systemd.user.services.freenet = {
      Unit = {
        Description = "Freenet Core Node";
        After = ["network.target"];
      };

      Service = {
        ExecStart = "${cfg.package}/bin/freenet network";
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

      Install = lib.mkIf cfg.autostart {
        WantedBy = ["default.target"];
      };
    };
  };
}
