{
    description = "MAPER - Multi-atlas propagation with enhanced registration";

    inputs = {
      nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

      pincram = {
        url = "github:soundray/pincram";
        inputs.nixpkgs.follows = "nixpkgs";
      };
    };

    outputs = { self, nixpkgs, pincram }:
      let
        system = "x86_64-linux";

        pkgs = import nixpkgs {
          inherit system;
        };

        maper = import ./default.nix {
          inherit pkgs;
        };

        pincramPackage = pincram.packages.${system}.pincram;

        container = import ./docker.nix {
          inherit pkgs;
          pincram = pincramPackage;
        };
      in {
        packages.${system} = {
          inherit maper container;

          pincram = pincramPackage;

          default = maper;
        };
      };
  }
