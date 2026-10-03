#!/usr/bin/env bats

load test_helper

setup() { setup_common ; }

@test "single pair: succeeds and writes transformation and propagated labels" {
    run_maper a1
    [ "$status" -eq 0 ]
    [ -s "$OUT/T1/a1-T1/src-tgt.dof.gz" ]
    [ -s "$OUT/T1/a1-T1/seg/seg.nii.gz" ]
}

@test "fusion: runs when the third atlas result arrives" {
    for s in a1 a2 a3 ; do
        run_maper "$s" -atlasn 3
        [ "$status" -eq 0 ]
    done
    [ -s "$OUT/f3-seg-T1.nii.gz" ]
}

@test "fusion: does not run before -atlasn results exist" {
    for s in a1 a2 ; do
        run_maper "$s" -atlasn 3
        [ "$status" -eq 0 ]
    done
    [ ! -e "$OUT/f3-seg-T1.nii.gz" ]
}

@test "input without any image specification is rejected" {
    run "$MAPER" -srcid a1 -tgtid T1 -srclabels "seg:$FX/a1-seg.nii.gz" \
        -tgtmri "$FX/t-mri.nii.gz" -tgtmask "$FX/t-mask.nii.gz" -output-dir "$OUT"
    [ "$status" -ne 0 ]
    [[ $output == *"Source specification incomplete"* ]]
}

# --- failures must not be swallowed ---------------------------------------

@test "registration failure: maper exits non-zero and writes no results" {
    export STUB_FAIL=mirtk:register
    run_maper a1
    [ "$status" -ne 0 ]
    [[ $output == *"Registration and propagation failed"* ]]
    [ ! -e "$OUT/T1/a1-T1/src-tgt.dof.gz" ]
}

@test "label propagation failure: maper exits non-zero" {
    # -notc keeps tc3() (which also calls transform-image) out of the picture,
    # so the failing call is the one in regprop's label propagation.
    export STUB_FAIL=mirtk:transform-image
    run_maper a1 -notc
    [ "$status" -ne 0 ]
    [[ $output == *"Registration and propagation failed"* ]]
}

@test "onepad generation failure for the source: maper exits non-zero" {
    # -srcmri + -srcmask without -srcop: onepad is derived with mirtk dilate-image
    export STUB_FAIL=mirtk:dilate-image
    run_maper a1
    [ "$status" -ne 0 ]
    [[ $output == *"forced failure of mirtk dilate-image"* ]]
    [ ! -e "$OUT/T1/a1-T1/src-tgt.dof.gz" ]
}

@test "onepad generation failure for the target: maper exits non-zero" {
    # Only the target needs dilation here: the source is given as -srcop.
    echo data > "$FX/a1-op.nii.gz"
    export STUB_FAIL=mirtk:dilate-image
    run "$MAPER" -srcid a1 -tgtid T1 -srcop "$FX/a1-op.nii.gz" \
        -srclabels "seg:$FX/a1-seg.nii.gz" \
        -tgtmri "$FX/t-mri.nii.gz" -tgtmask "$FX/t-mask.nii.gz" -output-dir "$OUT"
    [ "$status" -ne 0 ]
    [ ! -e "$OUT/T1/a1-T1/src-tgt.dof.gz" ]
}

@test "mask without image or onepad: reports an incomplete source specification" {
    run "$MAPER" -srcid a1 -tgtid T1 -srcmask "$FX/a1-mask.nii.gz" \
        -srclabels "seg:$FX/a1-seg.nii.gz" \
        -tgtmri "$FX/t-mri.nii.gz" -tgtmask "$FX/t-mask.nii.gz" -output-dir "$OUT"
    [ "$status" -ne 0 ]
    [[ $output == *"Source specification incomplete"* ]]
}

@test "target given only as a mask: reports an incomplete target specification" {
    run "$MAPER" -srcid a1 -tgtid T1 -srcmri "$FX/a1-mri.nii.gz" -srcmask "$FX/a1-mask.nii.gz" \
        -srclabels "seg:$FX/a1-seg.nii.gz" \
        -tgtmask "$FX/t-mask.nii.gz" -output-dir "$OUT"
    [ "$status" -ne 0 ]
    [[ $output == *"Target specification incomplete"* ]]
}

