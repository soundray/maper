{
  # nixos-19.09 as of 2019-12-29
  pkgsPath ? builtins.fetchTarball https://github.com/nixos/nixpkgs/archive/eab4ee0c27c5c6f622aa0ca55091c394a9e33edd.tar.gz
, pkgs ? import <nixpkgs> {}
}:
let
  maper = pkgs.callPackage ./default.nix {};
  # docs: https://nixos.org/nixpkgs/manual/#sec-pkgs-dockerTools
in pkgs.dockerTools.buildImage {
  name = "maper";
  tag = "latest";
  contents = [ maper pkgs.bashInteractive pkgs.coreutils pkgs.cacert pkgs.vim ];
  config.Env = [ "NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt" ];
}
