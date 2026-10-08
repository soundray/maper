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
    # launchlist-gen refuses more threads than this machine has processors
    [ "$(nproc)" -ge 2 ] || skip "needs at least two processors"
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

# --- options --------------------------------------------------------------------

@test "-h prints the usage text and exits 0" {
    run "$LAUNCHLIST_GEN" -h
    [ "$status" -eq 0 ]
    [[ $output == *"Usage:"* ]]
}

@test "usage documents the tissue-class options" {
    run "$LAUNCHLIST_GEN" --help
    [[ $output == *"-notc"* && $output == *"-tc2"* && $output == *"-tc3"* ]]
}

@test "missing -src-description is reported by name" {
    run "$LAUNCHLIST_GEN" -tgt-description "$FX/tgt.csv" -output-dir "$OUT"
    [ "$status" -ne 0 ]
    [[ $output == *"-src-description is required"* ]]
}

@test "missing -tgt-description is reported by name" {
    run "$LAUNCHLIST_GEN" -src-description "$FX/src.csv" -output-dir "$OUT"
    [ "$status" -ne 0 ]
    [[ $output == *"-tgt-description is required"* ]]
}

@test "unknown option is rejected and named" {
    run_llgen -bogus
    [ "$status" -ne 0 ]
    [[ $output == *"Unknown option: -bogus"* ]]
}

@test "stray argument is rejected" {
    run_llgen stray
    [ "$status" -ne 0 ]
    [[ $output == *"Unexpected argument: stray"* ]]
}

@test "option without a value is reported by name" {
    run_llgen -threads
    [ "$status" -ne 0 ]
    [[ $output == *"-threads requires a value"* ]]
}

@test "-src-base that is not a directory is an error, not a silent fallback" {
    run_llgen -src-base "$BATS_TEST_TMPDIR/no-such-dir"
    [ "$status" -ne 0 ]
    [[ $output == *"-src-base"* ]]
}

@test "-tc2, -tc3 and -notc are forwarded to every line" {
    local opt
    for opt in -tc2 -tc3 -notc ; do
        run_llgen "$opt"
        [ "$status" -eq 0 ]
        local n
        for n in 1 2 3 ; do
            ll_words "$n"
            ll_has "$opt"
        done
    done
}

@test "-tc2 together with -tc3 is rejected" {
    run_llgen -tc2 -tc3
    [ "$status" -ne 0 ]
    [[ $output == *"only one of -tc2 and -tc3"* ]]
}

@test "-notc together with -tc3 is rejected" {
    run_llgen -notc -tc3
    [ "$status" -ne 0 ]
    [[ $output == *"-notc is incompatible"* ]]
}

@test "-threads must be a positive integer" {
    local bad
    for bad in abc1 1x -3 0 "" ; do
        run_llgen -threads "$bad"
        [ "$status" -ne 0 ]
        [[ $output == *"-threads requires a positive integer"* ]]
    done
}

@test "-threads above the processor count of this machine is rejected" {
    run_llgen -threads 100000
    [ "$status" -ne 0 ]
    [[ $output == *"-threads"*"exceeds"* ]]
}

@test "-arch is still accepted, and reported as ignored" {
    run_llgen -arch x86_64
    [ "$status" -eq 0 ]
    [[ $output == *"-arch"*"ignored"* ]]
}

@test "-fastmode is still accepted" {
    run_llgen -fastmode
    [ "$status" -eq 0 ]
    [ "$(ll_count)" -eq 3 ]
}

@test "works on a machine without MIRTK and NiftySeg (only maper needs them)" {
    LL="$BATS_TEST_TMPDIR/launchlist.sh"
    run env PATH=/usr/bin:/bin "$LAUNCHLIST_GEN" -src-description "$FX/src.csv" \
        -tgt-description "$FX/tgt.csv" -output-dir "$OUT" -launchlist "$LL"
    [ "$status" -eq 0 ]
    [ "$(ll_count)" -eq 3 ]
}

