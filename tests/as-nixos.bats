#!/usr/bin/env bats
# tests/as-nixos.sh runs a command as on NixOS: /usr/bin and /bin hold only env and sh.
# It needs mount namespaces, and tools that do not live in /usr/bin or /bin (a nix-shell
# provides them); where that is not so, these tests are skipped.

load test_helper

setup() {
    setup_common
    AS_NIXOS="$MAPER_ROOT/tests/as-nixos.sh"
    case $(type -P bash) in
        /bin/*|/usr/bin/*) skip "bash is in /usr/bin here: take the tools from nix-shell or nix develop" ;;
    esac
    if ! unshare --mount true 2>/dev/null && ! unshare --user --map-root-user --mount true 2>/dev/null ; then
        skip "no mount namespaces here"
    fi
}

@test "as-nixos.sh: /usr/bin and /bin hold nothing but env and sh" {
    run "$AS_NIXOS" bash -c '
        for f in /usr/bin/* /bin/* ; do
            case ${f##*/} in env|sh) ;; *) echo "unexpected: $f" ;; esac
        done
        [ -e /usr/bin/env ] && [ -e /bin/sh ] && echo both-there'
    [ "$status" -eq 0 ]
    [[ $output == *both-there ]]
    [[ $output != *unexpected* ]]
}

@test "as-nixos.sh: a PATH of /usr/bin:/bin has no bash in it, as on NixOS" {
    # what broke the launchlist-gen test: "#!/usr/bin/env bash" finds no bash there
    run "$AS_NIXOS" env PATH=/usr/bin:/bin env bash -c true
    [ "$status" -eq 127 ]
    [[ $output == *bash* ]]               # env says that it cannot find bash
}

@test "as-nixos.sh: arguments and the exit status of the command are passed on" {
    run "$AS_NIXOS" bash -c 'printf "%s|" "$@"' as-nixos "a b" c
    [ "$status" -eq 0 ]
    [ "${lines[-1]}" = "a b|c|" ]         # (the notice of the helper is on standard error, too)
    run "$AS_NIXOS" bash -c 'exit 7'
    [ "$status" -eq 7 ]
}

@test "as-nixos.sh: the rest of the system is as it was, outside and afterwards" {
    local before after
    before=$(echo /usr/bin/* /bin/* | md5sum)
    "$AS_NIXOS" bash -c true
    after=$(echo /usr/bin/* /bin/* | md5sum)
    [ "$before" = "$after" ]
}

@test "as-nixos.sh: leaves no temporary directory behind" {
    "$AS_NIXOS" bash -c true
    [ -z "$(ls -A "$TMPDIR" | grep '^as-nixos' || true)" ]
}

@test "as-nixos.sh: the environment of the command is kept" {
    SOME_SETTING=kept run "$AS_NIXOS" bash -c 'echo "$SOME_SETTING"'
    [ "${lines[-1]}" = "kept" ]
}

@test "as-nixos.sh: without a command it says how it is used, and fails" {
    run "$AS_NIXOS"
    [ "$status" -ne 0 ]
    [[ $output == *"Usage"* ]]
}
