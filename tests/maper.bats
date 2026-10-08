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

# --- Jaccard values derived from the Dice values of seg_stats ----------------------

jc_files() {
    JC_INDIV="$OUT/T1/a1-T1/seg/seg-jc.csv"
    JC_MEAN="$OUT/T1/a1-T1/seg/seg-meanjc.csv"
}

@test "overlap with a reference: individual and mean Jaccard files have a fixed format" {
    run_maper a1 -tgtlabels "seg:$FX/t-ref.nii.gz"
    [ "$status" -eq 0 ]
    jc_files
    # Dice 0.8, 0.7 and a mean of 0.75: J = D / (2 - D), six decimals, bc's formatting
    [ "$(cat "$JC_INDIV")" = $'region,jc\n1, .666666\n2, .538461' ]
    [ "$(cat "$JC_MEAN")" = ".600000" ]
}

@test "Jaccard of Dice values 1 and 0 and of values in plain decimal notation" {
    export STUB_SEG_STATS_OUT='L[1] = 1\nL[2] = 0\nL[3] = 0.000001\nL[4] = .5\nM = 1\n'
    run_maper a1 -tgtlabels "seg:$FX/t-ref.nii.gz"
    [ "$status" -eq 0 ]
    jc_files
    [ "$(cat "$JC_INDIV")" = $'region,jc\n1, 1.000000\n2, 0\n3, 0\n4, .333333' ]
    [ "$(cat "$JC_MEAN")" = "1.000000" ]
}

@test "Dice in scientific notation gives the right Jaccard, not a value above 1" {
    export STUB_SEG_STATS_OUT='L[1] = 1.5e-05\nL[2] = 1E-05\nL[3] = 5e-01\nL[4] = 1.0e+00\nM = 2.5e-1\n'
    run_maper a1 -tgtlabels "seg:$FX/t-ref.nii.gz"
    [ "$status" -eq 0 ]
    jc_files
    # 1.5e-05/(2-1.5e-05) = 7.5e-06, 1e-05/(2-1e-05) = 5e-06, .5/1.5, 1/1; bc truncates at six decimals
    [ "$(cat "$JC_INDIV")" = $'region,jc\n1, .000007\n2, .000005\n3, .333333\n4, 1.000000' ]
    # the mean line: .25/1.75
    [ "$(cat "$JC_MEAN")" = ".142857" ]
}

@test "label numbers with several digits and extra spaces around the = are read" {
    export STUB_SEG_STATS_OUT='L[12]  =  0.5\nL[103]=0.25\nM = 0.5\n'
    run_maper a1 -tgtlabels "seg:$FX/t-ref.nii.gz"
    [ "$status" -eq 0 ]
    jc_files
    [ "$(cat "$JC_INDIV")" = $'region,jc\n12, .333333\n103, .142857' ]
}

@test "a Dice value that is not a number gives NA and a warning, never a made-up number" {
    export STUB_SEG_STATS_OUT='L[1] = nan\nL[2] = 0.5\nL[3] = 1.5\nL[4] = -0.2\nM = inf\n'
    run_maper a1 -tgtlabels "seg:$FX/t-ref.nii.gz"
    [ "$status" -eq 0 ]
    jc_files
    [ "$(cat "$JC_INDIV")" = $'region,jc\n1, NA\n2, .333333\n3, NA\n4, NA' ]
    [ "$(cat "$JC_MEAN")" = "NA" ]
    [[ $output == *"Warning"*"nan"* ]]
}

@test "seg_stats output without a mean line gives NA for the mean" {
    export STUB_SEG_STATS_OUT='L[1] = 0.5\n'
    run_maper a1 -tgtlabels "seg:$FX/t-ref.nii.gz"
    [ "$status" -eq 0 ]
    jc_files
    [ "$(cat "$JC_INDIV")" = $'region,jc\n1, .333333' ]
    [ "$(cat "$JC_MEAN")" = "NA" ]
}

@test "fused result is assessed with the same conversion" {
    export STUB_DICE=1e-05
    local s
    for s in a1 a2 a3 ; do
        run_maper "$s" -atlasn 3 -tgtlabels "seg:$FX/t-ref.nii.gz"
        [ "$status" -eq 0 ]
    done
    [ "$(sed -n 2p "$OUT/f3-seg-T1-indivjc.csv")" = "1, .000005" ]
}

