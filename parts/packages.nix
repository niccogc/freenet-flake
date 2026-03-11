{
  perSystem = {pkgs, ...}: let
    # Simple wrapper: fetch binary if missing, then exec it
    # Expects DATA_DIR to be set by the module/environment
    mkWrapper = name:
      pkgs.writeShellScriptBin name ''
        set -euo pipefail

        : "''${DATA_DIR:?DATA_DIR must be set}"
        BINARY_PATH="$DATA_DIR/${name}"
        VERSION_FILE="$DATA_DIR/version"
        mkdir -p "$DATA_DIR"

        ARCH=$(uname -m)
        case "$ARCH" in
          x86_64)  TARGET="x86_64-unknown-linux-musl" ;;
          aarch64) TARGET="aarch64-unknown-linux-musl" ;;
          *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
        esac

        fetch_version() {
          local version="$1"
          echo "--- Fetching ${name} $version ($TARGET) from GitHub ---"

          ASSET_URL=$(${pkgs.curl}/bin/curl -sf "https://api.github.com/repos/freenet/freenet-core/releases/tags/$version" | \
                      ${pkgs.jq}/bin/jq -r ".assets[] | select(.name | contains(\"${name}\") and contains(\"$TARGET\")) | .browser_download_url" | head -n 1)

          if [ -z "$ASSET_URL" ] || [ "$ASSET_URL" = "null" ]; then
            echo "Error: Asset not found for version $version"
            return 1
          fi

          TARBALL_PATH=$(${pkgs.nix}/bin/nix-prefetch-url --print-path "$ASSET_URL" 2>/dev/null | tail -n 1)
          TMP_DIR=$(mktemp -d)
          ${pkgs.gnutar}/bin/tar -xzf "$TARBALL_PATH" -C "$TMP_DIR"

          EXTRACTED=$(find "$TMP_DIR" -type f \( -name "${name}" -o -name "freenet*" \) | head -n 1)
          if [ -z "$EXTRACTED" ]; then
            echo "Error: Could not find ${name} binary in archive"
            rm -rf "$TMP_DIR"
            return 1
          fi

          cp "$EXTRACTED" "$BINARY_PATH"
          chmod +x "$BINARY_PATH"
          echo "$version" > "$VERSION_FILE"
          rm -rf "$TMP_DIR"
          echo "Installed version $version"
        }

        if [ ! -f "$BINARY_PATH" ]; then
          REMOTE_VERSION=$(${pkgs.curl}/bin/curl -sf https://api.github.com/repos/freenet/freenet-core/releases/latest | \
                           ${pkgs.jq}/bin/jq -r '.tag_name // empty')
          if [ -z "$REMOTE_VERSION" ]; then
            echo "Error: Cannot fetch version info from GitHub"
            exit 1
          fi
          fetch_version "$REMOTE_VERSION" || exit 1
        fi

        exec "$BINARY_PATH" "$@"
      '';

    # Updater script: checks GitHub, updates if newer, restarts service
    # Expects DATA_DIR to be set, FREENET_SERVICE_NAME optional (for service restart)
    mkUpdater = name:
      pkgs.writeShellScriptBin "${name}-update" ''
        set -euo pipefail

        : "''${DATA_DIR:?DATA_DIR must be set}"
        BINARY_PATH="$DATA_DIR/${name}"
        VERSION_FILE="$DATA_DIR/version"
        mkdir -p "$DATA_DIR"

        ARCH=$(uname -m)
        case "$ARCH" in
          x86_64)  TARGET="x86_64-unknown-linux-musl" ;;
          aarch64) TARGET="aarch64-unknown-linux-musl" ;;
          *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
        esac

        get_remote_version() {
          ${pkgs.curl}/bin/curl -sf https://api.github.com/repos/freenet/freenet-core/releases/latest | \
            ${pkgs.jq}/bin/jq -r '.tag_name // empty'
        }

        get_local_version() {
          if [ -f "$VERSION_FILE" ]; then
            cat "$VERSION_FILE"
          fi
        }

        fetch_version() {
          local version="$1"
          echo "--- Fetching ${name} $version ($TARGET) from GitHub ---"

          ASSET_URL=$(${pkgs.curl}/bin/curl -sf "https://api.github.com/repos/freenet/freenet-core/releases/tags/$version" | \
                      ${pkgs.jq}/bin/jq -r ".assets[] | select(.name | contains(\"${name}\") and contains(\"$TARGET\")) | .browser_download_url" | head -n 1)

          if [ -z "$ASSET_URL" ] || [ "$ASSET_URL" = "null" ]; then
            echo "Error: Asset not found for version $version"
            return 1
          fi

          TARBALL_PATH=$(${pkgs.nix}/bin/nix-prefetch-url --print-path "$ASSET_URL" 2>/dev/null | tail -n 1)
          TMP_DIR=$(mktemp -d)
          ${pkgs.gnutar}/bin/tar -xzf "$TARBALL_PATH" -C "$TMP_DIR"

          EXTRACTED=$(find "$TMP_DIR" -type f \( -name "${name}" -o -name "freenet*" \) | head -n 1)
          if [ -z "$EXTRACTED" ]; then
            echo "Error: Could not find ${name} binary in archive"
            rm -rf "$TMP_DIR"
            return 1
          fi

          cp "$EXTRACTED" "$BINARY_PATH"
          echo "$version" > "$VERSION_FILE"
          # Set ownership if running as root with FREENET_USER set
          if [ "$(id -u)" = "0" ] && [ -n "''${FREENET_USER:-}" ]; then
            chown "''${FREENET_USER}:''${FREENET_GROUP:-$FREENET_USER}" "$BINARY_PATH" "$VERSION_FILE"
          fi
          chmod 700 "$BINARY_PATH"
          chmod 600 "$VERSION_FILE"
          rm -rf "$TMP_DIR"
          echo "Updated to version $version"
        }

        stop_service() {
          if [ -n "''${FREENET_SERVICE_NAME:-}" ]; then
            echo "Stopping $FREENET_SERVICE_NAME..."
            ${pkgs.systemd}/bin/systemctl stop "$FREENET_SERVICE_NAME" 2>/dev/null || \
              ${pkgs.systemd}/bin/systemctl --user stop "$FREENET_SERVICE_NAME" 2>/dev/null || true
            sleep 2
          fi
        }

        start_service() {
          if [ -n "''${FREENET_SERVICE_NAME:-}" ]; then
            echo "Starting $FREENET_SERVICE_NAME..."
            ${pkgs.systemd}/bin/systemctl start "$FREENET_SERVICE_NAME" 2>/dev/null || \
              ${pkgs.systemd}/bin/systemctl --user start "$FREENET_SERVICE_NAME" 2>/dev/null || \
              echo "Note: Could not start service. Manual start may be needed."
          fi
        }

        REMOTE_VERSION=$(get_remote_version)
        if [ -z "$REMOTE_VERSION" ]; then
          echo "Warning: Could not fetch remote version"
          exit 0
        fi

        LOCAL_VERSION=$(get_local_version)

        if [ "$REMOTE_VERSION" != "$LOCAL_VERSION" ]; then
          echo "Update available: $LOCAL_VERSION -> $REMOTE_VERSION"
          stop_service
          fetch_version "$REMOTE_VERSION"
          start_service
        else
          echo "Already at latest version: $LOCAL_VERSION"
        fi
      '';
  in {
    packages = {
      freenet = mkWrapper "freenet";
      fdev = mkWrapper "fdev";
      default = mkWrapper "freenet";

      freenet-update = mkUpdater "freenet";
      fdev-update = mkUpdater "fdev";
    };
  };
}
