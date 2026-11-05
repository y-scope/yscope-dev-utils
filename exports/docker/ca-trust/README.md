# CA trust

A library for propagating the host's trusted CA certificates into containerized builds that run behind a TLS-inspecting (e.g., corporate) gateway. Trust is wired up through environment variables and an ephemeral mount, so certificates are never installed into an image or persisted in layers, caches, or artifacts.

The examples below assume the consuming project has this repo as a submodule at `tools/yscope-dev-utils` (see the [usage docs](../../../docs/index.md#usage)); adjust the paths to your layout.

## Onboarding a project

1. Add this repo as a submodule — see the [usage docs](../../../docs/index.md#usage).
2. Decide which halves you need. Certificates during **image builds** ([below](#docker-build)), inside **running containers** ([below](#docker-run)), or both. They're independent.
3. Make it opt-in. Put it behind a flag (`--with-ca-certs` in `y-scope/clp` and `y-scope/clp-plugin-presto-connector`) so the default path — and CI — does nothing at all. CI has no TLS-inspecting gateway and should not be staging certificates.
4. If your build installs packages with `apt` or `dnf`, wire up their own options as well. They ignore the environment variables this library sets; see [Package managers](#package-managers-need-to-be-told-separately).
5. Verify with a control. Build **without** a bundle first and confirm it fails the way you expect, then build with one and confirm it passes. A passing build proves nothing on its own — it may simply not have needed the certificates. `mitmproxy` makes a usable stand-in for a corporate gateway if you don't have one.

## Requirements

* Host: `bash` 3.2 or newer (macOS's `/bin/bash` qualifies), plus a container runtime that supports bind mounts.
  * `docker build` support additionally needs BuildKit with named build contexts: Docker 23 or newer.
  * `openssl` (optional): used to drop expired certificates during staging; without it, the bundle is copied as-is.
* Container: `bash`.
  * `findmnt` (optional): used to verify `CA_TRUST_DIR` is not on the container's writable overlay; without it, a warning is printed and the build proceeds.
  * A JDK providing `keytool` (JVM builds only): used to generate the PKCS#12 trust store; without it, JVM trust setup is skipped.

## Docker build

Declare an empty default stage so the mount resolves when no CA trust is supplied, and guard the `RUN` so it works either way:

```dockerfile
# syntax=docker/dockerfile:1
FROM scratch AS ca_trust

FROM <base-image>
RUN --mount=type=bind,from=ca_trust,target=/run/ca-trust \
    if [ -e /run/ca-trust/container.sh ]; then \
        export CA_TRUST_DIR=/run/ca-trust; \
        runner="bash /run/ca-trust/container-exec.sh"; \
    else runner=""; fi; \
    $runner <your build command>
```

On the host, stage the bundle and the library into one directory and pass it as the `ca_trust` build context:

```bash
source tools/yscope-dev-utils/exports/docker/ca-trust/host.sh

ca_trust_dir="$(mktemp -d)"
trap 'rm -rf "${ca_trust_dir}"' EXIT

# Check the status: building without the CA trust you asked for is the failure
# this library exists to prevent.
ca_trust_stage_or_fail "${ca_trust_dir}" || exit 1
ca_trust_stage_build_context "${ca_trust_dir}" || exit 1

build_cmd=(docker buildx build --tag <tag> --file <dockerfile> <context>)
ca_trust_add_build_args build_cmd "${ca_trust_dir}"
"${build_cmd[@]}"
```

Omit those calls and the `FROM scratch AS ca_trust` stage supplies an empty directory: the `RUN` falls through to the plain command and the image keeps its own distro trust store. That is what makes CA trust opt-in, and why CI needs no CA configuration at all.

A named build context is used rather than a BuildKit secret because secrets are capped at 500KiB and corporate CA bundles can exceed that. Bind mounts of a build context are equally ephemeral: nothing lands in a layer or in `docker history`.

## Docker run

Bind-mount the staging directory (writable) into the container, point `CA_TRUST_DIR` at the mount, and source `container.sh` before running the build:

```bash
source tools/yscope-dev-utils/exports/docker/ca-trust/host.sh

ca_trust_dir="$(mktemp -d)"
trap 'rm -rf "${ca_trust_dir}"' EXIT
ca_trust_stage_or_fail "${ca_trust_dir}" || exit 1

run_cmd=(docker run --rm --mount "type=bind,src=${PWD},dst=/repo")
CA_TRUST_JVM=1 ca_trust_add_run_args run_cmd "${ca_trust_dir}"
"${run_cmd[@]}" <image> bash -c '
    source /repo/tools/yscope-dev-utils/exports/docker/ca-trust/container.sh
    # Run the build; curl, git, pip, and Maven now trust the host CAs.
'
```

`CA_TRUST_JVM=1` is only needed for JVM builds; see [JVM builds](#jvm-builds).

## Host API (`host.sh`)

`ca_trust_stage_host_bundle <trust-dir>` writes the host's CA bundle to `<trust-dir>/${CA_TRUST_BUNDLE_FILENAME}` (read-only, `0444`):

* The bundle is taken from `SSL_CERT_FILE` when set; otherwise, common Linux CA-bundle locations are searched. If none is found (e.g., on macOS without `SSL_CERT_FILE`), an empty file is created and the build proceeds without host CA context.
* Expired certificates are dropped during staging (when `openssl` is available on the host), since a single expired certificate in a bundle can break TLS verification for otherwise-valid chains.
* `CA_TRUST_BUNDLE_SEARCH_PATHS` (colon-separated) overrides the default search list; it exists so the "no host bundle" path is reachable in tests.

`ca_trust_stage_or_fail <trust-dir>` stages the bundle and fails if nothing usable was found. `ca_trust_stage_host_bundle` tolerates an empty bundle on purpose, because a build with no host CA context is normal; a caller that explicitly asked for CA trust wants the opposite, so use this instead of repeating the check.

`ca_trust_stage_build_context <trust-dir>` copies this library into the staging directory, so one named build context carries both the bundle and the scripts that consume it.

`ca_trust_add_build_args <cmd-array-name> <trust-dir>` and `ca_trust_add_run_args <cmd-array-name> <trust-dir>` append the corresponding Docker flags to a caller-owned bash array.

Constants:

* `CA_TRUST_BUNDLE_FILENAME` (`ca-bundle.pem`): the staged bundle's filename; `container.sh` reads it from `CA_TRUST_DIR` by this name.
* `CA_TRUST_CONTAINER_DIR` (`/run/ca-trust`): the conventional in-container mount point.
* `CA_TRUST_BUILD_CONTEXT_NAME` (`ca_trust`): the named build context. A Dockerfile can't read these shell constants, so this name is also spelled out in each consuming Dockerfile; keep the two in sync.

The caller owns the staging directory and cleans it up. The scripts never modify the host's or the container's installed trust stores.

## Container API (`container.sh`)

Source it after setting `CA_TRUST_DIR` to the mount of the staged trust directory. It's a no-op when `CA_TRUST_DIR` is unset, so builds that don't mount a trust directory are unaffected.

When the staged bundle is non-empty, it exports `CURL_CA_BUNDLE`, `GIT_SSL_CAINFO`, `PIP_CERT`, `REQUESTS_CA_BUNDLE`, and `SSL_CERT_FILE`. An empty bundle deliberately exports nothing: pointing `SSL_CERT_FILE` at an empty file would break all TLS rather than falling back to the system store.

### Package managers need to be told separately

`curl`, `git`, `pip`, and `apk` read the variables above. **`apt` and `dnf` read none of them** -- verified: `apt` over https still fails certificate verification with `SSL_CERT_FILE` and `CURL_CA_BUNDLE` both pointing at a valid bundle, and `dnf` succeeds with both set to `/dev/null`. If your build installs packages with either, pass the bundle explicitly:

```bash
apt-get -o "Acquire::https::CaInfo=${CA_TRUST_DIR}/ca-bundle.pem" update
dnf --setopt="sslcacert=${CA_TRUST_DIR}/ca-bundle.pem" install ...
```

Guard both on the bundle existing, so the default (no CA trust supplied) is unaffected. See `components/core/tools/scripts/lib_install/ca-trust-pkg-opts.sh` in `y-scope/clp` for one way to factor this out.

Anything reading none of these -- `wget`, Node (`NODE_EXTRA_CA_CERTS`), rustls-based tooling -- also needs its own configuration.

`container-exec.sh <cmd> [args...]` sources `container.sh` and then execs the command. Dockerfile `RUN` steps are executed by `/bin/sh` while `container.sh` needs `bash`, so this wrapper keeps the Dockerfile free of nested quoting.

### JVM builds

JVM tools (Maven, Gradle, ...) don't read the environment variables above, so JVM support is opt-in via `CA_TRUST_JVM=1`. When it's set, the bundle is non-empty, and `keytool` is available, `container.sh` uses the container's own JDK to generate a PKCS#12 trust store from the bundle at `${CA_TRUST_DIR}/truststore.p12`, then appends the corresponding `-Djavax.net.ssl.trustStore*` options to `MAVEN_OPTS`, preserving any caller-supplied value. A generation failure is an error. See [generators/java-pkcs12](generators/java-pkcs12/README.md) for details.

Options are *appended*, space-separated. Callers that string-parse `MAVEN_OPTS` for a flag they add after sourcing `container.sh` rely on that ordering.

This is a `docker run` feature. A `docker build` gets the trust directory through a bind mount of the named build context, and those are read-only, so generating the trust store there fails. A build that needs JVM trust must add `rw` to its `RUN --mount`, which makes the writes land in a scratch layer that BuildKit discards. Nothing in this repo's consumers does that today.

## Persistence contract

`CA_TRUST_DIR` must be a bind-mount or tmpfs, not the container's writable overlay: a file on the overlay would be retained by `docker commit`, while a mount is not part of any committed image. `container.sh` verifies this with `findmnt` before writing the JVM trust store and refuses to write to the overlay; if `findmnt` is unavailable, it warns and proceeds. All staged and generated files live in the caller's staging directory and disappear when the caller cleans it up.

## Extensibility

Add a backend under `generators/` when a trust format can't consume the PEM bundle directly. Keep host discovery and lifecycle in `host.sh`; keep format-specific conversion in the backend, run in-container. See [generators/java-pkcs12](generators/java-pkcs12/README.md) as a template.

## Why there's no taskfile wrapper

Unlike most `exports/` libraries, this one isn't consumed through Task. Its functions must be `source`d into the caller's shell to mutate a command array and export variables, and Task runs each `cmd` in a fresh process.