@test "plain decimals are used exactly as written, with no rounding before the conversion" {
    # D = 0.666666666666666 gives J just below 0.5. Rounding D to twelve decimals
    # first would push J just above 0.5 and change the sixth decimal (.499999 vs .500000).
    export STUB_SEG_STATS_OUT='L[1] = 0.666666666666666\nM = 0.666666666666666\n'
    run_maper a1 -tgtlabels "seg:$FX/t-ref.nii.gz"
    [ "$status" -eq 0 ]
    jc_files
    [ "$(sed -n 2p "$JC_INDIV")" = "1, .499999" ]
    [ "$(cat "$JC_MEAN")" = ".499999" ]
}

@test "Dice values with huge or tiny exponents are handled, not turned into numbers" {
    export STUB_SEG_STATS_OUT='L[1] = 1e99999\nL[2] = 1e400\nL[3] = 1e-99999\nL[4] = 1e-400\nM = 1e99999\n'
    run_maper a1 -tgtlabels "seg:$FX/t-ref.nii.gz"
    [ "$status" -eq 0 ]
    jc_files
    # far above 1: not a Dice value; far below any six decimals: zero
    [ "$(cat "$JC_INDIV")" = $'region,jc\n1, NA\n2, NA\n3, 0\n4, 0' ]
    [ "$(cat "$JC_MEAN")" = "NA" ]
}

@test "Dice in scientific notation also works where the decimal separator is a comma" {
    # printf reads and writes numbers in the locale's notation, which would reject "1.5e-05".
    # LOCPATH has to be in the environment of the process that starts (libc reads it from
    # there), so maper is started with env instead of exporting the variables here.
    [ -e /usr/share/i18n/locales/de_DE ] && command -v localedef >/dev/null \
        || skip "no locale sources to build a German locale from"
    local loc="$BATS_TEST_TMPDIR/locale"
    mkdir "$loc"
    localedef -i de_DE -f UTF-8 "$loc/de_DE.UTF-8" 2>/dev/null || true
    [ "$(env LOCPATH="$loc" LC_ALL=de_DE.UTF-8 bash -c "printf '%.1f' 1,5" 2>/dev/null)" = "1,5" ] \
        || skip "could not build a locale with a decimal comma"
    export STUB_SEG_STATS_OUT='L[1] = 1.5e-05\nL[2] = 0.5\nM = 2.5e-1\n'
    build_args a1
    run env LOCPATH="$loc" LC_ALL=de_DE.UTF-8 "$MAPER" -srcid a1 -tgtid T1 "${ARGS_NOID[@]}" \
        -tgtlabels "seg:$FX/t-ref.nii.gz"
    [ "$status" -eq 0 ]
    jc_files
    [ "$(cat "$JC_INDIV")" = $'region,jc\n1, .000007\n2, .333333' ]
    [ "$(cat "$JC_MEAN")" = ".142857" ]
}

# --- jobs running at the same time ---------------------------------------------------
#
# The races are forced, not hoped for: tests/stubs/lockpause makes a job sit on the fusion
# lock at a chosen point, and tests/stubs/cp writes files slowly in two halves so that the
# test can look at them while they are half written.

no_leftovers() { # the output directory holds no lock, no re-check marker, no temporary file
    [ -z "$(find "$OUT" \( -name '*fusion-*' -o -name '*.tmp.*' \) | head -n 1)" ]
}

@test "fusion: a result that is published while another job holds the lock is not missed" {
    run_maper a1 -atlasn 3
    [ "$status" -eq 0 ]
    # job a2 takes the lock and sits on it before it looks at the results ...
    maper_pair a2 -atlasn 3
    STUB_LOCK_ACQUIRE_PAUSE=5 "${MAPER_PAIR[@]}" >"$BATS_TEST_TMPDIR/a2.log" 2>&1 &
    local pid=$!
    wait_for "$OUT/fusion-semaphore-seg-T1"
    # ... and job a3 delivers the third result while it does
    run_maper a3 -atlasn 3
    [ "$status" -eq 0 ]
    wait "$pid"
    [ -s "$OUT/f3-seg-T1.nii.gz" ]
}

