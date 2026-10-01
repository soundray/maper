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
