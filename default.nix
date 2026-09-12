{
  # nixos-19.09 as of 2019-12-29
  pkgsPath ? builtins.fetchTarball https://github.com/nixos/nixpkgs/archive/eab4ee0c27c5c6f622aa0ca55091c394a9e33edd.tar.gz
  # nixpkgs to use
, pkgs ? import pkgsPath {}
}:
let
  inherit (pkgs) lib;
  pythonEnv = pkgs.python3.withPackages (ps: [
    ps.nibabel
    ps.numpy
  ]);
  src = lib.cleanSource ./.;
  binpath = pkgs.lib.concatStringsSep ":" [
    "$out/bin" # sample needs maper on PATH
    "${pkgs.mirtk}/bin"
    "${pkgs.niftyseg}/bin"
    "${pkgs.coreutils}/bin" # For date
    "${pkgs.curl}/bin" # For example script to download sample data
    "${pkgs.gnutar}/bin" # For example script to unpack sample data
    "${pkgs.findutils}/bin" # For xargs
    "${pkgs.gnugrep}/bin"
    "${pkgs.gnused}/bin"
    "${pkgs.bc}/bin"
    "${pkgs.util-linux}/bin"
  ];
in pkgs.runCommand "maper" {
  nativeBuildInputs = [ pkgs.makeWrapper ];
  meta = {
    license = lib.licenses.gpl2;
    description = "Multi-atlas propagation with enhanced registration";
    homepage = https://soundray.org/maper/;
  };
} ''
  mkdir -p $out/bin $out/lib/maper
  cp ${src}/{maper,launchlist-gen,run-maper-example-generate.sh,generic-functions,hammers_mith-ancillaries.sh,canonicalize-nifti.py,reorient2std-nifti.py} $out/lib/maper
  chmod u+w $out/lib/maper/generic-functions
  echo "export PATH='${binpath}'" >>$out/lib/maper/generic-functions
  sed -i "s^##nix-path-goes-here##^source $out/lib/maper/generic-functions^" $out/lib/maper/run-maper-example-generate.sh
  for f in $out/lib/maper/* ; do patchShebangs $f ; done
  cp ${src}/neutral.dof.gz ${src}/rightmask.nii.gz $out/lib/maper
  ln -s $out/lib/maper/{maper,launchlist-gen,run-maper-example-generate.sh,hammers_mith-ancillaries.sh} $out/bin
  makeWrapper ${pythonEnv}/bin/python "$out/bin/maper-canonicalize-nifti" \
    --add-flags "$out/lib/maper/canonicalize-nifti.py"
  makeWrapper ${pythonEnv}/bin/python "$out/bin/maper-reorient2std-nifti" \
    --add-flags "$out/lib/maper/reorient2std-nifti.py"
''
