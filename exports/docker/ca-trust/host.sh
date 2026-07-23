#!/usr/bin/env bash

# Host-side CA discovery and staging shared by Docker build and run workflows.

if [[ "${_CA_TRUST_HOST_SH_LOADED:-}" == "1" ]]; then
    return 0
fi
readonly _CA_TRUST_HOST_SH_LOADED=1

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
stage_host_ca_bundle() {
    if (( $# != 1 )) || [[ -z "$1" ]]; then
        echo >&2 "ERROR: stage_host_ca_bundle requires a trust directory"
        return 2
    fi
    local trust_dir="$1"
    if [[ -L "${trust_dir}" || ( -e "${trust_dir}" && ! -d "${trust_dir}" ) ]]; then
        echo >&2 "ERROR: stage_host_ca_bundle target is not a directory: ${trust_dir}"
        return 1
    fi
    if ! mkdir -p "${trust_dir}"; then
        echo >&2 "ERROR: failed to create trust directory: ${trust_dir}"
        return 1
    fi
    trust_dir="$(cd "${trust_dir}" &>/dev/null && pwd)" || return
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
