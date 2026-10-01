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
