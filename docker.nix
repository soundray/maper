# The image for running maper pipelines. What is in it falls into three tiers, each
# declared where it belongs, so that the maper package says truthfully what it needs:
#   1. what maper and pincram need to run (MIRTK, NiftySeg ...)  -> default.nix
#   2. what maper's ancillary scripts need (nibabel, numpy)       -> python-env.nix
#   3. what the pipelines around maper use (ANTs for N4, scipy, which pincram needs, too,
#      the shell tools, pincram and posnorm themselves)           -> here, and only here
# Nothing of tier 3 is a dependency of the maper package; tests/nix-checks.nix checks that.
{
  pkgs ? import <nixpkgs> {}
, pincram ? null
, posnorm ? null
}:
let
  maper = pkgs.callPackage ./default.nix {};

  # The one Python of the image serves tiers 2 and 3: the modules of python-env.nix, and
  # scipy on top
  pythonEnv = pkgs.callPackage ./python-env.nix {
    extraPackages = ps: [ ps.scipy ];
  };

  tier1 = [
    maper
    pkgs.mirtk
    pkgs.niftyseg
  ];

  tier2 = [
    pythonEnv
  ];

  tier3 = [
    pkgs.ants # N4 bias field correction
    pkgs.bashInteractive
    pkgs.cacert
    pkgs.coreutils
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
  ]
  ++ pkgs.lib.optional (pincram != null) pincram
  ++ pkgs.lib.optional (posnorm != null) posnorm;

  env = pkgs.buildEnv {
    name = "maper-docker-env";
    paths = tier1 ++ tier2 ++ tier3;
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
  inherit env pythonEnv;
}
