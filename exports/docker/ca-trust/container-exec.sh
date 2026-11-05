#!/usr/bin/env bash

# Sources container.sh, then execs the given command with the CA trust
# environment in place.
#
# Exists for `docker build`: a Dockerfile RUN is executed by /bin/sh, while
# container.sh needs bash (BASH_SOURCE, [[ ]]). Without this wrapper every RUN
# would have to spell out `bash -c '. .../container.sh && <cmd>'`, which is
# unwritable when <cmd> itself contains single-quoted arguments (sed scripts,
# for instance). It's also usable as a `docker run --entrypoint`.
#
# Usage: container-exec.sh <cmd> [args...]

set -o errexit
set -o nounset
set -o pipefail

if (( $# == 0 )); then
    echo >&2 "ERROR: container-exec.sh requires a command to run"
    exit 2
fi

_ca_trust_exec_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

# container.sh signals failure with `return 1` when sourced, which `errexit`
# doesn't catch across a source; check explicitly.
# shellcheck source=exports/docker/ca-trust/container.sh
if ! source "${_ca_trust_exec_dir}/container.sh"; then
    echo >&2 "ERROR: failed to configure CA trust"
    exit 1
fi

unset _ca_trust_exec_dir

exec "$@"
