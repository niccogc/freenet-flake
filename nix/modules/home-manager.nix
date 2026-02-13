{freenet-pkg}: {
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.freenet-core;

  updateCheckerScript = pkgs.writeShellScript "freenet-update-checker" ''
    set -euo pipefail

    CURRENT_VERSION="${freenet-pkg.version}"
    GITHUB_API="https://api.github.com/repos/freenet/freenet-core/releases/latest"

    LATEST_VERSION=$(${pkgs.curl}/bin/curl -sf "$GITHUB_API" | ${pkgs.jq}/bin/jq -r '.tag_name' | sed 's/^v//')

    if [ -z "$LATEST_VERSION" ]; then
      echo "Failed to fetch latest version"
      exit 1
    fi

    echo "Current: $CURRENT_VERSION, Latest: $LATEST_VERSION"

    if [ "$CURRENT_VERSION" != "$LATEST_VERSION" ]; then
      ${pkgs.libnotify}/bin/notify-send \
        --urgency=normal \
        --icon=software-update-available \
        --app-name="Freenet" \
        "Freenet Update Available" \
        "New version $LATEST_VERSION is available (current: $CURRENT_VERSION)"
    fi
  '';
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

    updateChecker = {
      enable = lib.mkEnableOption "Freenet version update checker";

      interval = lib.mkOption {
        type = lib.types.str;
        default = "daily";
        description = "How often to check for updates (systemd calendar format).";
        example = "hourly";
      };
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

    systemd.user.services.freenet-update-checker = lib.mkIf cfg.updateChecker.enable {
      Unit = {
        Description = "Freenet Update Checker";
        After = ["network-online.target"];
      };

      Service = {
        Type = "oneshot";
        ExecStart = "${updateCheckerScript}";
        Environment = ["DISPLAY=:0"];
      };
    };

    systemd.user.timers.freenet-update-checker = lib.mkIf cfg.updateChecker.enable {
      Unit = {
        Description = "Freenet Update Checker Timer";
      };

      Timer = {
        OnCalendar = cfg.updateChecker.interval;
        Persistent = true;
        RandomizedDelaySec = "5min";
      };

      Install = {
        WantedBy = ["timers.target"];
      };
    };
  };
}
