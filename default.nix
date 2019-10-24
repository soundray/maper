{
  # nixos-19.03 as of 2019-10-04
  pkgsPath ? builtins.fetchTarball https://github.com/nixos/nixpkgs/archive/6420e2649fa9e267481fb78e602022dab9d1dcd1.tar.gz
  # nixpkgs to use
, pkgs ? import pkgsPath {}
}:
let
  inherit (pkgs) lib;
  src = lib.cleanSource ./.;
  binpath = pkgs.lib.concatStringsSep ":" [
    "$out/bin" # sample needs maper on PATH
    "${pkgs.mirtk}/lib/tools" # maper needs non-namespaced mirtk tools
    "${pkgs.niftyseg}/bin"
    "${pkgs.coreutils}/bin" # For date
    "${pkgs.curl}/bin" # For example script to download sample data
    "${pkgs.gnutar}/bin" # For example script to unpack sample data
    "${pkgs.findutils}/bin" # For xargs
    "${pkgs.gnugrep}/bin"
    "${pkgs.gnused}/bin"
    "${pkgs.bc}/bin"
  ];
in pkgs.runCommandNoCC "maper-1.2.3" {
  meta = {
    license = lib.licenses.gpl2;
    description = "Multi-atlas propagation with enhanced registration";
    homepage = https://soundray.org/maper/;
  };
} ''
  mkdir -p $out/bin $out/lib/maper
  cp ${src}/{maper,launchlist-gen,generic-functions,run-maper-example.sh} $out/lib/maper
  for f in $out/lib/maper/* ; do patchShebangs $f ; done
  cp ${src}/neutral.dof.gz $out/lib/maper
  ln -s $out/lib/maper/{maper,launchlist-gen,run-maper-example.sh} $out/bin
''
