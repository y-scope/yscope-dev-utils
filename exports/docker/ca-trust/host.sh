#!/usr/bin/env bash

# Host-side CA discovery and staging shared by Docker build and run workflows.

if [[ "${_CA_TRUST_HOST_SH_LOADED:-}" == "1" ]]; then
    return 0
fi
readonly _CA_TRUST_HOST_SH_LOADED=1

# shellcheck source=exports/docker/utils.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." &>/dev/null && pwd)/utils.sh"

# Conventional staged filename for the host CA bundle. container.sh reads it
# from CA_TRUST_DIR by this name (HOST_CA_BUNDLE) and generates the Java
# PKCS#12 trust store in-container from it.
readonly CA_TRUST_BUNDLE_FILENAME="ca-bundle.pem"

# In-container mount point for the staged trust directory. Callers bind-mount
# the staging directory here (writable) and pass it as CA_TRUST_DIR so
# container.sh consumes the staged PEM bundle and writes the generated Java
# PKCS#12 trust store back into it. Kept in host.sh so the path is defined
# once on the host side rather than hardcoded by each caller.
readonly CA_TRUST_CONTAINER_DIR="/run/ca-trust"

# Name of the Docker named build context used to carry the staging directory
# into `docker build`. A Dockerfile can't read these shell constants, so the
# name is also spelled out in each consuming Dockerfile's
# `--mount=type=bind,from=...`; keep the two in sync.
#
# Consumers must declare `FROM scratch AS ca_trust` so the mount resolves to an
# empty directory when no context is passed. That is what makes CA trust opt-in:
# an unprovided named context is fatal (BuildKit tries to pull it as an image),
# while an empty default lets untrusted-network-free builds and CI run with no
# CA configuration at all.
readonly CA_TRUST_BUILD_CONTEXT_NAME="ca_trust"

# Copies <src> to <dest>, dropping any certificate whose validity period has
# already ended. A stale corporate CA bundle otherwise gets propagated
# verbatim into CURL_CA_BUNDLE, where OpenSSL (unlike macOS's SecureTransport)
# treats the file as the exclusive trust store: one expired cert anywhere in
# it is enough to break TLS verification for any download whose chain happens
# to rely on it, even though the destination server's own certificate is
# fine. Falls back to a plain copy if openssl isn't on the host, so this never
# becomes a new hard dependency.
#
# Args: <src> <dest>
_stage_ca_bundle_without_expired_certs() {
    local src="$1" dest="$2"
    if ! command -v openssl &>/dev/null; then
        cp "${src}" "${dest}"
        return
    fi

    local total=0 dropped=0
    local cert="" line
    : > "${dest}"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        cert+="${line}"$'\n'
        if [[ "${line}" == "-----END CERTIFICATE-----" ]]; then
            total=$((total + 1))
            if printf '%s' "${cert}" | openssl x509 -noout -checkend 0 &>/dev/null; then
                printf '%s' "${cert}" >> "${dest}"
            else
                dropped=$((dropped + 1))
            fi
            cert=""
        fi
    done < "${src}"

    if (( dropped > 0 )); then
        echo >&2 "==> Dropped ${dropped}/${total} expired certificate(s) from host CA bundle"
    fi
}

