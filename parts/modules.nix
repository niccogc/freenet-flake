{
  withSystem,
  ...
}: {
  # Modern flake.modules with class checking (flake-parts 0.1+)
  flake.modules = {
    nixos.freenet = import ../modules/nixos {inherit withSystem;};
    home-manager.freenet = import ../modules/home-manager {inherit withSystem;};
  };

  # Legacy attributes for compatibility
  flake.nixosModules = {
    freenet = import ../modules/nixos {inherit withSystem;};
    default = import ../modules/nixos {inherit withSystem;};
  };

  flake.homeManagerModules = {
    freenet = import ../modules/home-manager {inherit withSystem;};
    default = import ../modules/home-manager {inherit withSystem;};
  };
}