# --- overlap assessment and fusion ----------------------------------------

@test "target reference: per-pair overlap files are written" {
    run_maper a1 -tgtlabels "seg:$FX/t-ref.nii.gz"
    [ "$status" -eq 0 ]
    [ -s "$OUT/T1/a1-T1/seg/seg-jc.csv" ]
    [ -s "$OUT/T1/a1-T1/seg/seg-meanjc.csv" ]
}

@test "fusion with two label sets and references: every job succeeds and both sets are fused and assessed" {
    for s in a1 a2 a3 ; do
        run_maper "$s" -atlasn 3 \
            -srclabels "segB:$FX/$s-seg2.nii.gz" \
            -tgtlabels "seg:$FX/t-ref.nii.gz" -tgtlabels "segB:$FX/t-ref2.nii.gz"
        [ "$status" -eq 0 ]
    done
    local set
    for set in seg segB ; do
        [ -s "$OUT/f3-$set-T1.nii.gz" ]
        [ -s "$OUT/f3-$set-T1-tc3crisp.nii.gz" ]
        [ -s "$OUT/f3-$set-T1-meanjc.csv" ]
        [ -s "$OUT/f3-$set-T1-indivjc.csv" ]
    done
}

@test "fusion failure: maper exits non-zero and leaves no stale lock behind" {
    for s in a1 a2 ; do
        run_maper "$s" -atlasn 3
        [ "$status" -eq 0 ]
    done
    export STUB_FAIL=seg_LabFusion
    run_maper a3 -atlasn 3
    [ "$status" -ne 0 ]
    run bash -c 'ls -d "$1"/fusion-semaphore-* 2>/dev/null' _ "$OUT"
    [ -z "$output" ]
}

@test "fusion failure: a later run can fuse once the problem is fixed" {
    for s in a1 a2 ; do
        run_maper "$s" -atlasn 3
        [ "$status" -eq 0 ]
    done
    export STUB_FAIL=seg_LabFusion
    run_maper a3 -atlasn 3
    [ "$status" -ne 0 ]
    unset STUB_FAIL
    # a3's own registration results are already in place, so this only fuses
    run_maper a3 -atlasn 3
    [ "$status" -eq 0 ]
    [ -s "$OUT/f3-seg-T1.nii.gz" ]
}

# --- argument validation --------------------------------------------------

@test "-h prints the usage text and exits 0" {
    run "$MAPER" -h
    [ "$status" -eq 0 ]
    [[ $output == *"Usage:"* ]]
}

@test "--help prints the usage text and exits 0" {
    run "$MAPER" --help
    [ "$status" -eq 0 ]
    [[ $output == *"Usage:"* ]]
}

@test "usage documents -threads" {
    run "$MAPER" -h
    [[ $output == *"-threads"* ]]
}

@test "no arguments: fails and says what is required" {
    run "$MAPER"
    [ "$status" -ne 0 ]
    [[ $output == *"-srcid is required"* ]]
}

@test "missing -srcid is rejected before anything is written" {
    build_args a1
    run "$MAPER" -tgtid T1 "${ARGS_NOID[@]}"
    [ "$status" -ne 0 ]
    [[ $output == *"-srcid is required"* ]]
    [ ! -e "$OUT" ]
}

@test "missing -tgtid is rejected before anything is written" {
    build_args a1
    run "$MAPER" -srcid a1 "${ARGS_NOID[@]}"
    [ "$status" -ne 0 ]
    [[ $output == *"-tgtid is required"* ]]
    [ ! -e "$OUT" ]
}

@test "unknown option is rejected and named" {
    run_maper a1 -bogus
    [ "$status" -ne 0 ]
    [[ $output == *"Unknown option: -bogus"* ]]
}

@test "stray positional argument is rejected instead of silently ending option parsing" {
    run_maper a1 stray -quicktest
    [ "$status" -ne 0 ]
    [[ $output == *"Unexpected argument: stray"* ]]
}

@test "option without a value is reported by name" {
    build_args a1
    run "$MAPER" -tgtid T1 "${ARGS_NOID[@]}" -srcid
    [ "$status" -ne 0 ]
    [[ $output == *"-srcid requires a value"* ]]
}

