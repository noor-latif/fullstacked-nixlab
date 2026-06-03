{
  description = "NixOS VPS configuration for Pangolin and Mox mail";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/b51242d7d43689db2f3be91bd05d5b24fbb469c4";
  };

  outputs = { nixpkgs, ... }: {
    nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./nixos/configuration.nix
      ];
    };
  };
}
