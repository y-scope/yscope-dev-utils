#!/usr/bin/env bash

# Small shell helpers shared by the docker libraries in this directory.

if [[ "${_DOCKER_UTILS_SH_LOADED:-}" == "1" ]]; then
    return 0
fi
readonly _DOCKER_UTILS_SH_LOADED=1

# Appends values to the caller's array, which is passed by name.
#
# The obvious implementation is a bash nameref (`local -n`), but that needs bash
# 4.3 and macOS still ships bash 3.2 as /bin/bash -- and a macOS laptop behind a
# corporate TLS gateway is exactly who reaches for these libraries. So the
# append goes through `eval` instead, with every value rendered by `printf %q`.
# That is what %q is for: it emits a token the shell parses back to the original
# byte-for-byte, so values containing spaces, quotes, `$`, or newlines -- proxy
# and mirror URLs routinely have them -- arrive intact.
#
# Args: <array-name> [value...]
docker_utils_append_args() {
    if (( $# < 1 )) || [[ -z "$1" ]]; then
        echo >&2 "ERROR: docker_utils_append_args requires an array name"
        return 2
    fi
    # Only ever an identifier chosen by the calling library, never user data,
    # but validate anyway since the name is what gets evaluated.
    if [[ ! "$1" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
        echo >&2 "ERROR: not a valid array name: $1"
        return 2
    fi

    local array_name="$1"
    shift
    if (( $# == 0 )); then
        return 0
    fi

    eval "${array_name}+=($(printf '%q ' "$@"))"
}

# Echoes the number of elements in the array named by <array-name>.
#
# Args: <array-name>
docker_utils_array_length() {
    if (( $# != 1 )) || [[ ! "$1" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
        echo >&2 "ERROR: docker_utils_array_length requires an array name"
        return 2
    fi
    eval "echo \"\${#$1[@]}\""
}
