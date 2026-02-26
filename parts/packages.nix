{
  perSystem = {pkgs, ...}: let
    mkAutoupdater = name:
      pkgs.writeShellScriptBin name ''
        trap "exit" INT TERM

        STATE_DIR="''${FREENET_STATE_DIR:-$HOME/.local/state/${name}}"
        BINARY_PATH="$STATE_DIR/${name}"
        mkdir -p "$STATE_DIR"

        ARCH=$(uname -m)
        case "$ARCH" in
          x86_64)  TARGET="x86_64-unknown-linux-musl" ;;
          aarch64) TARGET="aarch64-unknown-linux-musl" ;;
          *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
        esac

        # Function to fetch the absolute latest from GitHub
        fetch_latest() {
            echo "--- Fetching latest ${name} ($TARGET) from GitHub ---"
            ASSET_URL=$(${pkgs.curl}/bin/curl -s https://api.github.com/repos/freenet/freenet-core/releases/latest | \
                        ${pkgs.jq}/bin/jq -r ".assets[] | select(.name | contains(\"${name}\") and contains(\"$TARGET\")) | .browser_download_url" | head -n 1)

            if [ -z "$ASSET_URL" ] || [ "$ASSET_URL" = "null" ]; then
                echo "Error: Asset not found."
                return 1
            fi

            TARBALL_PATH=$(${pkgs.nix}/bin/nix-prefetch-url --print-path "$ASSET_URL" | tail -n 1)
            TMP_DIR=$(mktemp -d)
            ${pkgs.gnutar}/bin/tar -xzf "$TARBALL_PATH" -C "$TMP_DIR"

            EXTRACTED=$(find "$TMP_DIR" -type f \( -name "${name}" -o -name "freenet*" \) | head -n 1)
            cp "$EXTRACTED" "$BINARY_PATH"
            chmod +x "$BINARY_PATH"
            rm -rf "$TMP_DIR"
        }

        # Initial check: if binary doesn't exist at all, fetch it
        if [ ! -f "$BINARY_PATH" ]; then
            fetch_latest || exit 1
        fi

        while true; do
            echo "--- Starting ${name} ---"
            "$BINARY_PATH" "$@"
            exit_code=$?

            if [ $exit_code -eq 42 ]; then
                echo "Autoupdate triggered by exit code 42. Updating..."
                fetch_latest
                sleep 1
            else
                echo "Exited with code: $exit_code. Stopping."
                break
            fi
        done
      '';
  in {
    packages = {
      freenet = mkAutoupdater "freenet";
      fdev = mkAutoupdater "fdev";
      default = mkAutoupdater "freenet";
    };
  };
}
