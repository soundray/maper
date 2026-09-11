{
  description = "MAPER - Multi-atlas propagation with enhanced registration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    pincram = {
      url = "github:soundray/pincram";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    posnorm = {
      url = "github:soundray/posnorm";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, pincram, posnorm }:
    let
      system = "x86_64-linux";

      pkgs = import nixpkgs {
        inherit system;
      };

      maper = import ./default.nix {
        inherit pkgs;
      };

      pincramPackage = pincram.packages.${system}.pincram;
      posnormPackage = posnorm.packages.${system}.posnorm;

      container = import ./docker.nix {
        inherit pkgs;
        pincram = pincramPackage;
        posnorm = posnormPackage;
      };
    in {
      packages.${system} = {
        inherit maper container;

        pincram = pincramPackage;
        posnorm = posnormPackage;

        default = maper;
      };
    };
}