@test "fusion: a result that arrives after the lock holder has counted is picked up when it lets go" {
    run_maper a1 -atlasn 3
    [ "$status" -eq 0 ]
    # job a2 has counted two results and is about to release the lock ...
    maper_pair a2 -atlasn 3
    STUB_LOCK_RELEASE_PAUSE=5 "${MAPER_PAIR[@]}" >"$BATS_TEST_TMPDIR/a2.log" 2>&1 &
    local pid=$!
    wait_for "$OUT/fusion-semaphore-seg-T1"
    # ... when job a3 delivers the third result and cannot get the lock
    run_maper a3 -atlasn 3
    [ "$status" -eq 0 ]
    [ ! -e "$OUT/f3-seg-T1.nii.gz" ]    # a3 left it to the lock holder
    wait "$pid"
    [ -s "$OUT/f3-seg-T1.nii.gz" ]
}

@test "fusion: no lock, marker or temporary file is left behind" {
    local s
    for s in a1 a2 a3 ; do
        run_maper "$s" -atlasn 3
        [ "$status" -eq 0 ]
    done
    [ -s "$OUT/f3-seg-T1.nii.gz" ]
    no_leftovers
}

@test "fusion: eight jobs at once give exactly one fused result, round after round" {
    # Without forced timing this still catches the lost hand-over: the code that counted before
    # taking the lock failed in about one round in three here (all jobs exiting 0, no fusion).
    local k part round pids pid
    for k in 1 2 3 4 5 6 7 8 ; do
        for part in mri mask seg seg2 ; do cp "$FX/a1-$part.nii.gz" "$FX/s$k-$part.nii.gz" ; done
    done
    for round in 1 2 3 4 5 6 ; do
        OUT="$BATS_TEST_TMPDIR/round$round"
        pids=()
        for k in 1 2 3 4 5 6 7 8 ; do
            maper_pair "s$k" -atlasn 8 -tgtlabels "seg:$FX/t-ref.nii.gz" -srccache "$BATS_TEST_TMPDIR/cache"
            "${MAPER_PAIR[@]}" >"$BATS_TEST_TMPDIR/s$k.$round.log" 2>&1 &
            pids+=($!)
        done
        for pid in "${pids[@]}" ; do wait "$pid" ; done
        [ -s "$OUT/f8-seg-T1.nii.gz" ]
        [ "$(ls "$OUT" | grep -c '^f[0-9]*-seg-T1.nii.gz$')" -eq 1 ]
        no_leftovers
    done
}

sizes_of_results() { # the size of each result file that exists
    local f
    for f in "$OUT/T1/a1-T1/src-tgt.dof.gz" "$OUT/T1/a1-T1/seg/seg.nii.gz" ; do
        if [[ -e $f ]] ; then wc -c < "$f" ; fi
    done
}

@test "results appear in the output directory complete or not at all" {
    maper_pair a1
    STUB_CP_PAUSE=0.3 STUB_CP_MATCH="$OUT" "${MAPER_PAIR[@]}" >"$BATS_TEST_TMPDIR/a1.log" 2>&1 &
    local pid=$!
    local sizes size
    sizes=$(watch_until_exit "$pid" sizes_of_results)
    wait "$pid"
    [ -s "$OUT/T1/a1-T1/seg/seg.nii.gz" ]
    [ -n "$sizes" ]                          # the files were looked at while they were being written
    for size in $sizes ; do
        [ "$size" -eq 5 ]                    # "stub" and a newline: never half of it
    done
    no_leftovers
}

entries_of() { # the number of entries of a directory, if it exists
    if [[ -d $1 ]] ; then ls "$1" | wc -l ; fi
}

@test "a cache is visible complete or not at all while it is filled" {
    local c="$BATS_TEST_TMPDIR/cache" counts n final
    mkdir "$c"
    maper_pair a1 -srccache "$c"
    STUB_CP_PAUSE=0.15 STUB_CP_MATCH="$c" "${MAPER_PAIR[@]}" >"$BATS_TEST_TMPDIR/a1.log" 2>&1 &
    local pid=$!
    counts=$(watch_until_exit "$pid" entries_of "$c/a1")
    wait "$pid"
    final=$(ls "$c/a1" | wc -l)
    [ "$final" -gt 8 ]
    for n in $counts ; do
        if [ "$n" -ne 0 ] && [ "$n" -ne "$final" ] ; then
            echo "saw a cache of $n files while it should have 0 or $final" >&2
            false
        fi
    done
    [ -z "$(find "$c" -name '*.tmp.*')" ]
}

