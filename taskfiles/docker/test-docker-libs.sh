#!/usr/bin/env bash

# Tests for exports/docker/ca-trust/host.sh, exports/docker/ca-trust/container.sh,
# and exports/docker/build/host.sh.
#
# Docker-free by design: every assertion here exercises shell behaviour only, so
# the suite runs anywhere. The Docker-level behaviour these libraries depend on
# (named build contexts, bind mounts leaving no layer residue) is verified by
# the consuming repos' image builds.

# SC2030/SC2031: environment mutations are deliberately confined to subshells so
# each case runs against a known environment; "the change might be lost" is the
# intent, not a bug. Must precede all commands to apply file-wide.
# shellcheck disable=SC2030,SC2031

set -o errexit
set -o nounset
set -o pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
repo_root="$(cd "${script_dir}/../.." &>/dev/null && pwd)"
fixtures_dir="${script_dir}/fixtures"

readonly VALID_CA="${fixtures_dir}/valid-ca.pem"
readonly EXPIRED_CA="${fixtures_dir}/expired-ca.pem"

failures=0
checks=0

# Args: <description> <expected> <actual>
expect_eq() {
    checks=$((checks + 1))
    if [[ "$2" == "$3" ]]; then
        echo "  ok  $1"
    else
        echo "  FAIL $1"
        echo "         expected: [$2]"
        echo "         actual:   [$3]"
        failures=$((failures + 1))
    fi
}

# Args: <description> <actual-exit-code> <expected-exit-code>
expect_rc() {
    expect_eq "$1" "$3" "$2"
}

# Echoes a file's permission bits as octal digits, e.g. 444. `stat -c` is GNU;
# macOS's BSD stat spells the same thing `-f %Lp`.
#
# Args: <path>
file_mode() {
    stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"
}

# shellcheck source=exports/docker/ca-trust/host.sh
source "${repo_root}/exports/docker/ca-trust/host.sh"
# shellcheck source=exports/docker/build/host.sh
source "${repo_root}/exports/docker/build/host.sh"

work_dir="$(mktemp -d)"
trap 'rm -rf "${work_dir}"' EXIT

echo "== ca_trust_stage_host_bundle =="

# Expired certificates are dropped, valid ones kept.
mixed_bundle="${work_dir}/mixed.pem"
cat "${VALID_CA}" "${EXPIRED_CA}" > "${mixed_bundle}"
stage_a="${work_dir}/stage-a"
mkdir -p "${stage_a}"
SSL_CERT_FILE="${mixed_bundle}" ca_trust_stage_host_bundle "${stage_a}" 2>/dev/null
expect_eq "drops the expired cert, keeps the valid one" \
    "1" "$(grep -c 'BEGIN CERTIFICATE' "${stage_a}/ca-bundle.pem")"
expect_eq "staged bundle is read-only (0444)" "444" "$(file_mode "${stage_a}/ca-bundle.pem")"
expect_eq "staged bundle keeps the valid subject" "1" \
    "$(openssl x509 -in "${stage_a}/ca-bundle.pem" -noout -subject 2>/dev/null \
        | grep -c 'yscope-dev-utils-test-valid-ca')"

# A bundle of only-expired certs stages as empty rather than failing.
stage_b="${work_dir}/stage-b"
mkdir -p "${stage_b}"
SSL_CERT_FILE="${EXPIRED_CA}" ca_trust_stage_host_bundle "${stage_b}" 2>/dev/null
expect_eq "all-expired bundle stages empty" "0" "$(wc -c < "${stage_b}/ca-bundle.pem" | tr -d ' ')"

# An SSL_CERT_FILE that doesn't exist is a hard error, not a fallback.
stage_c="${work_dir}/stage-c"
mkdir -p "${stage_c}"
rc=0
SSL_CERT_FILE="${work_dir}/does-not-exist.pem" \
    ca_trust_stage_host_bundle "${stage_c}" 2>/dev/null || rc=$?
expect_rc "nonexistent SSL_CERT_FILE fails" "${rc}" "1"

