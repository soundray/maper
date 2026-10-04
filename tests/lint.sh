#!/usr/bin/env bash
# Lint gate: shellcheck must find no warning or error, and no unquoted variable
# (SC2086), in any shell file of the repository. Run it from anywhere: tests/lint.sh
#
# A finding that is right about the code but wrong about the intent is silenced
# on the line, with a reason:  # shellcheck disable=SCxxxx  # why
#
# (The .bats files use syntax shellcheck cannot read; they are exercised by bats.)
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

command -v shellcheck >/dev/null || { echo "lint.sh: shellcheck not found" >&2 ; exit 1 ; }

files=(
    maper launchlist-gen generic-functions build-sif ./*.sh
    tests/stubs/* tests/test_helper.bash tests/lint.sh
)

shellcheck --severity=warning -s bash "${files[@]}"
# Unquoted variables are below the warning level but always wrong in these scripts;
# where word splitting is wanted, use an array
shellcheck --severity=style --include=SC2086 -s bash "${files[@]}"
echo "shellcheck: no warnings or errors, no unquoted variables"
