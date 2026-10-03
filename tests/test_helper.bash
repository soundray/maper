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
    export STUB_STATE_DIR="$BATS_TEST_TMPDIR"
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
    # optional columns of the description files
    for f in a1 a2 a3 ; do
        echo data > "$FX/$f-op.nii.gz" ; echo data > "$FX/$f-tc.nii.gz" ; echo data > "$FX/$f.dof.gz"
    done
    echo data > "$FX/t-op.nii.gz" ; echo data > "$FX/t-tc.nii.gz" ; echo data > "$FX/t.dof.gz"
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

# stub_calls <tool> [subcommand]: number of logged calls to a stubbed tool.
# (Assert with [ "$(stub_calls seg_EM)" -eq 0 ]; a negated "! grep" does not
# fail a bats test, because bash ignores a negated command for errexit.)
stub_calls() {
    grep -c "^$1${2:+ $2}\\( \\|\$\\)" "$STUB_LOG" || true
}

# --- launchlist-gen helpers -------------------------------------------------

# write_csv <name> <line>...: write $FX/<name> with the given lines
write_csv() {
    local f=$FX/$1 ; shift
    printf '%s\n' "$@" > "$f"
}

# Three atlases and one target, referring to the fixture images
default_csvs() {
    write_csv src.csv "id, mri, brainmask, seg" \
        "a1, a1-mri.nii.gz, a1-mask.nii.gz, a1-seg.nii.gz" \
        "a2, a2-mri.nii.gz, a2-mask.nii.gz, a2-seg.nii.gz" \
        "a3, a3-mri.nii.gz, a3-mask.nii.gz, a3-seg.nii.gz"
    write_csv tgt.csv "id, mri, brainmask" \
        "T1, t-mri.nii.gz, t-mask.nii.gz"
}

# run_llgen [extra launchlist-gen args...]: uses src.csv/tgt.csv from $FX
run_llgen() {
    LL="$BATS_TEST_TMPDIR/launchlist.sh"
    run "$LAUNCHLIST_GEN" -src-description "$FX/src.csv" -tgt-description "$FX/tgt.csv" \
        -output-dir "$OUT" -launchlist "$LL" "$@"
}

# ll_words <n>: split line n of the launchlist into WORDS, as the shell would
ll_words() {
    local line
    line=$(sed -n "${1}p" "$LL")
    eval "WORDS=($line)"
}

# ll_values <option>: the value following each occurrence of <option> in WORDS
ll_values() {
    local i
    for (( i = 0 ; i < ${#WORDS[@]} - 1 ; i++ )) ; do
        if [[ ${WORDS[i]} == "$1" ]] ; then printf '%s\n' "${WORDS[i+1]}" ; fi
    done
}

# ll_has <option>: is the (value-less) option present in WORDS?
ll_has() {
    local w
    for w in "${WORDS[@]}" ; do
        if [[ $w == "$1" ]] ; then return 0 ; fi
    done
    return 1
}

ll_count() { wc -l < "$LL" | tr -d ' ' ; }

# --- concurrency helpers ------------------------------------------------------

# wait_for <path> [tenths of a second]: wait until the path exists
wait_for() {
    local k
    for (( k = 0 ; k < ${2:-100} ; k++ )) ; do
        if [[ -e $1 ]] ; then return 0 ; fi
        sleep 0.1
    done
    return 1
}

# watch_until_exit <pid> <command...>: run the command every 0.05 s for as long as the
# process <pid> lives; its output, one line per sample, is what this prints
watch_until_exit() {
    local pid=$1 ; shift
    while kill -0 "$pid" 2>/dev/null ; do
        "$@"
        sleep 0.05
    done
}

# maper_pair <atlas-id> [extra maper args...]: command line for atlas <id> against T1
# in $OUT, for starting a job in the background
maper_pair() {
    local s=$1 ; shift
    build_args "$s"
    # shellcheck disable=SC2034  # the tests start the command with it
    MAPER_PAIR=("$MAPER" -srcid "$s" -tgtid T1 "${ARGS_NOID[@]}" "$@")
}
