# CA trust

A library for propagating the host's trusted CA certificates into containerized builds that run behind a TLS-inspecting (e.g., corporate) gateway. Trust is wired up through environment variables and a bind-mounted staging directory, so certificates are never installed into an image or persisted in layers, caches, or artifacts.

The examples below assume the consuming project has this repo as a submodule at `tools/yscope-dev-utils` (see the [usage docs](../../../docs/index.md#usage)) and mounts itself at `/repo` inside the build container; adjust the paths to your layout.

## Requirements

* Host: `bash`, plus a container runtime that supports bind mounts (the examples use Docker).
  * `openssl` (optional): used to drop expired certificates during staging; without it, the bundle is copied as-is.
* Container: `bash`.
  * `findmnt` (optional): used to verify `CA_TRUST_DIR` is not on the container's writable overlay; without it, a warning is printed and the build proceeds.
  * A JDK providing `keytool` (JVM builds only): used to generate the PKCS#12 trust store; without it, JVM trust setup is skipped.

## Quick start

On the host, stage the CA bundle into a temporary directory. Bind-mount that directory (writable) into the container, point `CA_TRUST_DIR` at the mount, and source `container.sh` before running the build:

```bash
# Host side
source tools/yscope-dev-utils/exports/docker/ca-trust/host.sh

CA_TRUST_HOST_DIR="$(mktemp -d)"
trap 'rm -rf "${CA_TRUST_HOST_DIR}"' EXIT

# Creates ${CA_TRUST_HOST_DIR}/ca-bundle.pem (read-only). Check the status: running
# the build without host CA trust is the failure this library exists to avoid.
stage_host_ca_bundle "${CA_TRUST_HOST_DIR}" || exit 1

docker run --rm \
    --mount "type=bind,src=${PWD},dst=/repo" \
    --mount "type=bind,src=${CA_TRUST_HOST_DIR},dst=${CA_TRUST_CONTAINER_DIR}" \
    --env "CA_TRUST_DIR=${CA_TRUST_CONTAINER_DIR}" \
    --env "CA_TRUST_JVM=1" \
    --env MAVEN_OPTS \
    <image> \
    bash -c '
        source /repo/tools/yscope-dev-utils/exports/docker/ca-trust/container.sh
        # Run the build; curl, git, pip, and Maven now trust the host CAs.
    '
```

`CA_TRUST_JVM=1` and `--env MAVEN_OPTS` are only needed for JVM builds; see [JVM builds](#jvm-builds).

## Host API (`host.sh`)

`stage_host_ca_bundle <trust-dir>` writes the host's CA bundle to `<trust-dir>/${CA_TRUST_BUNDLE_FILENAME}` (read-only, `0444`):

* The bundle is taken from `SSL_CERT_FILE` when set; otherwise, common Linux CA-bundle locations are searched. If none is found (e.g., on macOS without `SSL_CERT_FILE`), an empty file is created and the build proceeds without host CA context.
* Expired certificates are dropped during staging (when `openssl` is available on the host), since a single expired certificate in a bundle can break TLS verification for otherwise-valid chains.

Constants:

* `CA_TRUST_BUNDLE_FILENAME` (`ca-bundle.pem`): the staged bundle's filename; `container.sh` reads it from `CA_TRUST_DIR` by this name.
* `CA_TRUST_CONTAINER_DIR` (`/run/ca-trust`): the conventional in-container mount point for the staged trust directory, passed to the container as `CA_TRUST_DIR`.

The caller owns the staging directory and cleans it up (e.g., with `trap`, as above). The scripts never modify the host's or the container's installed trust stores.

## Container API (`container.sh`)

Source it after setting `CA_TRUST_DIR` to the (writable) mount of the staged trust directory. It's a no-op when `CA_TRUST_DIR` is unset, so builds that don't mount a trust directory are unaffected.

When the staged bundle is non-empty, it exports `CURL_CA_BUNDLE`, `GIT_SSL_CAINFO`, `PIP_CERT`, `REQUESTS_CA_BUNDLE`, and `SSL_CERT_FILE`, covering most TLS clients used in builds.

### JVM builds

JVM tools (Maven, Gradle, ...) don't read the environment variables above, so JVM support is opt-in via `CA_TRUST_JVM=1`. When it's set, the bundle is non-empty, and `keytool` is available, `container.sh` uses the container's own JDK to generate a PKCS#12 trust store from the bundle at `${CA_TRUST_DIR}/truststore.p12`, then appends the corresponding `-Djavax.net.ssl.trustStore*` options to `MAVEN_OPTS`, preserving any caller-supplied value (forward `MAVEN_OPTS` into the container, as in the quick start). A generation failure is an error. See [generators/java-pkcs12](generators/java-pkcs12/README.md) for details.

## Persistence contract

`CA_TRUST_DIR` must be a writable host bind-mount or tmpfs, not the container's writable overlay: a file on the overlay would be retained by `docker commit`, while a bind mount is not part of any committed image. `container.sh` verifies this with `findmnt` and refuses to write to the overlay; if `findmnt` is unavailable, it warns and proceeds. All staged and generated files live in the caller's staging directory and disappear when the caller cleans it up.

## Extensibility

Add a backend under `generators/` when a trust format can't consume the PEM bundle directly. Keep host discovery and lifecycle in `host.sh`; keep format-specific conversion in the backend, run in-container. See [generators/java-pkcs12](generators/java-pkcs12/README.md) as a template.
