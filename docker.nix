{
  pkgs ? import <nixpkgs> {}
, pincram ? null
, posnorm ? null
}:
let
  maper = pkgs.callPackage ./default.nix {};

  pythonEnv = pkgs.callPackage ./python-env.nix {};

  shellTools = [
    pkgs.diffutils
    pkgs.file
    pkgs.findutils
    pkgs.gawk
    pkgs.gnugrep
    pkgs.gnused
    pkgs.gnutar
    pkgs.gzip
    pkgs.less
    pkgs.util-linux
    pythonEnv
  ];

  env = pkgs.buildEnv {
    name = "maper-docker-env";
    paths = [
      maper
      pkgs.mirtk
      pkgs.niftyseg
      pkgs.bashInteractive
      pkgs.coreutils
      pkgs.cacert
      pkgs.ants
    ]
    ++ shellTools
    ++ pkgs.lib.optional (pincram != null) pincram
    ++ pkgs.lib.optional (posnorm != null) posnorm;
  };

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
