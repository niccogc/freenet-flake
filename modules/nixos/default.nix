{withSystem}: {
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.freenet;

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
  options.services.freenet = {
    enable = mkEnableOption "Freenet node";

    package = mkOption {
      type = types.package;
      default = withSystem pkgs.stdenv.hostPlatform.system ({config, ...}: config.packages.freenet);
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
      type = types.path;
      default = "/var/lib/freenet";
      description = "Directory for Freenet state.";
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

    systemd.services.freenet = {
      description = "Freenet Node";
      wantedBy = ["multi-user.target"];
      after = ["network-online.target"];
      wants = ["network-online.target"];

      environment =
        {
          HOME = cfg.dataDir;
          FREENET_STATE_DIR = cfg.dataDir;
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
        StateDirectory = "freenet";
        LogsDirectory = "freenet";
        ReadWritePaths = [cfg.dataDir];
      };
    };

    networking.firewall = mkIf cfg.openFirewall {
      allowedTCPPorts = [cfg.firewallPort];
      allowedUDPPorts = [cfg.firewallPort];
    };
  };
}