@test "two jobs filling the same cold cache at once: one complete cache, both jobs succeed" {
    local c="$BATS_TEST_TMPDIR/cache"
    mkdir "$c"
    maper_pair a1 -srccache "$c" -output-dir "$BATS_TEST_TMPDIR/out-x"
    STUB_CP_PAUSE=0.1 STUB_CP_MATCH="$c" "${MAPER_PAIR[@]}" >"$BATS_TEST_TMPDIR/x.log" 2>&1 &
    local px=$!
    maper_pair a1 -srccache "$c" -output-dir "$BATS_TEST_TMPDIR/out-y"
    STUB_CP_PAUSE=0.1 STUB_CP_MATCH="$c" "${MAPER_PAIR[@]}" >"$BATS_TEST_TMPDIR/y.log" 2>&1 &
    local py=$!
    wait "$px"
    wait "$py"
    [ "$(ls "$c/a1" | wc -l)" -gt 8 ]
    [ "$(find "$c/a1" -type f -size -5c | wc -l)" -eq 0 ]
    [ -z "$(find "$c" -name '*.tmp.*')" ]
    [ -s "$BATS_TEST_TMPDIR/out-x/T1/a1-T1/src-tgt.dof.gz" ]
    [ -s "$BATS_TEST_TMPDIR/out-y/T1/a1-T1/src-tgt.dof.gz" ]
}

# --- the working directory ------------------------------------------------------------

working_dirs() { # the working directories maper leaves in $TMPDIR/$USER
    if [[ -d $TMPDIR/$USER ]] ; then ls "$TMPDIR/$USER" | wc -l ; else echo 0 ; fi
}

@test "the working directory is removed when maper ends" {
    run_maper a1
    [ "$status" -eq 0 ]
    [ "$(working_dirs)" -eq 0 ]
}

@test "the working directory is removed when maper fails" {
    export STUB_FAIL=mirtk:register
    run_maper a1
    [ "$status" -ne 0 ]
    [ "$(working_dirs)" -eq 0 ]
}

@test "savewd=1 in the environment keeps the working directory (a debugging aid)" {
    export savewd=1
    run_maper a1
    [ "$status" -eq 0 ]
    [ "$(working_dirs)" -eq 1 ]
}

@test "a TMPDIR whose path contains a space works" {
    export TMPDIR="$BATS_TEST_TMPDIR/tmp dir with space"
    mkdir "$TMPDIR"
    run_maper a1
    [ "$status" -eq 0 ]
    [ -s "$OUT/T1/a1-T1/src-tgt.dof.gz" ]
    [ "$(working_dirs)" -eq 0 ]
}

@test "-verbose passes on the output of the registration line by line, backslashes and all" {
    export STUB_REGISTER_LINE='a line that ends in a backslash \'
    run_maper a1 -verbose
    [ "$status" -eq 0 ]
    [ "$(stub_calls mirtk register)" -gt 1 ]
    # one message per line printed; a plain "read" would join each with the next line
    [ "$(grep -c '^maper: a line that ends in a backslash \\$' <<< "$output")" -eq "$(stub_calls mirtk register)" ]
}

@test "maper reports its runtime in seconds" {
    run_maper a1
    [ "$status" -eq 0 ]
    [[ $output =~ maper:\ runtime:\ [0-9]+\ seconds ]]
}

@test "-debug keeps a copy of the working directory when the TMPDIR path contains a space" {
    export TMPDIR="$BATS_TEST_TMPDIR/tmp dir with space"
    mkdir "$TMPDIR"
    run_maper a1 -debug
    [ "$status" -eq 0 ]
    [ "$(find "$OUT/T1/a1-T1" -maxdepth 1 -type d -name 'maper.*' | wc -l)" -eq 1 ]
}