# No bundle anywhere: empty file, success. This is the default/CI path, so it
# must never fail the caller.
stage_d="${work_dir}/stage-d"
mkdir -p "${stage_d}"
rc=0
( unset SSL_CERT_FILE
  CA_TRUST_BUNDLE_SEARCH_PATHS="${work_dir}/nope-1:${work_dir}/nope-2" \
      ca_trust_stage_host_bundle "${stage_d}" ) 2>/dev/null || rc=$?
expect_rc "no host bundle found still succeeds" "${rc}" "0"
expect_eq "no host bundle produces an empty file" "0" \
    "$(wc -c < "${stage_d}/ca-bundle.pem" | tr -d ' ')"

# Bad arity.
rc=0
ca_trust_stage_host_bundle 2>/dev/null || rc=$?
expect_rc "missing argument is a usage error" "${rc}" "2"

echo "== ca_trust_stage_or_fail =="

stage_ok="${work_dir}/stage-ok"
mkdir -p "${stage_ok}"
rc=0
( export SSL_CERT_FILE="${VALID_CA}"; ca_trust_stage_or_fail "${stage_ok}" ) 2>/dev/null || rc=$?
expect_rc "succeeds when a usable bundle is found" "${rc}" "0"

# The plain staging call tolerates an empty bundle; this one must not.
stage_none="${work_dir}/stage-none"
mkdir -p "${stage_none}"
rc=0
(
    unset SSL_CERT_FILE
    export CA_TRUST_BUNDLE_SEARCH_PATHS="${work_dir}/nope-1:${work_dir}/nope-2"
    ca_trust_stage_or_fail "${stage_none}"
) 2>/dev/null || rc=$?
expect_rc "fails when no bundle is found" "${rc}" "1"

# An all-expired bundle stages empty, which is equally unusable.
stage_exp="${work_dir}/stage-exp"
mkdir -p "${stage_exp}"
rc=0
( export SSL_CERT_FILE="${EXPIRED_CA}"; ca_trust_stage_or_fail "${stage_exp}" ) 2>/dev/null || rc=$?
expect_rc "fails when every certificate is expired" "${rc}" "1"

echo "== ca_trust_stage_build_context =="

ca_trust_stage_build_context "${stage_a}"
expect_eq "stages container.sh" "yes" "$([[ -f "${stage_a}/container.sh" ]] && echo yes || echo no)"
expect_eq "stages container-exec.sh" "yes" \
    "$([[ -f "${stage_a}/container-exec.sh" ]] && echo yes || echo no)"
expect_eq "stages generators/ for the JVM path" "yes" \
    "$([[ -d "${stage_a}/generators/java-pkcs12" ]] && echo yes || echo no)"
expect_eq "does not stage host.sh into the container" "no" \
    "$([[ -f "${stage_a}/host.sh" ]] && echo yes || echo no)"
expect_eq "leaves the staged bundle in place" "yes" \
    "$([[ -s "${stage_a}/ca-bundle.pem" ]] && echo yes || echo no)"

echo "== ca_trust_add_run_args =="

got="$(
    cmd=(docker run)
    ca_trust_add_run_args cmd "${stage_a}"
    printf '%s' "${cmd[*]}"
)"
expect_eq "mounts the trust dir and sets CA_TRUST_DIR" \
    "docker run --mount type=bind,src=${stage_a},dst=/run/ca-trust --env CA_TRUST_DIR=/run/ca-trust" \
    "${got}"

# JVM opt-in must be passed BY VALUE. The pass-through `--env NAME` form is
# resolved by the docker client when the command runs, so a caller that scopes
# the assignment to this call -- `CA_TRUST_JVM=1 ca_trust_add_run_args ...` --
# would silently lose it.
got="$(
    cmd=(docker run)
    CA_TRUST_JVM=1 ca_trust_add_run_args cmd "${stage_a}"
    # `|| true`: grep -c exits 1 on zero matches, which under errexit would kill
    # this subshell -- aborting the suite instead of failing the assertion, i.e.
    # exactly when the regression is present.
    printf '%s\n' "${cmd[@]}" | grep -c '^CA_TRUST_JVM=1$' || true
)"
expect_eq "passes CA_TRUST_JVM by value, not by reference" "1" "${got}"

got="$(
    cmd=(docker run)
    unset CA_TRUST_JVM || true
    ca_trust_add_run_args cmd "${stage_a}"
    printf '%s\n' "${cmd[@]}" | grep -c 'CA_TRUST_JVM' || true
)"
expect_eq "no JVM flags when CA_TRUST_JVM is unset" "0" "${got}"

