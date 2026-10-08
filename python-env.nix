# python-env.nix
{ pkgs ? import <nixpkgs> {} }:

pkgs.python3.withPackages (ps: [
  ps.nibabel
  ps.numpy
])