@test "maper works from an installation whose path contains a space" {
    local inst="$BATS_TEST_TMPDIR/install dir with space"
    mkdir "$inst"
    cp "$MAPER_ROOT"/{maper,generic-functions,neutral.dof.gz,rightmask.nii.gz} "$inst"/
    MAPER="$inst/maper"
    run_maper a1
    [ "$status" -eq 0 ]
    # the right mask of the atlas is the one file of the installation that mirtk is handed
    grep -q -F "mirtk [transform-image] [$inst/rightmask.nii.gz] " "$STUB_LOG.args"
    [ -s "$OUT/T1/a1-T1/src-tgt.dof.gz" ]
}

# --- a fusion lock whose holder died --------------------------------------------------------
#
# A job that is killed with SIGKILL (a cluster's last resort at the wall time limit) cannot
# clean up. Its lock must not block the fusion of that target for good: the holder refreshes
# its lock, and a lock that has been quiet for MAPER_LOCK_TIMEOUT seconds is taken over.

fast_locks() { export MAPER_LOCK_HEARTBEAT=1 MAPER_LOCK_TIMEOUT=6 ; }

lock_of() { echo "$OUT/fusion-semaphore-seg-T1" ; }

# a2 is in the middle of its pass, holding the lock (it was told to sit there before it lets go)
start_holder_a2() {
    maper_pair a2 -atlasn 3
    STUB_LOCK_RELEASE_PAUSE=${1:-60} "${MAPER_PAIR[@]}" 3>&- >"$BATS_TEST_TMPDIR/a2.log" 2>&1 &
    HOLDER=$!
    wait_for "$(lock_of)"
}

@test "fusion lock: a job killed with SIGKILL while it holds the lock does not block the fusion for good" {
    fast_locks
    run_maper a1 -atlasn 3
    [ "$status" -eq 0 ]
    start_holder_a2
    kill -9 "$HOLDER"
    wait "$HOLDER" 2>/dev/null || true
    [ -d "$(lock_of)" ]                              # nothing could clean up: the lock is stranded
    # a3 finishes while the lock still looks alive: it leaves the work to the holder ...
    run_maper a3 -atlasn 3
    [ "$status" -eq 0 ]
    [ ! -e "$OUT/f3-seg-T1.nii.gz" ]
    # ... and a run after the holder has been quiet for longer than the timeout takes over
    sleep 8
    run_maper a3 -atlasn 3
    [ "$status" -eq 0 ]
    [ -s "$OUT/f3-seg-T1.nii.gz" ]
    [ ! -e "$(lock_of)" ]
}

@test "fusion lock: a holder that is slow but alive keeps its lock beyond the timeout" {
    fast_locks
    run_maper a1 -atlasn 3
    [ "$status" -eq 0 ]
    start_holder_a2 12
    sleep 8                                          # longer than MAPER_LOCK_TIMEOUT
    run_maper a3 -atlasn 3                           # sees a lock that is old but beating
    [ "$status" -eq 0 ]
    [[ $output != *"taking it over"* ]]
    wait "$HOLDER"
    [ -s "$OUT/f3-seg-T1.nii.gz" ]                   # the holder fused, with a3's result
    [ "$(ls "$OUT" | grep -c '^f[0-9]*-seg-T1.nii.gz$')" -eq 1 ]
}

@test "fusion lock: a lock of another host that has gone quiet is taken over, one that is beating is not" {
    fast_locks
    local s
    for s in a1 a2 ; do
        run_maper "$s" -atlasn 3
        [ "$status" -eq 0 ]
    done
    mkdir "$(lock_of)"
    echo "othernode:4242" > "$(lock_of)/owner"
    run_maper a3 -atlasn 3                           # fresh: for all anyone can tell, alive
    [ "$status" -eq 0 ]
    [ ! -e "$OUT/f3-seg-T1.nii.gz" ]
    [ -d "$(lock_of)" ]
    touch -d '10 minutes ago' "$(lock_of)/owner"
    run_maper a3 -atlasn 3
    [ "$status" -eq 0 ]
    [[ $output == *"othernode:4242"* ]]              # the warning says whose lock it was
    [ -s "$OUT/f3-seg-T1.nii.gz" ]
}

@test "fusion lock: an empty lock directory left by an earlier version is taken over" {
    local s
    for s in a1 a2 ; do
        run_maper "$s" -atlasn 3
        [ "$status" -eq 0 ]
    done
    mkdir "$(lock_of)"
    run_maper a3 -atlasn 3
    [ "$status" -eq 0 ]
    [ -s "$OUT/f3-seg-T1.nii.gz" ]
}

