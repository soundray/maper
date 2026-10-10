# python-env.nix: the Python that maper's ancillary scripts need (tier 2, see docker.nix)
{ pkgs ? import <nixpkgs> {}
, extraPackages ? (_ps: [])   # more modules; only docker.nix passes any (tier 3)
}:

pkgs.python3.withPackages (ps: [
  ps.nibabel
  ps.numpy
] ++ extraPackages ps)
