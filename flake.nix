{
  description = "MAPER - Multi-atlas propagation with enhanced registration";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      maper = import ./default.nix { inherit pkgs; };
    in {
      packages.${system} = {
        inherit maper;
        default = maper;
      };
    };
}
