{withSystem}: {
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.local.services.freenet;
  packages = withSystem pkgs.stdenv.hostPlatform.system ({config, ...}: config.packages);

  # Wrap packages with environment variables
  wrappedFreenet = pkgs.writeShellScriptBin "freenet" ''
    CONFIG_DIR="${cfg.dataDir}" \
    DATA_DIR="${cfg.dataDir}" \
    LOG_DIR="${cfg.dataDir}" \
    exec ${packages.freenet}/bin/freenet "$@"
  '';

  wrappedFdev = pkgs.writeShellScriptBin "fdev" ''
    CONFIG_DIR="${cfg.dataDir}" \
    DATA_DIR="${cfg.dataDir}" \
    LOG_DIR="${cfg.dataDir}" \
    exec ${packages.fdev}/bin/fdev "$@"
  '';

  # Convert attrset to CLI flags: { fooBar = "value"; } -> ["--foo-bar" "value"]
  toFlags = attrs:
    flatten (mapAttrsToList (
        name: value: let
          flag = "--${replaceStrings upperChars (map (c: "-${c}") lowerChars) name}";
        in
          if value == true
          then [flag]
          else if value == false || value == null
          then []
          else if isList value
          then concatMap (v: [flag (toString v)]) value
          else [flag (toString value)]
      )
      attrs);
in {
  options.local.services.freenet = {
    enable = mkEnableOption "Freenet node";

    package = mkOption {
      type = types.package;
      default = packages.freenet;
      defaultText = literalExpression "pkgs.freenet";
      description = "The Freenet package to use.";
    };

    mode = mkOption {
      type = types.enum ["network" "local"];
      default = "network";
      description = "Node operation mode.";
    };

    user = mkOption {
      type = types.str;
      default = "freenet";
      description = "User account under which Freenet runs.";
    };

    group = mkOption {
      type = types.str;
      default = "freenet";
      description = "Group under which Freenet runs.";
    };

    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/freenet";
      description = "Directory for Freenet data and binaries.";
    };

    logDir = mkOption {
      type = types.str;
      default = "/var/log/freenet";
      description = "Directory for Freenet logs.";
    };

    configDir = mkOption {
      type = types.str;
      default = "/var/lib/freenet/config";
      description = "Directory for Freenet configs.";
    };
    settings = mkOption {
      type = types.attrsOf (types.oneOf [types.bool types.int types.str types.path (types.listOf types.str)]);
      default = {};
      example = literalExpression ''
        {
          wsApiPort = 7509;
          networkPort = 31337;
          isGateway = true;
          logLevel = "info";
          blockedAddresses = ["192.168.1.1:8080"];
        }
      '';
      description = ''
        Freenet settings as an attribute set. Names are converted from camelCase
        to --kebab-case flags. Boolean true adds the flag, false/null omits it.
      '';
    };

    environment = mkOption {
      type = types.attrsOf types.str;
      default = {};
      example = literalExpression ''
        {
          RUST_LOG = "debug";
          FREENET_TELEMETRY_ENABLED = "true";
        }
      '';
      description = "Environment variables for the Freenet service.";
    };

    extraArgs = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Extra command-line arguments to pass to Freenet.";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to open the firewall for Freenet's network port.";
    };

    firewallPort = mkOption {
      type = types.port;
      default = 31337;
      description = "Port to open in the firewall (if openFirewall is true).";
    };

    autoUpdate = {
      enable = mkEnableOption "automatic updates via systemd timer";

      interval = mkOption {
        type = types.str;
        default = "hourly";
        example = "*:0/5";
        description = "Systemd calendar expression for update check frequency. Examples: 'hourly', 'daily', '*:0/5' (every 5 min).";
      };
    };
  };

  config = mkIf cfg.enable {
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.group;
      home = cfg.dataDir;
      createHome = true;
      description = "Freenet daemon user";
    };

    users.groups.${cfg.group} = {};

    # Add wrapped freenet and fdev to system packages
    environment.systemPackages = [wrappedFreenet wrappedFdev];

    systemd.tmpfiles.rules = [
      "d '${cfg.dataDir}' 0750 ${cfg.user} ${cfg.group} - -"
      "d '${cfg.logDir}' 0750 ${cfg.user} ${cfg.group} - -"
      "d '${cfg.configDir}' 0750 ${cfg.user} ${cfg.group} - -"
    ];

    systemd.services.freenet = {
      description = "Freenet Node";
      wantedBy = ["multi-user.target"];
      after = ["network-online.target"];
      wants = ["network-online.target"];

      # gzip is needed by tar for .tar.gz extraction on first run
      path = [pkgs.gzip];
      environment =
        {
          HOME = cfg.dataDir;
          CONFIG_DIR = cfg.configDir;
          DATA_DIR = cfg.dataDir;
          LOG_DIR = cfg.logDir;
        }
        // cfg.environment;

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = cfg.dataDir;
        ExecStart = escapeShellArgs ([
            "${cfg.package}/bin/freenet"
            cfg.mode
          ]
          ++ (toFlags cfg.settings)
          ++ cfg.extraArgs);
        Restart = "on-failure";
        RestartSec = 10;

        # Hardening
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictNamespaces = true;
        RestrictSUIDSGID = true;
        MemoryDenyWriteExecute = false;

        # Directories
        ReadWritePaths = [cfg.dataDir];
      };
    };

    systemd.services.freenet-update = mkIf cfg.autoUpdate.enable {
      description = "Freenet Auto-Updater";
      after = ["network-online.target"];
      wants = ["network-online.target"];

      # gzip is needed by tar for .tar.gz extraction
      path = [pkgs.gzip];

      environment = {
        HOME = cfg.dataDir;
        DATA_DIR = cfg.dataDir;
      };

      serviceConfig = {
        Type = "oneshot";
        User = cfg.user;
        Group = cfg.group;
        # Stop freenet before update, restart after (+ runs as root)
        ExecStartPre = [
          "+${pkgs.systemd}/bin/systemctl stop freenet.service"
          "${pkgs.coreutils}/bin/sleep 10"
        ];
        ExecStart = "${packages.freenet-update}/bin/freenet-update";
        ExecStartPost = "+${pkgs.systemd}/bin/systemctl start freenet.service";
        ReadWritePaths = [cfg.dataDir];
      };
    };

    systemd.timers.freenet-update = mkIf cfg.autoUpdate.enable {
      description = "Freenet Update Timer";
      wantedBy = ["timers.target"];

      timerConfig = {
        OnCalendar = cfg.autoUpdate.interval;
        Persistent = true;
        RandomizedDelaySec = "5min";
      };
    };

    networking.firewall = mkIf cfg.openFirewall {
      allowedTCPPorts = [cfg.firewallPort];
      allowedUDPPorts = [cfg.firewallPort];
    };
  };
}
