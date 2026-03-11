{withSystem}: {
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.freenet;
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
  options.services.freenet = {
    enable = mkEnableOption "Freenet node (user service)";

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

    autostart = mkEnableOption "Autostart Freenet";

    dataDir = mkOption {
      type = types.str;
      default = "${config.home.homeDirectory}/.local/share/freenet";
      description = "Directory for Freenet data and binaries.";
    };

    logDir = mkOption {
      type = types.str;
      default = "${config.home.homeDirectory}/.local/state/logs/freenet";
      description = "Directory for Freenet logs.";
    };

    configDir = mkOption {
      type = types.str;
      default = "${config.home.homeDirectory}/.config/freenet";
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
        }
      '';
      description = "Environment variables for the Freenet service.";
    };

    extraArgs = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Extra command-line arguments to pass to Freenet.";
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
    home.packages = [wrappedFreenet wrappedFdev];

    systemd.user.services.freenet = {
      Unit = {
        Description = "Freenet Node (User Service)";
        After = ["network-online.target"];
        Wants = ["network-online.target"];
      };

      Service = {
        Type = "simple";
        ExecStart = escapeShellArgs ([
            "${cfg.package}/bin/freenet"
            cfg.mode
          ]
          ++ (toFlags cfg.settings)
          ++ cfg.extraArgs);
        Restart = "on-failure";
        RestartSec = 30;
        Environment = mapAttrsToList (k: v: "${k}=${v}") ({
            CONFIG_DIR = cfg.configDir;
            DATA_DIR = cfg.dataDir;
            LOG_DIR = cfg.logDir;
          }
          // cfg.environment);
      };

      Install = {
        WantedBy = lib.optionals cfg.autostart ["default.target"];
      };
    };

    systemd.user.services.freenet-update = mkIf cfg.autoUpdate.enable {
      Unit = {
        Description = "Freenet Auto-Updater";
        After = ["network-online.target"];
        Wants = ["network-online.target"];
        # Stop freenet while updating, restart after success
        Conflicts = ["freenet.service"];
        OnSuccess = ["freenet.service"];
      };

      Service = {
        Type = "oneshot";
        ExecStart = "${packages.freenet-update}/bin/freenet-update";
        Environment = [
          "DATA_DIR=${cfg.dataDir}"
          "FREENET_SERVICE_NAME=freenet.service"
        ];
      };
    };

    systemd.user.timers.freenet-update = mkIf cfg.autoUpdate.enable {
      Unit = {
        Description = "Freenet Update Timer";
      };

      Timer = {
        OnCalendar = cfg.autoUpdate.interval;
        Persistent = true;
        RandomizedDelaySec = "5min";
      };

      Install = {
        WantedBy = ["timers.target"];
      };
    };
  };
}
