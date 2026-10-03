#!/usr/bin/env bats

load test_helper

setup() { setup_common ; default_csvs ; }

# --- behaviour that must be preserved -----------------------------------------

@test "one line per source/target pair" {
    run_llgen
    [ "$status" -eq 0 ]
    [ "$(ll_count)" -eq 3 ]
}

@test "line carries ids, atlas count, output directory and threads" {
    run_llgen -threads 2
    [ "$status" -eq 0 ]
    ll_words 1
    [ "${WORDS[0]}" = "$MAPER" ]
    [ "$(ll_values -tgtid)" = T1 ]
    [ "$(ll_values -srcid)" = a1 ]
    [ "$(ll_values -atlasn)" = 3 ]
    [ "$(ll_values -output-dir)" = "$OUT" ]
    [ "$(ll_values -threads)" = 2 ]
}

@test "image paths are resolved against the description's directory by default" {
    run_llgen
    ll_words 1
    [ "$(ll_values -srcmri)" = "$FX/a1-mri.nii.gz" ]
    [ "$(ll_values -srcmask)" = "$FX/a1-mask.nii.gz" ]
    [ "$(ll_values -tgtmri)" = "$FX/t-mri.nii.gz" ]
    [ "$(ll_values -tgtmask)" = "$FX/t-mask.nii.gz" ]
    [ "$(ll_values -srclabels)" = "seg:$FX/a1-seg.nii.gz" ]
}

@test "-src-base and -tgt-base replace the description's directory" {
    mkdir "$BATS_TEST_TMPDIR/atlases" "$BATS_TEST_TMPDIR/targets"
    cp "$FX"/a?-*.nii.gz "$BATS_TEST_TMPDIR/atlases/"
    cp "$FX"/t-*.nii.gz "$BATS_TEST_TMPDIR/targets/"
    run_llgen -src-base "$BATS_TEST_TMPDIR/atlases" -tgt-base "$BATS_TEST_TMPDIR/targets"
    [ "$status" -eq 0 ]
    ll_words 1
    [ "$(ll_values -srcmri)" = "$BATS_TEST_TMPDIR/atlases/a1-mri.nii.gz" ]
    [ "$(ll_values -tgtmri)" = "$BATS_TEST_TMPDIR/targets/t-mri.nii.gz" ]
}

@test "every known column maps to its maper option, for sources and targets" {
    write_csv src.csv "id, onepad, pretransformation, tc3raw, brainmask, mri, seg" \
        "a1, a1-op.nii.gz, a1.dof.gz, a1-tc.nii.gz, a1-mask.nii.gz, a1-mri.nii.gz, a1-seg.nii.gz"
    write_csv tgt.csv "id, onepad, pretransformation, tc3raw, brainmask, mri, seg" \
        "T1, t-op.nii.gz, t.dof.gz, t-tc.nii.gz, t-mask.nii.gz, t-mri.nii.gz, t-ref.nii.gz"
    run_llgen
    [ "$status" -eq 0 ]
    ll_words 1
    [ "$(ll_values -srcop)" = "$FX/a1-op.nii.gz" ]
    [ "$(ll_values -spn)" = "$FX/a1.dof.gz" ]
    [ "$(ll_values -srctc3raw)" = "$FX/a1-tc.nii.gz" ]
    [ "$(ll_values -srcmask)" = "$FX/a1-mask.nii.gz" ]
    [ "$(ll_values -srcmri)" = "$FX/a1-mri.nii.gz" ]
    [ "$(ll_values -srclabels)" = "seg:$FX/a1-seg.nii.gz" ]
    [ "$(ll_values -tgtop)" = "$FX/t-op.nii.gz" ]
    [ "$(ll_values -tpn)" = "$FX/t.dof.gz" ]
    [ "$(ll_values -tgttc3raw)" = "$FX/t-tc.nii.gz" ]
    [ "$(ll_values -tgtmask)" = "$FX/t-mask.nii.gz" ]
    [ "$(ll_values -tgtmri)" = "$FX/t-mri.nii.gz" ]
    [ "$(ll_values -tgtlabels)" = "seg:$FX/t-ref.nii.gz" ]
}

@test "header names are case-insensitive and label set names are lower-cased" {
    write_csv src.csv "ID, MRI, BrainMask, Seg95" \
        "a1, a1-mri.nii.gz, a1-mask.nii.gz, a1-seg.nii.gz"
    run_llgen
    [ "$status" -eq 0 ]
    ll_words 1
    [ "$(ll_values -srcid)" = a1 ]
    [ "$(ll_values -srclabels)" = "seg95:$FX/a1-seg.nii.gz" ]
}

@test "comment lines in the source description are ignored and not counted as atlases" {
    write_csv src.csv "# atlas list" "id, mri, brainmask, seg" \
        "a1, a1-mri.nii.gz, a1-mask.nii.gz, a1-seg.nii.gz" \
        "# a2 is excluded for now" \
        "a3, a3-mri.nii.gz, a3-mask.nii.gz, a3-seg.nii.gz"
    run_llgen
    [ "$status" -eq 0 ]
    [ "$(ll_count)" -eq 2 ]
    ll_words 1
    [ "$(ll_values -atlasn)" = 2 ]
}

@test "-loocv leaves out the pair of an image with itself and counts one atlas fewer" {
    write_csv src.csv "id, mri, brainmask, seg" \
        "a1, a1-mri.nii.gz, a1-mask.nii.gz, a1-seg.nii.gz" \
        "a2, a2-mri.nii.gz, a2-mask.nii.gz, a2-seg.nii.gz" \
        "a3, a3-mri.nii.gz, a3-mask.nii.gz, a3-seg.nii.gz"
    write_csv tgt.csv "id, mri, brainmask" "a2, a2-mri.nii.gz, a2-mask.nii.gz"
    run_llgen -loocv
    [ "$status" -eq 0 ]
    [ "$(ll_count)" -eq 2 ]
    [ "$(grep -c -e '-srcid a2 ' "$LL" || true)" -eq 0 ]
    ll_words 1
    [ "$(ll_values -atlasn)" = 2 ]
}

@test "-quicktest, -notc3, caches and -threads are forwarded" {
    run_llgen -quicktest -notc3 -threads 1 -src-cache "$BATS_TEST_TMPDIR/cs" -tgt-cache "$BATS_TEST_TMPDIR/ct"
    [ "$status" -eq 0 ]
    ll_words 1
    ll_has -quicktest
    ll_has -notc3
    [ "$(ll_values -srccache)" = "$BATS_TEST_TMPDIR/cs" ]
    [ "$(ll_values -tgtcache)" = "$BATS_TEST_TMPDIR/ct" ]
}

@test "the call is logged next to the launchlist" {
    run_llgen
    [ -s "$LL-genlog.txt" ]
}

@test "missing source description is reported" {
    run "$LAUNCHLIST_GEN" -src-description "$FX/nope.csv" -tgt-description "$FX/tgt.csv" \
        -output-dir "$OUT" -launchlist "$BATS_TEST_TMPDIR/l.sh"
    [ "$status" -ne 0 ]
    [[ $output == *"Source description"*"does not exist"* ]]
}

@test "end to end: the launchlist runs under maper and fuses the result" {
    run_llgen
    [ "$status" -eq 0 ]
    run bash "$LL"
    [ "$status" -eq 0 ]
    [ -s "$OUT/T1/a1-T1/src-tgt.dof.gz" ]
    [ -s "$OUT/f3-seg-T1.nii.gz" ]
}
