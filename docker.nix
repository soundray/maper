{
  pkgs ? import <nixpkgs> {}
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
}) // {
  inherit env;
}
