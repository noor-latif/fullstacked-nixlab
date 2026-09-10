{
  description = "NixOS configuration for the fullstacked.se mail/infra stack (Stalwart + Caddy)";

  inputs = {
    # Track a single, current nixpkgs. nixos-unstable carries modern packages
    # (e.g. stalwart_0_16) that the 26.05 release branch lacks. The resolved
    # commit is pinned in flake.lock for reproducibility; update deliberately
    # with `nix flake update nixpkgs`, then rebuild + commit.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { nixpkgs, ... }: {
    nixosModules.bridge-ports = ./modules/bridge-ports;

    nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./nixos/configuration.nix
      ];
    };
  };
}
