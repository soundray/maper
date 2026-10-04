{
  # nixpkgs to use when none is given: the revision that flake.lock pins, so that
  # nix-build and `nix build` use the same one (`nix flake update` moves both)
  pkgsPath ? let
    lock = builtins.fromJSON (builtins.readFile ./flake.lock);
    locked = lock.nodes.${lock.nodes.root.inputs.nixpkgs}.locked;
  in builtins.fetchTarball {
    url = "https://github.com/${locked.owner}/${locked.repo}/archive/${locked.rev}.tar.gz";
    sha256 = locked.narHash;
  }
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
  cp ${src}/{maper,launchlist-gen,run-maper-example-generate.sh,generic-functions,atlas-ancillaries.sh,hammers-atlas-db-n30r120-ancillaries.sh,canonicalize-nifti.py,reorient2std-nifti.py} $out/lib/maper
  chmod u+w $out/lib/maper/generic-functions
  echo "export PATH='${binpath}'" >>$out/lib/maper/generic-functions
  sed -i "s^##nix-path-goes-here##^source $out/lib/maper/generic-functions^" $out/lib/maper/run-maper-example-generate.sh
  for f in $out/lib/maper/* ; do patchShebangs $f ; done
  cp ${src}/neutral.dof.gz ${src}/rightmask.nii.gz $out/lib/maper
  ln -s $out/lib/maper/{maper,launchlist-gen,run-maper-example-generate.sh,atlas-ancillaries.sh,hammers-atlas-db-n30r120-ancillaries.sh} $out/bin
  makeWrapper ${pythonEnv}/bin/python "$out/bin/maper-canonicalize-nifti" \
    --add-flags "$out/lib/maper/canonicalize-nifti.py"
  makeWrapper ${pythonEnv}/bin/python "$out/bin/maper-reorient2std-nifti" \
    --add-flags "$out/lib/maper/reorient2std-nifti.py"
''