@test "missing source label file is fatal" {
    run_maper a1 -srclabels "segB:$FX/MISSING.nii.gz"
    [ "$status" -ne 0 ]
    [[ $output == *"does not exist"*"MISSING.nii.gz"* ]]
    [ ! -e "$OUT/T1/a1-T1/src-tgt.dof.gz" ]
}

@test "missing target label file is fatal" {
    run_maper a1 -tgtlabels "seg:$FX/MISSING-ref.nii.gz"
    [ "$status" -ne 0 ]
    [[ $output == *"does not exist"*"MISSING-ref.nii.gz"* ]]
}

@test "source label spec without name:file form is rejected" {
    run_maper a1 -srclabels "justafilename.nii.gz"
    [ "$status" -ne 0 ]
    [[ $output == *"-srclabels expects name:file"* ]]
}

@test "target label spec without name:file form is rejected" {
    run_maper a1 -tgtlabels "justafilename.nii.gz"
    [ "$status" -ne 0 ]
    [[ $output == *"-tgtlabels expects name:file"* ]]
}

@test "label file path containing spaces works" {
    mkdir "$FX/dir with space"
    echo data > "$FX/dir with space/extra seg.nii.gz"
    run_maper a1 -srclabels "spaced:$FX/dir with space/extra seg.nii.gz"
    [ "$status" -eq 0 ]
    [ -s "$OUT/T1/a1-T1/seg/spaced.nii.gz" ]
}

@test "missing input image is reported with the option name and path" {
    run_maper a1 -tgtmri "$FX/no-such-image.nii.gz"
    [ "$status" -ne 0 ]
    [[ $output == *"-tgtmri"*"no-such-image.nii.gz"* ]]
}

@test "input image in a directory that does not exist is reported by option name" {
    run_maper a1 -srcmri /no/such/dir/image.nii.gz
    [ "$status" -ne 0 ]
    [[ $output == *"-srcmri"*"/no/such/dir/image.nii.gz"* ]]
}

@test "pretransformation file that does not exist is reported" {
    run_maper a1 -spn "$FX/no-such.dof.gz" -tpn "$FX/no-such.dof.gz"
    [ "$status" -ne 0 ]
    [[ $output == *"-spn"* ]]
}

@test "-threads must be a positive integer" {
    local bad
    for bad in abc 0 -3 1x "" ; do
        run_maper a1 -threads "$bad"
        [ "$status" -ne 0 ]
        [[ $output == *"-threads"* ]]
    done
}

@test "-threads accepts a positive integer" {
    run_maper a1 -threads 2
    [ "$status" -eq 0 ]
}

@test "-atlasn must be a number" {
    run_maper a1 -atlasn many
    [ "$status" -ne 0 ]
    [[ $output == *"-atlasn"* ]]
}

@test "-tc2 and -tc3 are mutually exclusive" {
    run_maper a1 -tc2 -tc3
    [ "$status" -ne 0 ]
    [[ $output == *"only one of -tc2 and -tc3"* ]]
}

@test "-notc is incompatible with the tc3 output options" {
    run_maper a1 -notc -tc3out
    [ "$status" -ne 0 ]
    [[ $output == *"-notc"*"incompatible"* ]]
}

# --- -tc3only and the tissue-class caches ----------------------------------

@test "-tc3only: stops after tissue classification, without registration" {
    run_maper a1 -tc3only
    [ "$status" -eq 0 ]
    [ "$(stub_calls mirtk register)" -eq 0 ]
    [ ! -e "$OUT/T1/a1-T1/src-tgt.dof.gz" ]
}

@test "-tc3only: populates the source and target caches" {
    run_maper a1 -tc3only -srccache "$BATS_TEST_TMPDIR/csrc" -tgtcache "$BATS_TEST_TMPDIR/ctgt"
    [ "$status" -eq 0 ]
    [ -s "$BATS_TEST_TMPDIR/csrc/a1/csf.nii.gz" ]
    [ -s "$BATS_TEST_TMPDIR/csrc/a1/tc3raw.nii.gz" ]
    [ -s "$BATS_TEST_TMPDIR/ctgt/T1/crisp.nii.gz" ]
}

