#!/usr/bin/env bash

# Container-side configuration for CA trust. Source it after setting
# CA_TRUST_DIR to a writable mount of the staged trust directory, which must
# contain ca-bundle.pem. Set CA_TRUST_JVM=1 as well if the build runs on a JVM
# (Maven, Gradle, ...) that needs its trust store configured: a Java PKCS#12
# trust store is then generated here, inside the container, from the PEM
# bundle using the container's own JDK (keytool) -- no separate generator
# container or host JDK is required -- and written back to CA_TRUST_DIR
# alongside the bundle.
#
# Persistence contract: CA_TRUST_DIR must be a writable host bind-mount (or
# tmpfs), not the container's writable overlay. A file on the overlay is retained
# by `docker commit`; a bind mount is not part of any committed image. This
# script refuses to write to the overlay.

if [[ -z "${CA_TRUST_DIR:-}" ]]; then
    return 0 2>/dev/null || exit 0
fi

_ca_trust_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
HOST_CA_BUNDLE="${CA_TRUST_DIR}/ca-bundle.pem"

if [[ -s "${HOST_CA_BUNDLE:-}" ]]; then
    export CURL_CA_BUNDLE="${HOST_CA_BUNDLE}"
    export GIT_SSL_CAINFO="${HOST_CA_BUNDLE}"
    export PIP_CERT="${HOST_CA_BUNDLE}"
    export REQUESTS_CA_BUNDLE="${HOST_CA_BUNDLE}"
    export SSL_CERT_FILE="${HOST_CA_BUNDLE}"
fi

# Generate a Java PKCS#12 trust store in-container from the staged PEM bundle and
# point Maven at it. Opt-in via CA_TRUST_JVM=1, since not every caller of this
# library runs on a JVM. Also skipped when the bundle is empty or keytool is
# unavailable, so CI builds without a trust directory and PEM-only staging
# (empty bundle) are unaffected.
if [[ -n "${CA_TRUST_JVM:-}" ]] && [[ -s "${HOST_CA_BUNDLE:-}" ]] && command -v keytool &>/dev/null; then
    if ! mkdir -p "${CA_TRUST_DIR}"; then
        echo >&2 "ERROR: cannot create Java trust store dir: ${CA_TRUST_DIR}"
        return 1 2>/dev/null || exit 1
    fi

    # Refuse to write to the container's writable overlay: a file there is
    # retained by `docker commit`, violating the no-persistence invariant. A
    # bind mount or tmpfs has its own mount target; the root overlay resolves
    # to "/". Warn (but proceed) if findmnt is unavailable to check.
    if command -v findmnt &>/dev/null; then
        _ca_trust_mount_target="$(findmnt -T "${CA_TRUST_DIR}" -o TARGET -n 2>/dev/null || true)"
        if [[ -z "${_ca_trust_mount_target}" || "${_ca_trust_mount_target}" == "/" ]]; then
            echo >&2 "ERROR: CA_TRUST_DIR (${CA_TRUST_DIR}) is on the container's writable overlay,"
            echo >&2 "       which docker commit would retain. Mount a writable host directory or tmpfs there."
            return 1 2>/dev/null || exit 1
        fi
    else
        echo >&2 "WARNING: findmnt unavailable; cannot verify CA_TRUST_DIR is off the overlay."
    fi

    HOST_CA_JAVA_TRUST_STORE="${CA_TRUST_DIR}/truststore.p12"
    if ! bash "${_ca_trust_dir}/generators/java-pkcs12/generate.sh" \
            "${HOST_CA_BUNDLE}" "${HOST_CA_JAVA_TRUST_STORE}"; then
        echo >&2 "ERROR: failed to generate Java PKCS#12 trust store from ${HOST_CA_BUNDLE}"
        return 1 2>/dev/null || exit 1
    fi

    # Preserve any Maven options supplied by the caller.
    _host_ca_maven_opts="${MAVEN_OPTS:-}"
    [[ -n "${_host_ca_maven_opts}" ]] && _host_ca_maven_opts="${_host_ca_maven_opts} "
    _host_ca_maven_opts="${_host_ca_maven_opts}-Djavax.net.ssl.trustStore=${HOST_CA_JAVA_TRUST_STORE}"
    _host_ca_maven_opts="${_host_ca_maven_opts} -Djavax.net.ssl.trustStoreType=PKCS12"
    # The store contains only public certificates; this is an integrity password, not a secret.
    _host_ca_maven_opts="${_host_ca_maven_opts} -Djavax.net.ssl.trustStorePassword=changeit"
    export MAVEN_OPTS="${_host_ca_maven_opts}"
    unset _host_ca_maven_opts _ca_trust_mount_target
fi

unset _ca_trust_dir