# Stages the host CA bundle at <trust-dir>/${CA_TRUST_BUNDLE_FILENAME} for a
# temporary Docker mount. Creates an empty file when the host has no CA bundle;
# returns nonzero only on an error.
#
# Args: <trust-dir>
ca_trust_stage_host_bundle() {
    if (( $# != 1 )) || [[ -z "$1" ]]; then
        echo >&2 "ERROR: ca_trust_stage_host_bundle requires a trust directory"
        return 2
    fi
    local trust_dir="$1"
    if [[ -L "${trust_dir}" || ( -e "${trust_dir}" && ! -d "${trust_dir}" ) ]]; then
        echo >&2 "ERROR: ca_trust_stage_host_bundle target is not a directory: ${trust_dir}"
        return 1
    fi
    if ! mkdir -p "${trust_dir}"; then
        echo >&2 "ERROR: failed to create trust directory: ${trust_dir}"
        return 1
    fi
    if ! trust_dir="$(cd "${trust_dir}" &>/dev/null && pwd)"; then
        echo >&2 "ERROR: failed to resolve trust directory: $1"
        return 1
    fi
    local dest="${trust_dir}/${CA_TRUST_BUNDLE_FILENAME}"
    if [[ -L "${dest}" || ( -e "${dest}" && ! -f "${dest}" ) ]]; then
        echo >&2 "ERROR: host CA bundle destination is not a regular file: ${dest}"
        return 1
    fi
    local source_path=""
    local candidates=()

    if [[ -n "${SSL_CERT_FILE:-}" ]]; then
        if [[ ! -f "${SSL_CERT_FILE}" || ! -s "${SSL_CERT_FILE}" ]]; then
            echo >&2 "ERROR: SSL_CERT_FILE is not a nonempty regular file: ${SSL_CERT_FILE}"
            return 1
        fi
        candidates=("${SSL_CERT_FILE}")
    elif [[ -n "${CA_TRUST_BUNDLE_SEARCH_PATHS:-}" ]]; then
        # Colon-separated override for the default search list. Exists so the
        # "no host bundle found" branch below is reachable in tests: every Linux
        # CI runner has a bundle at one of the default locations.
        IFS=':' read -r -a candidates <<< "${CA_TRUST_BUNDLE_SEARCH_PATHS}"
    else
        candidates=(
            /etc/ssl/certs/ca-certificates.crt
            /etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem
            /etc/pki/tls/certs/ca-bundle.crt
            /etc/ssl/ca-bundle.pem
            /etc/pki/tls/cacert.pem
            /etc/ssl/cert.pem
        )
    fi

    local candidate
    for candidate in "${candidates[@]}"; do
        if [[ -f "${candidate}" && -s "${candidate}" ]]; then
            source_path="${candidate}"
            break
        fi
    done

    if [[ -n "${source_path}" && -e "${dest}" && "${source_path}" -ef "${dest}" ]]; then
        echo >&2 "ERROR: host CA bundle source and destination must differ: ${dest}"
        return 1
    fi

    local staged_bundle
    if ! staged_bundle="$(mktemp "${trust_dir}/.ca-bundle.XXXXXX")"; then
        echo >&2 "ERROR: failed to create temporary host CA bundle in: ${trust_dir}"
        return 1
    fi
    if [[ -n "${source_path}" ]]; then
        echo >&2 "==> Staging host CA bundle: ${source_path} -> ${dest}"
        if ! _stage_ca_bundle_without_expired_certs "${source_path}" "${staged_bundle}"; then
            rm -f "${staged_bundle}"
            echo >&2 "ERROR: failed to stage host CA bundle: ${source_path}"
            return 1
        fi
    else
        echo >&2 "==> No host CA bundle found; continuing without host CA context."
    fi

    # BuildKit and runtime containers consume the staged bundle read-only.
    if ! chmod 0444 "${staged_bundle}"; then
        rm -f "${staged_bundle}"
        echo >&2 "ERROR: failed to set host CA bundle permissions: ${dest}"
        return 1
    fi
    if ! mv -f "${staged_bundle}" "${dest}"; then
        rm -f "${staged_bundle}"
        echo >&2 "ERROR: failed to replace host CA bundle: ${dest}"
        return 1
    fi
}

# Stages the host CA bundle and fails if it produced nothing usable.
#
# `ca_trust_stage_host_bundle` deliberately tolerates an empty bundle: a build
# with no host CA context is normal. A caller that explicitly asked for CA trust
# is in the opposite position -- finding nothing is an error, not a default -- so
# every such caller pairs the staging call with the same check. This is that
# pair, so the check can't drift between them.
#
# Args: <trust-dir>
ca_trust_stage_or_fail() {
    if (( $# != 1 )) || [[ -z "$1" ]]; then
        echo >&2 "ERROR: ca_trust_stage_or_fail requires a trust directory"
        return 2
    fi
    local trust_dir="$1"

    ca_trust_stage_host_bundle "${trust_dir}" || return 1

    local staged="${trust_dir}/${CA_TRUST_BUNDLE_FILENAME}"
    if [[ ! -f "${staged}" || ! -r "${staged}" || ! -s "${staged}" ]]; then
        echo >&2 "ERROR: no usable host CA bundle was found."
        echo >&2 "  Set SSL_CERT_FILE to your CA bundle, or don't ask for CA trust."
        return 1
    fi
}

# Copies this library into <trust-dir> so a single named build context carries
# both the staged bundle and the scripts that consume it. `docker build` has no
# bind mounts, and a Dockerfile can only COPY from its own build context — which
# for most consumers doesn't include this submodule.
#
# The whole directory is copied, including generators/, so container.sh's JVM
# branch keeps working for build-time consumers that opt into it.
#
# Args: <trust-dir>
ca_trust_stage_build_context() {
    if (( $# != 1 )) || [[ -z "$1" ]]; then
        echo >&2 "ERROR: ca_trust_stage_build_context requires a trust directory"
        return 2
    fi
    local trust_dir="$1"
    if [[ ! -d "${trust_dir}" ]]; then
        echo >&2 "ERROR: trust directory doesn't exist: ${trust_dir}"
        return 1
    fi

    local lib_dir
    lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)" || return 1

    local entry
    for entry in "${lib_dir}"/*; do
        # Skip host.sh: it's the caller's half and has no use in the container.
        [[ "$(basename "${entry}")" == "host.sh" ]] && continue
        if ! cp -R "${entry}" "${trust_dir}/"; then
            echo >&2 "ERROR: failed to stage ca-trust library into: ${trust_dir}"
            return 1
        fi
    done
}

# Appends the `docker build` flags that expose <trust-dir> to the build.
#
# A named build context is used rather than a BuildKit secret because secrets
# are capped at 500KiB and corporate CA bundles can exceed that. Bind mounts of
# a build context are equally ephemeral: nothing lands in a layer or in
# `docker history`.
#
# Args: <cmd-array-name> <trust-dir>
ca_trust_add_build_args() {
    if (( $# != 2 )) || [[ -z "$1" || -z "$2" ]]; then
        echo >&2 "ERROR: ca_trust_add_build_args requires a command array and a trust directory"
        return 2
    fi
    docker_utils_append_args "$1" "--build-context" "${CA_TRUST_BUILD_CONTEXT_NAME}=$2"
}

# Appends the `docker run` flags that mount <trust-dir> into the container and
# point container.sh at it. Set CA_TRUST_JVM=1 in the environment beforehand to
# also forward the JVM trust-store opt-in and MAVEN_OPTS.
#
# Args: <cmd-array-name> <trust-dir>
ca_trust_add_run_args() {
    if (( $# != 2 )) || [[ -z "$1" || -z "$2" ]]; then
        echo >&2 "ERROR: ca_trust_add_run_args requires a command array and a trust directory"
        return 2
    fi
    docker_utils_append_args "$1" \
        "--mount" "type=bind,src=$2,dst=${CA_TRUST_CONTAINER_DIR}" \
        "--env" "CA_TRUST_DIR=${CA_TRUST_CONTAINER_DIR}"
    if [[ -n "${CA_TRUST_JVM:-}" ]]; then
        # Pass CA_TRUST_JVM by value: the pass-through `--env NAME` form is
        # resolved by the docker client when the command finally runs, and a
        # caller that set the variable only for this call -- `CA_TRUST_JVM=1
        # ca_trust_add_run_args ...` -- no longer has it set by then, silently
        # dropping JVM trust. MAVEN_OPTS stays pass-through on purpose: the
        # point is to forward whatever the host has at run time.
        docker_utils_append_args "$1" \
            "--env" "CA_TRUST_JVM=${CA_TRUST_JVM}" \
            "--env" "MAVEN_OPTS"
    fi
}
