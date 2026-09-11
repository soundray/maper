{
  pkgs ? import <nixpkgs> {}
, pincram ? null
}:
let
  maper = pkgs.callPackage ./default.nix {};
  env = pkgs.buildEnv {
    name = "maper-docker-env";
    paths = [
      maper
      pkgs.bashInteractive
      pkgs.coreutils
      pkgs.cacert
    ]
    ++ pkgs.lib.optional (pincram != null) pincram;
  };
  # docs: https://nixos.org/nixpkgs/manual/#sec-pkgs-dockerTools
in (pkgs.dockerTools.buildImage {
  name = "registry.oak.sphalerite.org/maper";
  tag = "latest";
  copyToRoot = [
    env
  ];
  config.Env = [ "NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt" ];
  extraCommands = ''
    mkdir -p etc
    chmod u+w etc
    rm -f etc/passwd etc/group etc/nsswitch.conf
    cp -L ${pkgs.dockerTools.fakeNss}/etc/passwd etc/passwd
    cp -L ${pkgs.dockerTools.fakeNss}/etc/group etc/group
    cp -L ${pkgs.dockerTools.fakeNss}/etc/nsswitch.conf etc/nsswitch.conf
  '';
}) // {
  inherit env;
}
