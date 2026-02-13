{freenet-pkg}: {
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.freenet-core;
in {
  options.services.freenet-core = {
    enable = lib.mkEnableOption "Freenet Core Node";

    package = lib.mkOption {
      type = lib.types.package;
      default = freenet-pkg;
      description = "The Freenet Core package to use.";
    };

    telemetry = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable anonymous telemetry.";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/freenet";
      description = "Directory to store Freenet data.";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "freenet";
      description = "User account under which Freenet runs.";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "freenet";
      description = "Group under which Freenet runs.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [cfg.package];

    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.group;
      home = cfg.dataDir;
      createHome = true;
      description = "Freenet Core daemon user";
    };

    users.groups.${cfg.group} = {};

    systemd.services.freenet = {
      description = "Freenet Core Node";
      after = ["network.target"];
      wantedBy = ["multi-user.target"];

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = cfg.dataDir;
        ExecStart = "${cfg.package}/bin/freenet network";
        Environment = [
          "FREENET_TELEMETRY_ENABLED=${
            if cfg.telemetry
            then "true"
            else "false"
          }"
          "HOME=${cfg.dataDir}"
        ];
        Restart = "always";
        RestartSec = "10";

        # Hardening
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [cfg.dataDir];
      };
    };
  };
}
