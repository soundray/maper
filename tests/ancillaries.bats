#!/usr/bin/env bats
# The two scripts that prepare the ancillaries of an atlas database for MAPER.
# The ancillaries tarball is put in place beforehand, so that nothing is downloaded,
# except by the tests that are about the download (wget is a stub).

load test_helper

setup() { setup_common ; }

# A database with 30 atlases in the layout of <set>, and an ancillaries directory.
# Their paths contain a space, unless $PLAIN is set.
#   habad95:      <atlasdb>/HABAD-n30r95/aNN-seg.nii.gz
#   hammers120:   <atlasdb>/Hammers-n30r120/sub-NN/anat/sub-NN_space-orig_dseg.nii.gz
make_database() { # <set> <tarball name>
    if [[ -n ${PLAIN:-} ]] ; then
        ATLASDB="$BATS_TEST_TMPDIR/atlasdb" ANCILL="$BATS_TEST_TMPDIR/ancillaries"
    else
        ATLASDB="$BATS_TEST_TMPDIR/atlas db" ANCILL="$BATS_TEST_TMPDIR/ancillaries dir"
    fi
    mkdir -p "$ATLASDB" "$ANCILL" "$BATS_TEST_TMPDIR/payload/onepad"
    local a aa
    for a in {1..30} ; do
        aa=$(printf '%02d' "$a")
        case $1 in
            habad95)
                mkdir -p "$ATLASDB/HABAD-n30r95"
                echo "seg $a" > "$ATLASDB/HABAD-n30r95/a$aa-seg.nii.gz" ;;
            hammers120)
                mkdir -p "$ATLASDB/Hammers-n30r120/sub-$aa/anat"
                echo "seg $a" > "$ATLASDB/Hammers-n30r120/sub-$aa/anat/sub-${aa}_space-orig_dseg.nii.gz" ;;
        esac
    done
    echo onepad > "$BATS_TEST_TMPDIR/payload/onepad/a1.nii.gz"
    tar -cf "$BATS_TEST_TMPDIR/$2.tar" -C "$BATS_TEST_TMPDIR/payload" .
}

@test "atlas-ancillaries.sh prepares the ancillaries; the paths contain spaces" {
    make_database habad95 hammers_mith-ancillaries-n30r95
    cp "$BATS_TEST_TMPDIR/hammers_mith-ancillaries-n30r95.tar" "$ANCILL"/
    run "$MAPER_ROOT/atlas-ancillaries.sh" "$ATLASDB" "$ANCILL"
    [ "$status" -eq 0 ]
    [ "$(< "$ANCILL/seg/seg95/a1.nii.gz")" = "seg 1" ]
    [ "$(< "$ANCILL/seg/seg95/a30.nii.gz")" = "seg 30" ]
    [ -s "$ANCILL/onepad/a1.nii.gz" ]                  # unpacked from the tarball ...
    [ ! -e "$ANCILL/hammers_mith-ancillaries-n30r95.tar" ]    # ... which is gone again
    [ "$(wc -l < "$ANCILL/src-description.csv")" -eq 31 ]
    grep -q '^a30, onepad/a30.nii.gz, posnorm/a30.dof.gz, seg/seg95/a30.nii.gz$' "$ANCILL/src-description.csv"
}

@test "hammers-atlas-db-n30r120-ancillaries.sh prepares the ancillaries; the paths contain spaces" {
    make_database hammers120 hammers-atlas-db-n30r120-ancillaries
    cp "$BATS_TEST_TMPDIR/hammers-atlas-db-n30r120-ancillaries.tar" "$ANCILL"/
    run "$MAPER_ROOT/hammers-atlas-db-n30r120-ancillaries.sh" "$ATLASDB" "$ANCILL"
    [ "$status" -eq 0 ]
    [ "$(< "$ANCILL/seg/seg120/a1.nii.gz")" = "seg 1" ]
    [ "$(< "$ANCILL/seg/seg120/a30.nii.gz")" = "seg 30" ]
    [ -s "$ANCILL/onepad/a1.nii.gz" ]
    [ ! -e "$ANCILL/hammers-atlas-db-n30r120-ancillaries.tar" ]
    [ "$(wc -l < "$ANCILL/src-description.csv")" -eq 31 ]
    grep -q '^a30, onepad/a30.nii.gz, posnorm/a30.dof.gz, seg/seg120/a30.nii.gz$' "$ANCILL/src-description.csv"
}

@test "atlas-ancillaries.sh downloads the tarball with wget when it is not there" {
    PLAIN=1 make_database habad95 hammers_mith-ancillaries-n30r95
    export STUB_WGET_FILE="$BATS_TEST_TMPDIR/hammers_mith-ancillaries-n30r95.tar"
    run "$MAPER_ROOT/atlas-ancillaries.sh" "$ATLASDB" "$ANCILL"
    [ "$status" -eq 0 ]
    [ "$(< "$STUB_LOG.args")" = "wget [-O] [-] [https://soundray.org/maper/hammers_mith-ancillaries-n30r95.tar]" ]
    [ -s "$ANCILL/onepad/a1.nii.gz" ]
    [ -s "$ANCILL/src-description.csv" ]
}

@test "hammers-atlas-db-n30r120-ancillaries.sh downloads the tarball with wget when it is not there" {
    PLAIN=1 make_database hammers120 hammers-atlas-db-n30r120-ancillaries
    export STUB_WGET_FILE="$BATS_TEST_TMPDIR/hammers-atlas-db-n30r120-ancillaries.tar"
    run "$MAPER_ROOT/hammers-atlas-db-n30r120-ancillaries.sh" "$ATLASDB" "$ANCILL"
    [ "$status" -eq 0 ]
    [ "$(< "$STUB_LOG.args")" = "wget [-O] [-] [https://soundray.org/maper/hammers-atlas-db-n30r120-ancillaries.tar]" ]
    [ -s "$ANCILL/onepad/a1.nii.gz" ]
}