@test "never runs maper itself: generating a launchlist has no side effects" {
    # A per-pair "maper -dry-run" pre-check was long intended but never ran.
    # Naively enabling it would stage full images for every source/target pair.
    local spy="$BATS_TEST_TMPDIR/spy"
    mkdir "$spy"
    cp "$MAPER_ROOT/launchlist-gen" "$MAPER_ROOT/generic-functions" "$spy/"
    printf '#!/usr/bin/env bash\necho "$*" >> "%s"\n' "$BATS_TEST_TMPDIR/spy.log" > "$spy/maper"
    chmod +x "$spy/maper"
    LL="$BATS_TEST_TMPDIR/launchlist.sh"
    run "$spy/launchlist-gen" -src-description "$FX/src.csv" -tgt-description "$FX/tgt.csv" \
        -output-dir "$OUT" -launchlist "$LL"
    [ "$status" -eq 0 ]
    [ ! -e "$BATS_TEST_TMPDIR/spy.log" ]
}

# --- description files ----------------------------------------------------------

@test "a description may have more than eight columns: four label sets plus all fixed columns" {
    local k
    for k in A B C D ; do echo data > "$FX/a1-s$k.nii.gz" ; echo data > "$FX/t-s$k.nii.gz" ; done
    write_csv src.csv "id, mri, brainmask, tc3raw, pretransformation, segA, segB, segC, segD" \
        "a1, a1-mri.nii.gz, a1-mask.nii.gz, a1-tc.nii.gz, a1.dof.gz, a1-sA.nii.gz, a1-sB.nii.gz, a1-sC.nii.gz, a1-sD.nii.gz"
    run_llgen
    [ "$status" -eq 0 ]
    ll_words 1
    run ll_values -srclabels
    [ "${lines[0]}" = "sega:$FX/a1-sA.nii.gz" ]
    [ "${lines[1]}" = "segb:$FX/a1-sB.nii.gz" ]
    [ "${lines[2]}" = "segc:$FX/a1-sC.nii.gz" ]
    [ "${lines[3]}" = "segd:$FX/a1-sD.nii.gz" ]
    [ "${#lines[@]}" -eq 4 ]
}

@test "label sets are emitted in the order of the header, so the launchlist is deterministic" {
    local k
    for k in zeta alpha mid beta ; do echo data > "$FX/a1-$k.nii.gz" ; done
    write_csv src.csv "id, mri, zeta, alpha, mid, beta" \
        "a1, a1-mri.nii.gz, a1-zeta.nii.gz, a1-alpha.nii.gz, a1-mid.nii.gz, a1-beta.nii.gz"
    run_llgen
    [ "$status" -eq 0 ]
    ll_words 1
    run ll_values -srclabels
    [ "${lines[0]%%:*}" = zeta ]
    [ "${lines[1]%%:*}" = alpha ]
    [ "${lines[2]%%:*}" = mid ]
    [ "${lines[3]%%:*}" = beta ]
}

@test "an empty optional cell does not shift the cells after it" {
    write_csv tgt.csv "id, mri, brainmask, seg" "T1, t-mri.nii.gz, , t-ref.nii.gz"
    run_llgen
    [ "$status" -eq 0 ]
    ll_words 1
    [ "$(ll_values -tgtmri)" = "$FX/t-mri.nii.gz" ]
    [ -z "$(ll_values -tgtmask)" ]
    [ "$(ll_values -tgtlabels)" = "seg:$FX/t-ref.nii.gz" ]
}