echo "== container.sh =="

# Unset CA_TRUST_DIR is a no-op, and must not fail the caller.
out="$(unset CA_TRUST_DIR; source "${repo_root}/exports/docker/ca-trust/container.sh" \
    && echo "rc=0 SSL_CERT_FILE=[${SSL_CERT_FILE:-unset}]")"
expect_eq "no-op when CA_TRUST_DIR is unset" "rc=0 SSL_CERT_FILE=[unset]" "${out}"

# Empty bundle exports nothing: pointing SSL_CERT_FILE at an empty file would
# break all TLS rather than falling back to the system store.
out="$(CA_TRUST_DIR="${stage_d}" source "${repo_root}/exports/docker/ca-trust/container.sh" \
    && echo "[${SSL_CERT_FILE:-unset}]")"
expect_eq "empty bundle exports nothing" "[unset]" "${out}"

# Non-empty bundle exports the full set.
for var in CURL_CA_BUNDLE GIT_SSL_CAINFO PIP_CERT REQUESTS_CA_BUNDLE SSL_CERT_FILE; do
    out="$(CA_TRUST_DIR="${stage_a}" \
        source "${repo_root}/exports/docker/ca-trust/container.sh" && echo "${!var:-unset}")"
    expect_eq "exports ${var}" "${stage_a}/ca-bundle.pem" "${out}"
done

# MAVEN_OPTS ordering: consumers string-parse it for a flag they append after
# sourcing, so anything added here must come first and stay space-separated.
out="$(
    export CA_TRUST_DIR="${stage_a}" MAVEN_OPTS="-Dcaller.flag=1"
    unset CA_TRUST_JVM || true
    source "${repo_root}/exports/docker/ca-trust/container.sh"
    echo "${MAVEN_OPTS:-unset}"
)"
expect_eq "preserves caller MAVEN_OPTS when JVM support is off" "-Dcaller.flag=1" "${out}"

# An explicit CA_TRUST_JVM=1 that does nothing must say so: the alternative is a
# PKIX error much later in a JVM build, with no link back to the cause.
out="$(
    export CA_TRUST_DIR="${stage_d}" CA_TRUST_JVM=1
    source "${repo_root}/exports/docker/ca-trust/container.sh" 2>&1 >/dev/null
)"
expect_eq "warns when CA_TRUST_JVM is set but the bundle is empty" "1" \
    "$(printf '%s' "${out}" | grep -c 'CA_TRUST_JVM is set' || true)"

echo "== build/host.sh =="

# NOTE: assertions must run in this shell, not a subshell -- expect_eq's failure
# counter can't propagate out of one, so a subshell assertion would fail
# silently and the suite would still report success. Where a case needs a
# modified environment, run only the *value production* in a subshell and assert
# on its captured stdout here.

# Args: <prefix> [element...] -- echoes the first element starting with <prefix>.
# Selecting by content, not by index: a positional `${cmd[2]}` aborts the whole
# suite with an unbound-variable error under `nounset` when the helper appends
# nothing, which is exactly the regression these cases exist to report.
select_arg() {
    local prefix="$1"
    shift
    local arg
    for arg in "$@"; do
        case "${arg}" in
            "${prefix}"*)
                printf '%s' "${arg}"
                return 0
                ;;
        esac
    done
    return 1
}

# Values containing spaces, quotes and $ must survive verbatim.
nasty='http://user:p$$ w'"'"'d@127.0.0.1:8080'
got="$(
    export HTTPS_PROXY="${nasty}"
    cmd=(base)
    docker_build_add_proxy_args cmd
    select_arg "HTTPS_PROXY=" "${cmd[@]}" || true
)"
expect_eq "proxy value survives shell metacharacters" "HTTPS_PROXY=${nasty}" "${got}"

# An embedded newline is what a hand-rolled quoting scheme loses.
multiline="$(printf 'line1\nline2')"
got="$(
    export HTTPS_PROXY="${multiline}"
    cmd=(base)
    docker_build_add_proxy_args cmd
    select_arg "HTTPS_PROXY=" "${cmd[@]}" || true
)"
expect_eq "proxy value survives an embedded newline" "HTTPS_PROXY=${multiline}" "${got}"