@test "-tc3only: caches hold the same files as after a full run" {
    run_maper a1 -tc3only -srccache "$BATS_TEST_TMPDIR/only-s" -tgtcache "$BATS_TEST_TMPDIR/only-t"
    [ "$status" -eq 0 ]
    run_maper a1 -output-dir "$BATS_TEST_TMPDIR/out-full" \
        -srccache "$BATS_TEST_TMPDIR/full-s" -tgtcache "$BATS_TEST_TMPDIR/full-t"
    [ "$status" -eq 0 ]
    [ -n "$(ls "$BATS_TEST_TMPDIR/full-s/a1")" ]
    diff <(ls "$BATS_TEST_TMPDIR/only-s/a1") <(ls "$BATS_TEST_TMPDIR/full-s/a1")
    diff <(ls "$BATS_TEST_TMPDIR/only-t/T1") <(ls "$BATS_TEST_TMPDIR/full-t/T1")
}

@test "-tc3only: a later full run reuses the cached tissue classes" {
    run_maper a1 -tc3only -srccache "$BATS_TEST_TMPDIR/csrc" -tgtcache "$BATS_TEST_TMPDIR/ctgt"
    [ "$status" -eq 0 ]
    : > "$STUB_LOG"
    run_maper a1 -srccache "$BATS_TEST_TMPDIR/csrc" -tgtcache "$BATS_TEST_TMPDIR/ctgt"
    [ "$status" -eq 0 ]
    [ "$(stub_calls seg_EM)" -eq 0 ]
    [ -s "$OUT/T1/a1-T1/src-tgt.dof.gz" ]
}

@test "full run: fills the caches and the next run reuses them" {
    run_maper a1 -srccache "$BATS_TEST_TMPDIR/csrc" -tgtcache "$BATS_TEST_TMPDIR/ctgt"
    [ "$status" -eq 0 ]
    [ "$(stub_calls seg_EM)" -gt 0 ]
    : > "$STUB_LOG"
    run_maper a1 -output-dir "$BATS_TEST_TMPDIR/out2" \
        -srccache "$BATS_TEST_TMPDIR/csrc" -tgtcache "$BATS_TEST_TMPDIR/ctgt"
    [ "$status" -eq 0 ]
    [ "$(stub_calls seg_EM)" -eq 0 ]
}

# --- -dry-run -----------------------------------------------------------------

@test "dry run: still rejects an incomplete specification" {
    run "$MAPER" -dry-run -srcid a1 -tgtid T1 -srcmask "$FX/a1-mask.nii.gz" \
        -srclabels "seg:$FX/a1-seg.nii.gz" \
        -tgtmri "$FX/t-mri.nii.gz" -tgtmask "$FX/t-mask.nii.gz" -output-dir "$OUT"
    [ "$status" -ne 0 ]
    [[ $output == *"Source specification incomplete"* ]]
}

@test "dry run: runs no registration" {
    run_maper a1 -dry-run
    [ "$status" -eq 0 ]
    [ "$(stub_calls mirtk register)" -eq 0 ]
}

@test "dry run: writes no files to the output directory" {
    run_maper a1 -dry-run
    [ "$status" -eq 0 ]
    [ -z "$(find "$OUT" -type f)" ]
}

@test "dry run: -tc3out and -tc3crisp do not write placeholder maps" {
    run_maper a1 -dry-run -tc3out -tc3crisp
    [ "$status" -eq 0 ]
    [ -z "$(find "$OUT" -type f)" ]
}

@test "dry run: -debug still saves the working directory, but no results" {
    run_maper a1 -dry-run -debug
    [ "$status" -eq 0 ]
    [ -n "$(find "$OUT/T1/a1-T1" -mindepth 1 -maxdepth 1 -type d -name 'maper.*')" ]
    [ ! -e "$OUT/T1/a1-T1/src-tgt.dof.gz" ]
    [ ! -e "$OUT/T1/a1-T1/seg/seg.nii.gz" ]
}

@test "dry run: does not write to the caches" {
    run_maper a1 -dry-run -srccache "$BATS_TEST_TMPDIR/csrc" -tgtcache "$BATS_TEST_TMPDIR/ctgt"
    [ "$status" -eq 0 ]
    [ -z "$(find "$BATS_TEST_TMPDIR/csrc" "$BATS_TEST_TMPDIR/ctgt" -type f)" ]
}