@test "fusion lock: six jobs that find the same dead lock at once: one takes over, one fusion" {
    fast_locks
    local k part round pids pid
    for k in 1 2 3 4 5 6 ; do
        for part in mri mask seg seg2 ; do cp "$FX/a1-$part.nii.gz" "$FX/s$k-$part.nii.gz" ; done
    done
    for round in 1 2 3 ; do
        OUT="$BATS_TEST_TMPDIR/round$round"
        mkdir -p "$(lock_of)"
        echo "othernode:4242" > "$(lock_of)/owner"
        touch -d '10 minutes ago' "$(lock_of)/owner"
        pids=()
        for k in 1 2 3 4 5 6 ; do
            maper_pair "s$k" -atlasn 6
            "${MAPER_PAIR[@]}" >"$BATS_TEST_TMPDIR/s$k.$round.log" 2>&1 &
            pids+=($!)
        done
        for pid in "${pids[@]}" ; do wait "$pid" ; done
        [ -s "$OUT/f6-seg-T1.nii.gz" ]
        [ "$(ls "$OUT" | grep -c '^f[0-9]*-seg-T1.nii.gz$')" -eq 1 ]
        no_leftovers
    done
}

@test "fusion lock: the refreshing of the lock does not hold the caller's pipe open" {
    # a child process that kept stdout would make "| cat" wait for it
    export MAPER_LOCK_HEARTBEAT=30
    maper_pair a1 -atlasn 3
    local before after
    before=$(date +%s)
    "${MAPER_PAIR[@]}" 2>&1 | cat > /dev/null
    after=$(date +%s)
    [ $(( after - before )) -lt 20 ]
}

@test "fusion lock: nothing keeps running after maper has ended" {
    export MAPER_LOCK_HEARTBEAT=1
    run_maper a1 -atlasn 3
    [ "$status" -eq 0 ]
    sleep 1.5
    [ -z "$(pgrep -f "$BATS_TEST_TMPDIR" || true)" ]
}

@test "fusion lock: unusable timing settings are rejected before any work is done" {
    export MAPER_LOCK_TIMEOUT=soon
    run_maper a1 -atlasn 3
    [ "$status" -eq 1 ]
    [[ $output == *"MAPER_LOCK_TIMEOUT"* ]]
    [ "$(stub_calls mirtk)" -eq 0 ]
    export MAPER_LOCK_HEARTBEAT=10 MAPER_LOCK_TIMEOUT=10
    run_maper a1 -atlasn 3
    [ "$status" -eq 1 ]
    [[ $output == *"longer than"* ]]
    [ "$(stub_calls mirtk)" -eq 0 ]
    [ ! -e "$OUT" ]
}

