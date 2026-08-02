#!/usr/bin/env bash

# Host-side helpers for assembling a `docker build` command.
#
# Each function appends flags to a caller-owned bash array, passed by name.
# docker_utils_append_args does the appending; see utils.sh for why it's written
# the way it is.

if [[ "${_DOCKER_BUILD_HOST_SH_LOADED:-}" == "1" ]]; then
    return 0
fi
readonly _DOCKER_BUILD_HOST_SH_LOADED=1

# shellcheck source=exports/docker/utils.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." &>/dev/null && pwd)/utils.sh"

# Proxy variables forwarded into the build, in both spellings because tools
# disagree about which they read.
readonly _DOCKER_BUILD_PROXY_VARS=(
    HTTP_PROXY http_proxy
    HTTPS_PROXY https_proxy
    ALL_PROXY all_proxy
    NO_PROXY no_proxy
)

# Echoes <value> with any URL credentials replaced by <replacement> (removed when
# that is omitted).
#
# Proxy URLs and git remotes both carry credentials in practice --
# `http://user:token@proxy.corp:8080`, `https://user:token@github.com/org/repo` --
# and this library would otherwise copy them into an image label or a build log,
# where they outlive the build.
#
# Args: <value> [replacement]
_docker_build_replace_userinfo() {
    local value="$1" replacement="${2:-}"
    # Greedy `.*://` so the last scheme wins, and `[^/@]*` keeps the match inside
    # the authority: an `@` later in a path is not credentials.
    if [[ "${value}" =~ ^(.*://)[^/@]*@(.*)$ ]]; then
        printf '%s%s%s' "${BASH_REMATCH[1]}" "${replacement}" "${BASH_REMATCH[2]}"
        return 0
    fi
    printf '%s' "${value}"
}

# Appends `--build-arg` flags for any set proxy variables, and picks a network
# mode.
#
# A proxy on the host's loopback address is unreachable from the build
# container's default bridge network, so `--network host` is selected
# automatically in that case. DOCKER_NETWORK overrides the choice entirely.
#
# Args: <cmd-array-name>
docker_build_add_proxy_args() {
    if (( $# != 1 )) || [[ -z "$1" ]]; then
        echo >&2 "ERROR: docker_build_add_proxy_args requires a command array"
        return 2
    fi
    local cmd_name="$1"

    local has_loopback_proxy=false
    local var value
    for var in "${_DOCKER_BUILD_PROXY_VARS[@]}"; do
        value="${!var:-}"
        [[ -z "${value}" ]] && continue
        docker_utils_append_args "${cmd_name}" "--build-arg" "${var}=${value}"
        # Match the host after either the scheme or userinfo credentials, so
        # http://user:pass@127.0.0.1:8080 is recognized too. Also accept a bare
        # trailing host with no port or path.
        if [[ "${var}" != *NO_PROXY* && "${var}" != *no_proxy* ]] \
                && [[ "${value}" =~ (://|@)(localhost|127\.0\.0\.1|\[::1\])([:/]|$) ]]; then
            has_loopback_proxy=true
        fi
    done

    if [[ -n "${DOCKER_NETWORK:-}" ]]; then
        docker_utils_append_args "${cmd_name}" "--network" "${DOCKER_NETWORK}"
    elif [[ "${has_loopback_proxy}" == "true" ]]; then
        docker_utils_append_args "${cmd_name}" "--network" "host"
    fi
}

# Appends a `--build-arg` for each named environment variable that is set and
# non-empty. Lets consumers forward their own build knobs (package mirrors, for
# instance) without this library knowing their names.
#
# Args: <cmd-array-name> [var-name...]
docker_build_add_env_build_args() {
    if (( $# < 1 )) || [[ -z "$1" ]]; then
        echo >&2 "ERROR: docker_build_add_env_build_args requires a command array"
        return 2
    fi
    local cmd_name="$1"
    shift

    local var value
    for var in "$@"; do
        value="${!var:-}"
        [[ -n "${value}" ]] && docker_utils_append_args "${cmd_name}" \
            "--build-arg" "${var}=${value}"
    done
    # Explicit: the `&&` above leaves a nonzero status when the last variable is
    # unset, which would abort callers running under `errexit`.
    return 0
}

# Appends `--pull` unless DOCKER_PULL is "false", so builds refresh their base
# image by default.
#
# Args: <cmd-array-name>
docker_build_add_pull_arg() {
    if (( $# != 1 )) || [[ -z "$1" ]]; then
        echo >&2 "ERROR: docker_build_add_pull_arg requires a command array"
        return 2
    fi
    [[ "${DOCKER_PULL:-true}" != "false" ]] && docker_utils_append_args "$1" "--pull"
    return 0
}

# Appends OCI source-provenance labels derived from the git repo at <repo-dir>.
# A no-op outside a git work tree.
#
# Args: <cmd-array-name> <repo-dir>
docker_build_add_oci_labels() {
    if (( $# != 2 )) || [[ -z "$1" || -z "$2" ]]; then
        echo >&2 "ERROR: docker_build_add_oci_labels requires a command array and a repo directory"
        return 2
    fi
    local cmd_name="$1" repo_dir="$2"

    command -v git &>/dev/null || return 0
    git -C "${repo_dir}" rev-parse --is-inside-work-tree &>/dev/null || return 0

    local revision
    if revision="$(git -C "${repo_dir}" rev-parse HEAD 2>/dev/null)"; then
        docker_utils_append_args "${cmd_name}" \
            "--label" "org.opencontainers.image.revision=${revision}"
    fi

    local remote_url
    if remote_url="$(git -C "${repo_dir}" remote get-url origin 2>/dev/null)"; then
        # Credentials stripped: a label travels with the image to every registry
        # and `docker inspect` that ever sees it.
        remote_url="$(_docker_build_replace_userinfo "${remote_url}")"
        docker_utils_append_args "${cmd_name}" \
            "--label" "org.opencontainers.image.source=${remote_url}"
    fi
    return 0
}

# Echoes and runs the assembled command.
#
# Args: <cmd-array-name>
docker_build_run() {
    if (( $# != 1 )) || [[ -z "$1" ]]; then
        echo >&2 "ERROR: docker_build_run requires a command array"
        return 2
    fi
    local length
    length="$(docker_utils_array_length "$1")" || return 2
    if (( length == 0 )); then
        echo >&2 "ERROR: docker_build_run got an empty command array: $1"
        return 2
    fi

    if ! docker buildx version &>/dev/null; then
        echo >&2 "ERROR: docker buildx is required (Docker 23 or newer)."
        return 1
    fi

    # Copied out by name, since the array belongs to the caller.
    local cmd
    eval "cmd=(\"\${$1[@]}\")"

    # The echoed line is for humans and CI logs, so proxy credentials are masked
    # there. The command itself runs with the values untouched.
    local arg printable=()
    for arg in "${cmd[@]}"; do
        printable+=("$(_docker_build_replace_userinfo "${arg}" "***@")")
    done
    echo "Running: ${printable[*]}"

    "${cmd[@]}"
}

# The common composition: proxy args, forwarded build args, pull, labels, run.
# CA trust is deliberately not included -- it's opt-in and the consumer calls
# ca_trust_add_build_args itself.
#
# Args: <cmd-array-name> <repo-dir> [build-arg-var-name...]
docker_build_finalize() {
    if (( $# < 2 )) || [[ -z "$1" || -z "$2" ]]; then
        echo >&2 "ERROR: docker_build_finalize requires a command array and a repo directory"
        return 2
    fi
    local cmd_name="$1" repo_dir="$2"
    shift 2

    docker_build_add_proxy_args "${cmd_name}" || return
    docker_build_add_env_build_args "${cmd_name}" "$@" || return
    docker_build_add_pull_arg "${cmd_name}" || return
    docker_build_add_oci_labels "${cmd_name}" "${repo_dir}" || return
    docker_build_run "${cmd_name}"
}
