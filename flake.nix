{
  description = "NixOS VPS configuration for Pangolin and Mox mail";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/b51242d7d43689db2f3be91bd05d5b24fbb469c4";
  };

  outputs = { nixpkgs, ... }: {
    nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ({ ... }: {
          nixpkgs.overlays = [
            (final: prev: {
              lego = prev.lego.overrideAttrs (old: rec {
                version = "5.2.2";
                src = final.fetchFromGitHub {
                  owner = "go-acme";
                  repo = "lego";
                  tag = "v${version}";
                  hash = "sha256-uo2XbCtsFEmdcCevb5aelQ9452LjEqNJb2dR8oWDJFc=";
                };
                vendorHash = "sha256-PtE/3oADcNo/Vv1zZoPkzsWu8+ea2jRtt9avqjdGATs=";
                subPackages = [ "." ];
              });
            })
          ];
        })
        ./nixos/configuration.nix
      ];
    };
  };
}