@test "fusion lock: a killed holder that nobody has reaped yet (a zombie) is still recognised as dead" {
    # Where the parent of a job does not reap it (pid 1 of many containers), the killed holder stays
    # a zombie, for which kill -0 still succeeds: its refreshing must stop anyway.
    [ -r /proc/self/stat ] || skip "needs /proc to see the state of a process"
    fast_locks
    run_maper a1 -atlasn 3
    [ "$status" -eq 0 ]
    maper_pair a2 -atlasn 3
    local pidfile="$BATS_TEST_TMPDIR/holder.pid"
    STUB_LOCK_RELEASE_PAUSE=60 python3 -c '
import subprocess, sys, time
p = subprocess.Popen(sys.argv[2:], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
open(sys.argv[1], "w").write(str(p.pid))
time.sleep(45)                      # never waits for the child
' "$pidfile" "${MAPER_PAIR[@]}" &
    local parent=$!
    wait_for "$(lock_of)"
    local holder
    holder=$(cat "$pidfile")
    kill -9 "$holder"
    sleep 0.5
    local stat; stat=$(< "/proc/$holder/stat")
    [[ ${stat##*) } == Z* ]]                       # the premise: the holder is a zombie now
    sleep 8                                          # longer than MAPER_LOCK_TIMEOUT
    run_maper a3 -atlasn 3
    [ "$status" -eq 0 ]
    [ -s "$OUT/f3-seg-T1.nii.gz" ]
    kill "$parent" 2>/dev/null || true
}

@test "fusion lock: a job that was slow to claim a dead lock leaves a fresh lock of somebody else alone" {
    fast_locks
    local s
    for s in a1 a2 ; do
        run_maper "$s" -atlasn 3
        [ "$status" -eq 0 ]
    done
    mkdir "$(lock_of)"
    echo "deadnode:1" > "$(lock_of)/owner"
    touch -d '10 minutes ago' "$(lock_of)/owner"
    maper_pair a3 -atlasn 3
    STUB_BREAK_PAUSE=3 "${MAPER_PAIR[@]}" >"$BATS_TEST_TMPDIR/a3.log" 2>&1 &
    local slow=$!
    wait_for "$BATS_TEST_TMPDIR/break-paused"        # a3 has found the lock dead, and is about to claim it
    rm -rf "$(lock_of)"                              # in the meantime somebody else took it over ...
    mkdir "$(lock_of)"
    echo "othernode:7" > "$(lock_of)/owner"          # ... and is alive
    wait "$slow"
    [ "$(cat "$(lock_of)/owner")" = "othernode:7" ]
    [ ! -e "$OUT/f3-seg-T1.nii.gz" ]
    [[ $(< "$BATS_TEST_TMPDIR/a3.log") != *"taking it over"* ]]
}

@test "fusion lock: a lock that is being released is not taken over from under the job releasing it" {
    fast_locks
    run_maper a1 -atlasn 3
    [ "$status" -eq 0 ]
    maper_pair a2 -atlasn 3
    STUB_LOCK_HALFWAY_PAUSE=3 "${MAPER_PAIR[@]}" >"$BATS_TEST_TMPDIR/a2.log" 2>&1 &
    local releasing=$!
    # a2 is done with its pass; wherever it is while letting go, a3 comes in now
    until [ -e "$BATS_TEST_TMPDIR/halfway-paused" ] || ! kill -0 "$releasing" 2>/dev/null ; do sleep 0.1 ; done
    STUB_LOCK_RELEASE_PAUSE=5 run_maper a3 -atlasn 3
    [ "$status" -eq 0 ]
    wait "$releasing"                                # a2 must not fail because a3 holds the lock by now
    [ -s "$OUT/f3-seg-T1.nii.gz" ]
    [ "$(ls "$OUT" | grep -c '^f[0-9]*-seg-T1.nii.gz$')" -eq 1 ]
    [ ! -e "$(lock_of)" ]
}

@test "fusion lock: a job that is terminated (SIGTERM) lets go of its lock and ends its refreshing at once" {
    fast_locks
    run_maper a1 -atlasn 3
    [ "$status" -eq 0 ]
    start_holder_a2
    kill -TERM "$HOLDER"
    wait "$HOLDER" 2>/dev/null || true
    [ ! -e "$(lock_of)" ]
    [ -z "$(pgrep -f "maper -srcid.*$BATS_TEST_TMPDIR" || true)" ]   # no refreshing left behind
}

@test "fusion lock: a job that loses the race for the lock after looking leaves the winner's lock as it is" {
    # mv puts a directory inside one that exists (the BSD mv has no -T to say it should not);
    # the job must notice that it did not get the lock, and take its directory out again
    fast_locks
    local s
    for s in a1 a2 ; do
        run_maper "$s" -atlasn 3
        [ "$status" -eq 0 ]
    done
    maper_pair a3 -atlasn 3
    STUB_LOCK_INSTALL_PAUSE=3 "${MAPER_PAIR[@]}" 3>&- >"$BATS_TEST_TMPDIR/a3.log" 2>&1 &
    local slow=$!
    wait_for "$BATS_TEST_TMPDIR/install-paused"      # a3 has seen no lock and is about to put its own in place
    mkdir "$(lock_of)"                               # in the meantime another job did
    echo "othernode:7" > "$(lock_of)/owner"
    wait "$slow"
    [ "$(ls -A "$(lock_of)")" = "owner" ]            # nothing of a3's is left inside it
    [ "$(cat "$(lock_of)/owner")" = "othernode:7" ]
    [ ! -e "$OUT/f3-seg-T1.nii.gz" ]                 # a3 does not fuse under a lock that is not its own
    [ -z "$(ls -A "$OUT" | grep '^\.' || true)" ]    # and leaves no temporary directory
}