# Loopback proxies switch to host networking, including behind credentials.
for probe in "http://127.0.0.1:8080|host" "http://user:pw@127.0.0.1:8080|host" \
             "http://localhost|host" "http://[::1]:3128|host" \
             "http://proxy.corp.example:8080|none"; do
    url="${probe%|*}"
    want="${probe#*|}"
    got="$(
        export HTTPS_PROXY="${url}"
        cmd=(base)
        docker_build_add_proxy_args cmd
        net="none"
        for i in "${!cmd[@]}"; do
            [[ "${cmd[${i}]}" == "--network" ]] && net="${cmd[$((i + 1))]}"
        done
        printf '%s' "${net}"
    )"
    expect_eq "network for ${url}" "${want}" "${got}"
done

# NO_PROXY names loopback hosts routinely; it must not trigger host networking.
got="$(
    export NO_PROXY="localhost,127.0.0.1"
    cmd=(base)
    docker_build_add_proxy_args cmd
    printf '%s' "$(printf '%s\n' "${cmd[@]}" | grep -c -- '--network' || true)"
)"
expect_eq "NO_PROXY alone does not force host networking" "0" "${got}"

# An unset trailing variable must not leak a nonzero status to an errexit caller.
rc=0
(
    unset _TEST_MIRROR_A _TEST_MIRROR_B || true
    cmd=(base)
    docker_build_add_env_build_args cmd _TEST_MIRROR_A _TEST_MIRROR_B
) || rc=$?
expect_rc "all-unset build args returns success" "${rc}" "0"

got="$(
    export _TEST_MIRROR_A="http://mirror.example/a"
    unset _TEST_MIRROR_B || true
    cmd=(base)
    docker_build_add_env_build_args cmd _TEST_MIRROR_A _TEST_MIRROR_B
    printf '%s' "${cmd[*]}"
)"
expect_eq "forwards only the set build arg" \
    "base --build-arg _TEST_MIRROR_A=http://mirror.example/a" "${got}"

# Credentials in a git remote must not reach the image label, which travels with
# the image to every registry that ever stores it.
cred_repo="${work_dir}/cred-repo"
mkdir -p "${cred_repo}"
git -C "${cred_repo}" init -q 2>/dev/null
git -C "${cred_repo}" remote add origin "https://user:s3cr3t@github.com/y-scope/example.git"
got="$(
    cmd=(base)
    docker_build_add_oci_labels cmd "${cred_repo}"
    select_arg "org.opencontainers.image.source=" "${cmd[@]}" || true
)"
expect_eq "git credentials are stripped from the source label" \
    "org.opencontainers.image.source=https://github.com/y-scope/example.git" "${got}"

# Masking must not mangle URLs that carry no credentials, including the scp-style
# git remote (no `://`) and an `@` that appears in a path rather than the
# authority.
expect_eq "no-credential URL is left alone" "https://github.com/y-scope/example.git" \
    "$(_docker_build_replace_userinfo "https://github.com/y-scope/example.git")"
expect_eq "scp-style remote is left alone" "git@github.com:y-scope/example.git" \
    "$(_docker_build_replace_userinfo "git@github.com:y-scope/example.git")"
expect_eq "an @ in the path is not credentials" "https://example.com/a@b" \
    "$(_docker_build_replace_userinfo "https://example.com/a@b")"
expect_eq "proxy credentials are masked for logging" "http://***@127.0.0.1:8080" \
    "$(_docker_build_replace_userinfo "http://user:pw@127.0.0.1:8080" "***@")"

got="$(export DOCKER_PULL=false; cmd=(base); docker_build_add_pull_arg cmd; printf '%s' "${cmd[*]}")"
expect_eq "DOCKER_PULL=false omits --pull" "base" "${got}"

got="$(unset DOCKER_PULL || true; cmd=(base); docker_build_add_pull_arg cmd; printf '%s' "${cmd[*]}")"
expect_eq "--pull by default" "base --pull" "${got}"

echo
if (( failures > 0 )); then
    echo "FAILED: ${failures}/${checks} checks failed"
    exit 1
fi
echo "PASSED: ${checks}/${checks} checks"
