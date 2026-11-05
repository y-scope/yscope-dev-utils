#!/usr/bin/env bash

# Generates a Java PKCS#12 trust store from a PEM CA bundle, merging the
# selected JDK's default certificates with the bundle's certificates.
#
# Runs inside the build container, which already provides a JDK (keytool +
# cacerts); no separate generator container or host JDK is required.

set -o errexit
set -o nounset
set -o pipefail

if (( $# != 2 )) || [[ -z "$1" || -z "$2" ]]; then
    echo >&2 "ERROR: generate.sh requires an input CA bundle and output path"
    exit 2
fi

input_bundle="$1"
output_trust_store="$2"
if [[ ! -f "${input_bundle}" || ! -r "${input_bundle}" ]]; then
    echo >&2 "ERROR: input CA bundle is not a readable regular file: ${input_bundle}"
    exit 1
fi
output_dir="$(dirname "${output_trust_store}")"
if [[ ! -d "${output_dir}" || ! -w "${output_dir}" ]]; then
    echo >&2 "ERROR: output directory is not writable: ${output_dir}"
    exit 1
fi
if [[ -e "${output_trust_store}" && ! -f "${output_trust_store}" ]]; then
    echo >&2 "ERROR: output path is not a regular file: ${output_trust_store}"
    exit 1
fi

# Integrity password for a store of public CA certificates; not a secret.
readonly STOREPASS=changeit

# Locate keytool and the JDK's default trust store. Match Java's trust-store
# lookup order: jssecacerts overrides cacerts.
java_home="${JAVA_HOME:-}"
if [[ -n "${java_home}" ]]; then
    keytool="${java_home}/bin/keytool"
else
    keytool="$(command -v keytool)" || {
        echo >&2 "ERROR: keytool was not found in PATH and JAVA_HOME is unset"
        exit 1
    }
    keytool="$(readlink -f "${keytool}")"
    java_home="${keytool%/bin/keytool}"
fi
if [[ ! -x "${keytool}" ]]; then
    echo >&2 "ERROR: keytool is not executable: ${keytool}"
    exit 1
fi

java_security_dir="${java_home}/lib/security"
base_java_trust_store="${java_security_dir}/cacerts"
if [[ -f "${java_security_dir}/jssecacerts" && -s "${java_security_dir}/jssecacerts" ]]; then
    base_java_trust_store="${java_security_dir}/jssecacerts"
fi
if [[ ! -f "${base_java_trust_store}" || ! -r "${base_java_trust_store}" \
        || ! -s "${base_java_trust_store}" ]]; then
    echo >&2 "ERROR: JDK default trust store is not readable: ${base_java_trust_store}"
    exit 1
fi

# Append each certificate from the PEM bundle. keytool -importcert reads only
# the first certificate from a multi-cert PEM file, so split the bundle into
# per-cert buffers and import each under a unique alias.
work_dir="$(mktemp -d)"
trap 'rm -rf "${work_dir}"' EXIT

# Start from a copy of the JDK's default trust store as PKCS#12. This keeps the
# standard Mozilla CA set alongside the host's corporate CAs, so downloads to
# public mirrors (not behind the corporate gateway) still verify. keytool prints
# one progress line per entry to stderr; capture it so success is quiet but a
# failure still surfaces the cause.
if ! "${keytool}" -importkeystore -noprompt \
        -srckeystore "${base_java_trust_store}" -srcstoretype JKS -srcstorepass "${STOREPASS}" \
        -destkeystore "${output_trust_store}" -deststoretype PKCS12 -deststorepass "${STOREPASS}" \
        >/dev/null 2>"${work_dir}/import.err"; then
    echo >&2 "ERROR: keytool -importkeystore failed:"
    cat >&2 "${work_dir}/import.err"
    exit 1
fi

count=0
cert_buf=""
cert_file="${work_dir}/cert.pem"
while IFS= read -r line || [[ -n "${line}" ]]; do
    cert_buf+="${line}"$'\n'
    if [[ "${line}" == "-----END CERTIFICATE-----" ]]; then
        printf '%s' "${cert_buf}" > "${cert_file}"
        # -noprompt skips the "trust this certificate?" prompt. A certificate
        # already present under any alias is silently skipped by keytool, so
        # duplicates in the bundle (or shared with cacerts) are harmless.
        if ! "${keytool}" -importcert -noprompt \
                -alias "host-ca-${count}" -file "${cert_file}" \
                -keystore "${output_trust_store}" -storetype PKCS12 -storepass "${STOREPASS}" \
                >/dev/null 2>"${work_dir}/import-cert.err"; then
            echo >&2 "ERROR: failed to import certificate #${count} from bundle:"
            cat >&2 "${work_dir}/import-cert.err"
            exit 1
        fi
        count=$((count + 1))
        cert_buf=""
    fi
done < "${input_bundle}"

if (( count == 0 )); then
    echo >&2 "ERROR: input bundle contains no complete PEM certificates: ${input_bundle}"
    exit 1
fi

if [[ ! -s "${output_trust_store}" ]]; then
    echo >&2 "ERROR: generated trust store is empty: ${output_trust_store}"
    exit 1
fi
echo "==> Generated Java PKCS#12 trust store: ${output_trust_store} (${count} bundle certificate(s) processed)"
