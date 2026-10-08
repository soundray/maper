# Checks of the Nix packaging, run by `nix flake check` (see flake.nix and the "nix"
# job of .github/workflows/tests.yml).
#
# The package replaces PATH, in generic-functions, with a short list of store paths: a
# command that every Linux has but that is not on that list (awk, hostname, pgrep ...)
# is not there when maper runs from Nix. The checks therefore run the installed
# package, not the sources.
{ pkgs }:
let
  inherit (pkgs) lib;

  # MIRTK and NiftySeg are the stubs of the test suite (tests/stubs): they log the call and
  # create the output files that the real tools would. Everything else is the real package.
  stubs = ./stubs;
  stubPackage = name: tools: pkgs.runCommand name { } ''
    mkdir -p $out/bin
    for t in ${lib.escapeShellArgs tools} ; do
      install -m 755 ${stubs}/$t $out/bin/$t
    done
    patchShebangs $out/bin
  '';
  pkgsWithStubs = pkgs.extend (_final: _prev: {
    mirtk = stubPackage "mirtk-stub" [ "mirtk" ];
    niftyseg = stubPackage "niftyseg-stub" [ "seg_EM" "seg_LabFusion" "seg_maths" "seg_stats" ];
  });

  maper = import ../default.nix { inherit pkgs; };
  maperWithStubs = import ../default.nix { pkgs = pkgsWithStubs; };
in {
  # The package builds, and what it installs is complete and runnable
  package = pkgs.runCommand "maper-package-check" { } ''
    cd ${maper}/bin
    for c in maper launchlist-gen atlas-ancillaries.sh hammers-atlas-db-n30r120-ancillaries.sh \
             run-maper-example-generate.sh maper-canonicalize-nifti maper-reorient2std-nifti \
             maper-centre-origin-nifti ; do
      test -x "$c" || { echo "missing or not executable: bin/$c" >&2 ; exit 1 ; }
    done
    for f in maper launchlist-gen generic-functions neutral.dof.gz rightmask.nii.gz ; do
      test -s ${maper}/lib/maper/$f || { echo "missing: lib/maper/$f" >&2 ; exit 1 ; }
    done

    # nothing in bin starts a program that it looks for on PATH. (The Python scripts in
    # lib/maper are not called directly but by the wrappers, with the interpreter.)
    for c in * ; do
      f=$(readlink -f "$c")
      if ! head -n 1 "$f" | grep -q '^#! *'${lib.escapeShellArg builtins.storeDir}'/' ; then
        echo "bin/$c does not start with an interpreter from the store: $(head -n 1 "$f")" >&2 ; exit 1
      fi
    done

    # the Python scripts find their modules
    ./maper-canonicalize-nifti --help > /dev/null
    ./maper-reorient2std-nifti --help > /dev/null
    ./maper-centre-origin-nifti --help > /dev/null

    # the shell scripts start and answer a call without arguments with their usage text
    for c in maper launchlist-gen ; do
      if ./$c > $TMPDIR/$c.out 2>&1 ; then echo "$c without arguments should fail" >&2 ; exit 1 ; fi
      grep -q -i 'usage' $TMPDIR/$c.out || { echo "$c: no usage text" >&2 ; cat $TMPDIR/$c.out >&2 ; exit 1 ; }
    done
    touch $out
  '';

  # The scripts that prepare an atlas database, run as installed on a database of thirty
  # made-up atlases; the tarball of ancillaries is in place, so nothing is downloaded
  ancillaries = pkgs.runCommand "maper-ancillaries-check" { } ''
    export HOME=$TMPDIR USER=nix
    cd $TMPDIR
    mkdir payload ; mkdir payload/onepad ; echo onepad > payload/onepad/a1.nii.gz
    for n in $(seq 1 30) ; do
      nn=$(printf %02d $n)
      mkdir -p r95/Hammers-n30r95 r120/Hammers-n30r120/sub-$nn/anat
      echo "seg $n" > r95/Hammers-n30r95/a$nn-seg.nii.gz
      echo "seg $n" > r120/Hammers-n30r120/sub-$nn/anat/sub-''${nn}_space-orig_dseg.nii.gz
    done

    mkdir r95-out r120-out
    tar -cf r95-out/hammers_mith-ancillaries-n30r95.tar -C payload .
    tar -cf r120-out/hammers-atlas-db-n30r120-ancillaries.tar -C payload .
    ${maper}/bin/atlas-ancillaries.sh $PWD/r95 $PWD/r95-out > log-r95 2>&1 \
      || { cat log-r95 >&2 ; exit 1 ; }
    ${maper}/bin/hammers-atlas-db-n30r120-ancillaries.sh $PWD/r120 $PWD/r120-out > log-r120 2>&1 \
      || { cat log-r120 >&2 ; exit 1 ; }

    for d in r95-out/seg/seg95 r120-out/seg/seg120 ; do
      test "$(cat $d/a30.nii.gz)" = "seg 30" || { echo "no a30 in $d" >&2 ; exit 1 ; }
    done
    for d in r95-out r120-out ; do
      test -s $d/onepad/a1.nii.gz || { echo "$d: tarball not unpacked" >&2 ; exit 1 ; }
      test "$(wc -l < $d/src-description.csv)" -eq 31 || { echo "$d: description file" >&2 ; exit 1 ; }
    done
    touch $out
  '';

  # A target segmented from three atlases with the installed maper, MIRTK and NiftySeg
  # being stubs: registration flow, label fusion under the lock, all of it with the PATH
  # that the package gives. The fusion happens when the third job is done.
  pipeline = pkgs.runCommand "maper-pipeline-check" { } ''
    export HOME=$TMPDIR USER=nix
    fx=$TMPDIR/fixtures res=$TMPDIR/results
    mkdir -p $fx
    for s in a1 a2 a3 ; do
      for k in mri mask seg ; do echo data > $fx/$s-$k.nii.gz ; done
    done
    for k in mri mask ; do echo data > $fx/target-$k.nii.gz ; done

    for s in a1 a2 a3 ; do
      ${maperWithStubs}/bin/maper -srcid $s -tgtid T1 \
        -srcmri $fx/$s-mri.nii.gz -srcmask $fx/$s-mask.nii.gz \
        -tgtmri $fx/target-mri.nii.gz -tgtmask $fx/target-mask.nii.gz \
        -srclabels seg:$fx/$s-seg.nii.gz -output-dir $res -atlasn 3 > log-$s 2>&1 \
        || { echo "maper failed for $s:" >&2 ; cat log-$s >&2 ; exit 1 ; }
    done

    for s in a1 a2 a3 ; do test -s $res/T1/$s-T1/seg/seg.nii.gz || { echo "no result of $s" >&2 ; exit 1 ; } ; done
    test -s $res/f3-seg-T1.nii.gz || { echo "no fusion" >&2 ; cat log-a3 >&2 ; exit 1 ; }
    left=$(ls -A $res | grep -E 'fusion-|\.tmp' || true)
    test -z "$left" || { echo "left behind: $left" >&2 ; exit 1 ; }
    touch $out
  '';
}