@test "dry run followed by a real run: the real run does the work" {
    run_maper a1 -dry-run
    [ "$status" -eq 0 ]
    : > "$STUB_LOG"
    run_maper a1
    [ "$status" -eq 0 ]
    [ "$(stub_calls mirtk register)" -gt 0 ]
    [ -s "$OUT/T1/a1-T1/src-tgt.dof.gz" ]
    [ -s "$OUT/T1/a1-T1/seg/seg.nii.gz" ]
}

@test "empty results left by an earlier dry run are recomputed, not trusted" {
    mkdir -p "$OUT/T1/a1-T1/seg"
    : > "$OUT/T1/a1-T1/src-tgt.dof.gz"
    : > "$OUT/T1/a1-T1/seg/seg.nii.gz"
    run_maper a1
    [ "$status" -eq 0 ]
    [ "$(stub_calls mirtk register)" -gt 0 ]
    [ -s "$OUT/T1/a1-T1/src-tgt.dof.gz" ]
    [ -s "$OUT/T1/a1-T1/seg/seg.nii.gz" ]
}

@test "dry run with -atlasn: fuses existing results, and writes nothing derived from placeholders" {
    for s in a1 a2 a3 ; do
        run_maper "$s" -atlasn 4      # three results, four wanted: no fusion yet
        [ "$status" -eq 0 ]
    done
    [ ! -e "$OUT/f3-seg-T1.nii.gz" ]
    run_maper a1 -dry-run -atlasn 3 -tgtlabels "seg:$FX/t-ref.nii.gz"
    [ "$status" -eq 0 ]
    [ -s "$OUT/f3-seg-T1.nii.gz" ]
    [ -z "$(find "$OUT" -type f -empty)" ]
    # tissue-class based output would be derived from placeholder maps
    [ ! -e "$OUT/f3-seg-T1-tc3crisp.nii.gz" ]
    [ -z "$(ls "$OUT" | grep tcsep)" ]
    # the overlap with the reference needs no tissue maps
    [ -s "$OUT/f3-seg-T1-meanjc.csv" ]
}

# --- directories whose names contain spaces ----------------------------------------

@test "output directory with spaces: a re-run over existing results works" {
    OUT="$BATS_TEST_TMPDIR/out dir with space"
    run_maper a1
    [ "$status" -eq 0 ]
    [ -s "$OUT/T1/a1-T1/src-tgt.dof.gz" ]
    : > "$STUB_LOG"
    run_maper a1
    [ "$status" -eq 0 ]
    # the existing results were found and reused, not recomputed
    [ "$(stub_calls mirtk register)" -eq 0 ]
    [ -s "$OUT/T1/a1-T1/seg/seg.nii.gz" ]
}

@test "output directory with spaces: the fused result is written where it belongs" {
    OUT="$BATS_TEST_TMPDIR/out dir with space"
    local s
    for s in a1 a2 a3 ; do
        run_maper "$s" -atlasn 3
        [ "$status" -eq 0 ]
    done
    [ -s "$OUT/f3-seg-T1.nii.gz" ]
    # and nothing was written to the path as split at the spaces
    [ ! -e "$BATS_TEST_TMPDIR/out" ]
    [ "$(grep -c -- '-out ' "$STUB_LOG")" -ge 1 ]
    grep -q -- "-out $OUT/f3-seg-T1.nii.gz\$" "$STUB_LOG"
}

@test "cache directories with spaces are created, filled and reused" {
    local c="$BATS_TEST_TMPDIR/cache dir"
    mkdir "$c"
    run_maper a1 -srccache "$c/src" -tgtcache "$c/tgt"
    [ "$status" -eq 0 ]
    [ -s "$c/src/a1/csf.nii.gz" ]
    [ -s "$c/tgt/T1/csf.nii.gz" ]
    : > "$STUB_LOG"
    run_maper a1 -output-dir "$BATS_TEST_TMPDIR/out2" -srccache "$c/src" -tgtcache "$c/tgt"
    [ "$status" -eq 0 ]
    [ "$(stub_calls seg_EM)" -eq 0 ]
}
