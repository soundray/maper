#!/usr/bin/env bash
# Run a command as on NixOS: /usr/bin holds only "env" and /bin only "sh" (here both
# directories hold both), so that a tool cannot be found by its usual place on other
# systems, and "#!/usr/bin/env bash" is the only way to start a script.
#
# Usage: tests/as-nixos.sh COMMAND [ARGUMENT...]
#
# For instance, from a nix-shell that provides the tools of the tests (see the README):
#
#     tests/as-nixos.sh bats tests/
#
# Only the two directories are changed, and only for the command: the mount is made in a
# namespace of its own and goes away with it. This needs Linux and the command unshare,
# and either root or a kernel that allows user namespaces. The tools (the command, and
# bash) must not be in /usr/bin or /bin, as they would be hidden; a nix-shell or nix
# develop puts them elsewhere. On a system that already looks like NixOS the command is
# run as it is.

set -euo pipefail

die() { echo "as-nixos.sh: $*" >&2 ; exit 1 ; }

usage() {
    # the comment at the top of this file
    sed -n '2,/^[^#]/{/^[^#]/!s/^# \{0,1\}//p}' "$0"
}

if [[ $# -eq 0 ]] ; then usage >&2 ; exit 2 ; fi
if [[ $1 == -h || $1 == --help ]] ; then usage ; exit 0 ; fi

[[ $(uname -s) == Linux ]] || die "needs Linux (mount namespaces)"

# Already so? Then there is nothing to do.
shopt -s nullglob
entries=(/usr/bin/*)
if [[ ${#entries[@]} -eq 1 && ${entries[0]} == /usr/bin/env ]] ; then exec "$@" ; fi

command -v unshare > /dev/null || die "unshare (util-linux) not found"

for tool in "$1" bash ; do
    path=$(type -P "$tool") || die "$tool: not found"
    case $path in
        /usr/bin/env | /bin/sh) ;;
        /usr/bin/* | /bin/*)
            die "$tool is $path, which would be hidden: take the tools from a nix-shell or nix develop (see the README)" ;;
    esac
done

fake=$(mktemp -d "${TMPDIR:-/tmp}/as-nixos.XXXXXX")
trap 'rm -rf "$fake"' EXIT
cp -L "$(type -P env)" "$fake/env"
cp -L "$(type -P sh)" "$fake/sh"

if [[ $(id -u) -eq 0 ]] ; then
    namespace=(unshare --mount)
else
    namespace=(unshare --user --map-root-user --mount)
fi

echo "as-nixos.sh: /usr/bin and /bin now hold only: env sh" >&2

status=0
# shellcheck disable=SC2016  # in single quotes on purpose: the inner shell expands them
"${namespace[@]}" bash -c '
    fake=$1 ; shift
    mount --bind "$fake" /usr/bin
    if [ -d /bin ] && [ ! -L /bin ] ; then mount --bind "$fake" /bin ; fi
    exec "$@"' as-nixos "$fake" "$@" || status=$?
exit "$status"
