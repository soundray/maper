#!/usr/bin/env bash
# Lint gate: shellcheck must find no error-level problem in any shell file of
# the repository. Run it from anywhere: tests/lint.sh
#
# (The .bats files use syntax shellcheck cannot read; they are exercised by bats.)
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

command -v shellcheck >/dev/null || { echo "lint.sh: shellcheck not found" >&2 ; exit 1 ; }

shellcheck --severity=error -s bash \
    maper launchlist-gen generic-functions build-sif ./*.sh \
    tests/stubs/* tests/test_helper.bash tests/lint.sh
echo "shellcheck: no error-level findings"