@test "a target without a reference (empty trailing cell) simply has no -tgtlabels" {
    write_csv tgt.csv "id, mri, brainmask, seg" \
        "T1, t-mri.nii.gz, t-mask.nii.gz, t-ref.nii.gz" \
        "T2, t-mri.nii.gz, t-mask.nii.gz,"
    run_llgen
    [ "$status" -eq 0 ]
    [ "$(ll_count)" -eq 6 ]
    ll_words 1
    [ "$(ll_values -tgtid)" = T1 ]
    [ -n "$(ll_values -tgtlabels)" ]
    ll_words 4
    [ "$(ll_values -tgtid)" = T2 ]
    [ -z "$(ll_values -tgtlabels)" ]
}

@test "an atlas without a value for a label set is an error that names the row" {
    write_csv src.csv "id, mri, brainmask, seg" \
        "a1, a1-mri.nii.gz, a1-mask.nii.gz, a1-seg.nii.gz" \
        "a2, a2-mri.nii.gz, a2-mask.nii.gz,"
    run_llgen
    [ "$status" -ne 0 ]
    [[ $output == *"a2"*"seg"* ]]
}

@test "paths with spaces and shell metacharacters survive into the launchlist" {
    local d="$FX/dir with space"
    mkdir "$d"
    cp "$FX"/a1-*.nii.gz "$FX"/t-*.nii.gz "$d/"
    cp "$FX/a1-seg.nii.gz" "$d/we\$ird (1) 'q'.nii.gz"
    write_csv src.csv "id, mri, brainmask, seg" \
        "a1, a1-mri.nii.gz, a1-mask.nii.gz, we\$ird (1) 'q'.nii.gz"
    write_csv tgt.csv "id, mri, brainmask" "T1, t-mri.nii.gz, t-mask.nii.gz"
    mv "$FX/src.csv" "$FX/tgt.csv" "$d/"
    LL="$BATS_TEST_TMPDIR/launchlist.sh"
    run "$LAUNCHLIST_GEN" -src-description "$d/src.csv" -tgt-description "$d/tgt.csv" \
        -output-dir "$OUT" -launchlist "$LL"
    [ "$status" -eq 0 ]
    ll_words 1
    [ "$(ll_values -srcmri)" = "$d/a1-mri.nii.gz" ]
    [ "$(ll_values -srclabels)" = "seg:$d/we\$ird (1) 'q'.nii.gz" ]
    # and maper accepts what was generated
    run bash "$LL"
    [ "$status" -eq 0 ]
    [ -s "$OUT/T1/a1-T1/seg/seg.nii.gz" ]
}

@test "absolute paths in a description are used as they are" {
    write_csv tgt.csv "id, mri, brainmask" "T1, $FX/t-mri.nii.gz, t-mask.nii.gz"
    run_llgen
    [ "$status" -eq 0 ]
    ll_words 1
    [ "$(ll_values -tgtmri)" = "$FX/t-mri.nii.gz" ]
    [ "$(ll_values -tgtmask)" = "$FX/t-mask.nii.gz" ]
}

@test "descriptions with Windows line endings work" {
    printf 'id, mri, brainmask, seg\r\na1, a1-mri.nii.gz, a1-mask.nii.gz, a1-seg.nii.gz\r\n' > "$FX/src.csv"
    printf 'id, mri, brainmask\r\nT1, t-mri.nii.gz, t-mask.nii.gz\r\n' > "$FX/tgt.csv"
    run_llgen
    [ "$status" -eq 0 ]
    ll_words 1
    [ "$(ll_values -srclabels)" = "seg:$FX/a1-seg.nii.gz" ]
    [ "$(ll_values -tgtmask)" = "$FX/t-mask.nii.gz" ]
}

@test "comments and blank lines are ignored in both descriptions, before the header and between rows" {
    write_csv src.csv "# atlases" "" "id, mri, brainmask, seg" \
        "a1, a1-mri.nii.gz, a1-mask.nii.gz, a1-seg.nii.gz" "" "  # a2 is out" \
        "a3, a3-mri.nii.gz, a3-mask.nii.gz, a3-seg.nii.gz"
    write_csv tgt.csv "# targets" "" "id, mri, brainmask" "" "# T0 is out" \
        "T1, t-mri.nii.gz, t-mask.nii.gz"
    run_llgen
    [ "$status" -eq 0 ]
    [ "$(ll_count)" -eq 2 ]
}

