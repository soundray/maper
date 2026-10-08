#!/usr/bin/env bats
# run-maper-example-generate.sh asks for a "y" and writes the script that runs the example.

load test_helper

setup() { setup_common ; cd "$BATS_TEST_TMPDIR" ; }

@test "run-maper-example-generate.sh writes run-maper-example.sh when the answer is y" {
    run bash -c 'echo y | "$1"' _ "$MAPER_ROOT/run-maper-example-generate.sh"
    [ "$status" -eq 0 ]
    [[ $output == *"Script 'run-maper-example.sh' written."* ]]
    [ -s run-maper-example.sh ]
    bash -n run-maper-example.sh
    grep -q '^launchlist-gen' run-maper-example.sh
}

@test "run-maper-example-generate.sh writes nothing for any other answer" {
    run bash -c 'echo n | "$1"' _ "$MAPER_ROOT/run-maper-example-generate.sh"
    [ "$status" -eq 0 ]
    [[ $output == *"Not continuing"* ]]
    [ ! -e run-maper-example.sh ]
}
