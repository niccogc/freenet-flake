{
  description = "Freenet Core - A decentralized, censorship-resistant network";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = {
    self,
    nixpkgs,
  }: let
    system = "x86_64-linux";
    pkgs = import nixpkgs {inherit system;};

    freenet-pkg = pkgs.callPackage ./nix/packages/freenet.nix {};
  in {
    packages.${system} = {
      freenet = freenet-pkg;
      default = freenet-pkg;
    };

    nixosModules = {
      freenet = import ./nix/modules/nixos.nix {inherit freenet-pkg;};
      default = self.nixosModules.freenet;
    };

    homeManagerModules = {
      freenet = import ./nix/modules/home-manager.nix {inherit freenet-pkg;};
      default = self.homeManagerModules.freenet;
    };
  };
}