@test "spaces around fields are removed" {
    write_csv tgt.csv "  id ,mri  ,   brainmask" "  T1  ,   t-mri.nii.gz,t-mask.nii.gz   "
    run_llgen
    [ "$status" -eq 0 ]
    ll_words 1
    [ "$(ll_values -tgtid)" = T1 ]
    [ "$(ll_values -tgtmri)" = "$FX/t-mri.nii.gz" ]
}

@test "a row with a different number of fields than the header is an error that names file and line" {
    write_csv src.csv "id, mri, brainmask, seg" \
        "a1, a1-mri.nii.gz, a1-mask.nii.gz, a1-seg.nii.gz" \
        "a2, a2-mri.nii.gz, a2-mask.nii.gz"
    run_llgen
    [ "$status" -ne 0 ]
    [[ $output == *"src.csv:3"*"4 fields"*"found 3"* ]]
}

@test "duplicate ids are rejected, for sources and for targets" {
    write_csv src.csv "id, mri, brainmask, seg" \
        "a1, a1-mri.nii.gz, a1-mask.nii.gz, a1-seg.nii.gz" \
        "a1, a2-mri.nii.gz, a2-mask.nii.gz, a2-seg.nii.gz"
    run_llgen
    [ "$status" -ne 0 ]
    [[ $output == *"duplicate id a1"* ]]
    default_csvs
    write_csv tgt.csv "id, mri, brainmask" "T1, t-mri.nii.gz, t-mask.nii.gz" "T1, t-mri.nii.gz, t-mask.nii.gz"
    run_llgen
    [ "$status" -ne 0 ]
    [[ $output == *"duplicate id T1"* ]]
}

@test "a description without an id column is rejected" {
    write_csv tgt.csv "name, mri, brainmask" "T1, t-mri.nii.gz, t-mask.nii.gz"
    run_llgen
    [ "$status" -ne 0 ]
    [[ $output == *"tgt.csv"*"id column"* ]]
}

@test "a description with neither mri nor onepad column is rejected" {
    write_csv src.csv "id, brainmask, seg" "a1, a1-mask.nii.gz, a1-seg.nii.gz"
    run_llgen
    [ "$status" -ne 0 ]
    [[ $output == *"src.csv"*"mri or onepad"* ]]
}

@test "a repeated column name is rejected" {
    write_csv tgt.csv "id, mri, mri" "T1, t-mri.nii.gz, t-mri.nii.gz"
    run_llgen
    [ "$status" -ne 0 ]
    [[ $output == *"column mri"*"more than once"* ]]
}

@test "a label set name that maper could not parse is rejected" {
    write_csv src.csv "id, mri, a:b" "a1, a1-mri.nii.gz, a1-seg.nii.gz"
    run_llgen
    [ "$status" -ne 0 ]
    [[ $output == *"a:b"* ]]
}

@test "a row with an empty id is rejected" {
    write_csv tgt.csv "id, mri, brainmask" ", t-mri.nii.gz, t-mask.nii.gz"
    run_llgen
    [ "$status" -ne 0 ]
    [[ $output == *"tgt.csv:2"*"empty id"* ]]
}

@test "a description without any row is rejected" {
    write_csv tgt.csv "id, mri, brainmask"
    run_llgen
    [ "$status" -ne 0 ]
    [[ $output == *"tgt.csv"*"no rows"* ]]
}

