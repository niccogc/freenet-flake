# Freenet Flake

NixOS and Home Manager modules for running [Freenet](https://freenet.org/) nodes with auto-updating binaries.

## Features

- Auto-updating Freenet binaries from GitHub releases
- NixOS module (`services.freenet`) for system-level daemon
- Home Manager module (`services.freenet`) for user-level service
- Freeform settings — no module updates needed when Freenet adds new flags

## Installation

Add to your `flake.nix` inputs:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    freenet.url = "github:nicco/freenet-flake";  # adjust to your repo
  };
}
```

## NixOS Module

```nix
{ inputs, ... }: {
  imports = [ inputs.freenet.nixosModules.freenet ];

  services.freenet = {
    enable = true;
    mode = "network";  # or "local" for development

    # Freeform settings: camelCase → --kebab-case flags
    settings = {
      wsApiPort = 7509;
      networkPort = 31337;
      isGateway = true;
      logLevel = "info";
      minNumberOfConnections = 10;
      maxNumberOfConnections = 20;
    };

    # Environment variables passed to systemd
    environment = {
      RUST_LOG = "info";
    };

    openFirewall = true;
    firewallPort = 31337;
  };
}
```

## Home Manager Module

```nix
{ inputs, ... }: {
  imports = [ inputs.freenet.homeManagerModules.freenet ];

  services.freenet = {
    enable = true;
    mode = "network";

    settings = {
      wsApiPort = 7509;
      networkPort = 31337;
      logLevel = "info";
    };

    environment = {
      RUST_LOG = "debug";
    };
  };
}
```

## Settings Pattern

The `settings` attribute uses a freeform pattern — any key-value pair is converted to CLI flags:

| Nix | CLI Flag |
|-----|----------|
| `wsApiPort = 7509` | `--ws-api-port 7509` |
| `isGateway = true` | `--is-gateway` |
| `isGateway = false` | *(omitted)* |
| `logLevel = "info"` | `--log-level info` |
| `blockedAddresses = ["1.2.3.4" "5.6.7.8"]` | `--blocked-addresses 1.2.3.4 --blocked-addresses 5.6.7.8` |

Run `nix run github:you/freenet-flake#freenet -- --help` to see all available Freenet options.

## Packages

```bash
# Run Freenet node (auto-updating)
nix run .#freenet

# Run Freenet dev tools (auto-updating)
nix run .#fdev

# Enter dev shell with both tools
nix develop
```

## Module Options

### NixOS

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | `false` | Enable Freenet service |
| `package` | package | auto | Freenet package to use |
| `mode` | enum | `"network"` | `"network"` or `"local"` |
| `user` | string | `"freenet"` | System user |
| `group` | string | `"freenet"` | System group |
| `dataDir` | path | `/var/lib/freenet` | State directory |
| `settings` | attrs | `{}` | Freeform CLI flags |
| `environment` | attrs | `{}` | Environment variables |
| `extraArgs` | list | `[]` | Extra CLI arguments |
| `openFirewall` | bool | `false` | Open firewall ports |
| `firewallPort` | port | `31337` | Port to open |

### Home Manager

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | `false` | Enable Freenet user service |
| `package` | package | auto | Freenet package to use |
| `mode` | enum | `"network"` | `"network"` or `"local"` |
| `settings` | attrs | `{}` | Freeform CLI flags |
| `environment` | attrs | `{}` | Environment variables |
| `extraArgs` | list | `[]` | Extra CLI arguments |

## License

MIT
