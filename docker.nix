{
  # nixos-unstable as of 2023-05-26
  pkgsPath ? builtins.fetchTarball https://github.com/nixos/nixpkgs/archive/bfb7a882678e518398ce9a31a881538679f6f092.tar.gz
, pkgs ? import <nixpkgs> {}
}:
let
  maper = pkgs.callPackage ./default.nix {};
  env = pkgs.buildEnv {
    name = "maper-docker-env";
    paths = [ maper pkgs.bashInteractive pkgs.coreutils pkgs.cacert ];
  };
  # docs: https://nixos.org/nixpkgs/manual/#sec-pkgs-dockerTools
in (pkgs.dockerTools.buildImage {
  name = "registry.oak.sphalerite.org/maper";
  tag = "latest";
  copyToRoot = env;
  config.Env = [ "NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt" ];
  runAsRoot = ''
    chmod -vR u+w /etc
  '';
}) // {
  inherit env;
}