@test "files named in the descriptions must exist; all missing ones are listed" {
    write_csv src.csv "id, mri, brainmask, seg" \
        "a1, a1-mri.nii.gz, a1-mask.nii.gz, a1-seg.nii.gz" \
        "a2, MISSING-mri.nii.gz, a2-mask.nii.gz, MISSING-seg.nii.gz"
    write_csv tgt.csv "id, mri, brainmask" "T1, t-mri.nii.gz, NO-mask.nii.gz"
    run_llgen
    [ "$status" -ne 0 ]
    [[ $output == *"a2"*"mri"*"MISSING-mri.nii.gz"* ]]
    [[ $output == *"a2"*"seg"*"MISSING-seg.nii.gz"* ]]
    [[ $output == *"T1"*"brainmask"*"NO-mask.nii.gz"* ]]
}

@test "a failed validation leaves an existing launchlist untouched" {
    run_llgen
    [ "$status" -eq 0 ]
    local before; before=$(cat "$LL")
    write_csv tgt.csv "id, mri, brainmask" "T1, MISSING.nii.gz, t-mask.nii.gz"
    run_llgen
    [ "$status" -ne 0 ]
    [ "$(cat "$LL")" = "$before" ]
}

@test "-fastmode skips the check that the named files exist" {
    write_csv tgt.csv "id, mri, brainmask" "T1, MISSING.nii.gz, t-mask.nii.gz"
    run_llgen -fastmode
    [ "$status" -eq 0 ]
    ll_words 1
    [ "$(ll_values -tgtmri)" = "$FX/MISSING.nii.gz" ]
}

@test "the same input gives the same launchlist" {
    write_csv src.csv "id, mri, brainmask, s1, s2, s3" \
        "a1, a1-mri.nii.gz, a1-mask.nii.gz, a1-seg.nii.gz, a1-seg2.nii.gz, a1-op.nii.gz" \
        "a2, a2-mri.nii.gz, a2-mask.nii.gz, a2-seg.nii.gz, a2-seg2.nii.gz, a2-op.nii.gz"
    run_llgen
    cp "$LL" "$BATS_TEST_TMPDIR/first.sh"
    run_llgen
    cmp "$LL" "$BATS_TEST_TMPDIR/first.sh"
}

# --- -loocv with targets that are not among the sources -------------------------

@test "-loocv: -atlasn is per target; only a target that is itself an atlas loses one" {
    write_csv tgt.csv "id, mri, brainmask" \
        "a2, a2-mri.nii.gz, a2-mask.nii.gz" \
        "T1, t-mri.nii.gz, t-mask.nii.gz"
    run_llgen -loocv
    [ "$status" -eq 0 ]
    [ "$(ll_count)" -eq 5 ]          # a2 against a1, a3; T1 against a1, a2, a3
    local n
    for n in 1 2 ; do
        ll_words "$n"
        [ "$(ll_values -tgtid)" = a2 ]
        [ "$(ll_values -atlasn)" = 2 ]
    done
    for n in 3 4 5 ; do
        ll_words "$n"
        [ "$(ll_values -tgtid)" = T1 ]
        [ "$(ll_values -atlasn)" = 3 ]
    done
}

@test "without -loocv every target gets all atlases and the same -atlasn" {
    write_csv tgt.csv "id, mri, brainmask" \
        "a2, a2-mri.nii.gz, a2-mask.nii.gz" \
        "T1, t-mri.nii.gz, t-mask.nii.gz"
    run_llgen
    [ "$status" -eq 0 ]
    [ "$(ll_count)" -eq 6 ]
    local n
    for n in 1 2 3 4 5 6 ; do
        ll_words "$n"
        [ "$(ll_values -atlasn)" = 3 ]
    done
}

@test "-loocv with nothing left to pair warns about the empty launchlist" {
    write_csv src.csv "id, mri, brainmask, seg" "a1, a1-mri.nii.gz, a1-mask.nii.gz, a1-seg.nii.gz"
    write_csv tgt.csv "id, mri, brainmask" "a1, a1-mri.nii.gz, a1-mask.nii.gz"
    run_llgen -loocv
    [ "$status" -eq 0 ]
    [ "$(ll_count)" -eq 0 ]
    [[ $output == *"no source/target pairs"* ]]
}
