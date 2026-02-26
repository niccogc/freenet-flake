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
    enable = mkEnableOption "Freenet node (user service)";

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
  };

  config = mkIf cfg.enable {
    home.packages = [cfg.package];

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
        RestartSec = 10;
        Environment = mapAttrsToList (k: v: "${k}=${v}") ({
            FREENET_STATE_DIR = "%h/.local/state/freenet";
          }
          // cfg.environment);
      };

      Install = {
        WantedBy = ["default.target"];
      };
    };
  };
}
