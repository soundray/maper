# Shared setup for the bats tests.
#
# MIRTK and NiftySeg are replaced by stubs (tests/stubs) that are put first on
# PATH. The stubs log every call to $STUB_LOG, create the output files the real
# tools would create, and can be made to fail with STUB_FAIL=mirtk:register etc.
# The tests therefore exercise maper's control flow and argument handling, not
# image-processing results.

MAPER_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
MAPER="$MAPER_ROOT/maper"
LAUNCHLIST_GEN="$MAPER_ROOT/launchlist-gen"

setup_common() {
    export PATH="$BATS_TEST_DIRNAME/stubs:$PATH"
    export TMPDIR="$BATS_TEST_TMPDIR/tmp"
    export USER="${USER:-tester}"
    export STUB_LOG="$BATS_TEST_TMPDIR/stub.log"
    mkdir -p "$TMPDIR"
    : > "$STUB_LOG"

    FX="$BATS_TEST_TMPDIR/fixtures"
    OUT="$BATS_TEST_TMPDIR/out"
    mkdir -p "$FX"
    local f
    for f in a1 a2 a3 ; do
        for k in mri mask seg seg2 ; do echo data > "$FX/$f-$k.nii.gz" ; done
    done
    for f in t-mri t-mask t-ref t-ref2 ; do echo data > "$FX/$f.nii.gz" ; done
}

# Sets ARGS_NOID to a complete, valid maper command line for atlas $1 against
# target T1, without -srcid/-tgtid so that tests can leave them out.
build_args() {
    local s=${1:-a1}
    ARGS_NOID=(
        -srcmri "$FX/$s-mri.nii.gz" -srcmask "$FX/$s-mask.nii.gz"
        -tgtmri "$FX/t-mri.nii.gz" -tgtmask "$FX/t-mask.nii.gz"
        -srclabels "seg:$FX/$s-seg.nii.gz"
        -output-dir "$OUT"
    )
}

# run_maper <atlas-id> [extra maper args...]
run_maper() {
    local s=$1 ; shift
    build_args "$s"
    run "$MAPER" -srcid "$s" -tgtid T1 "${ARGS_NOID[@]}" "$@"
}
