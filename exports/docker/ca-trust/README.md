# CA trust

A reusable library for propagating the host's trusted certificates into a containerized build behind a corporate TLS gateway, without installing them in an image or persisting them in layers, caches, or artifacts.

## Quick start

On the host, stage the PEM CA bundle. Bind-mount it writable into the build container, and in the container set `CA_TRUST_DIR` to that mount point (plus `CA_TRUST_JVM=1` for a JVM build), then source `container.sh`. The Java PKCS#12 trust store is generated in-container into the same directory, alongside the bundle.

```bash
# Host side
source tools/yscope-dev-utils/exports/docker/ca-trust/host.sh

CA_TRUST_HOST_DIR="$(mktemp -d)"
trap 'rm -rf "${CA_TRUST_HOST_DIR}"' EXIT
stage_host_ca_bundle "${CA_TRUST_HOST_DIR}"  # creates ${CA_TRUST_HOST_DIR}/ca-bundle.pem, read-only

docker run --rm \
    --mount "type=bind,src=${CA_TRUST_HOST_DIR},dst=${CA_TRUST_CONTAINER_DIR}" \
    --env "CA_TRUST_DIR=${CA_TRUST_CONTAINER_DIR}" \
    --env "CA_TRUST_JVM=1" \
    --env MAVEN_OPTS \
    <image> bash -c '
        source /repo/tools/yscope-dev-utils/exports/docker/ca-trust/container.sh
        # ... run the build; curl/git/pip/Maven now use the host CAs
    '
```

Only the PEM bundle is staged on the host; the Java trust store is generated inside the container, which already has a JDK for the build. The generated store is written to the same writable bind mount (not the container's writable overlay), so it never lands on the overlay and cannot be retained by `docker commit`. The caller cleans up the staging directory.

## Host API (`host.sh`)

| Function               | Args          | Effect                                                                                                                                                                            |
|------------------------|---------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `stage_host_ca_bundle` | `<trust-dir>` | Writes `<trust-dir>/${CA_TRUST_BUNDLE_FILENAME}` (`0444`). Uses `SSL_CERT_FILE` when set, else searches common Linux CA-bundle locations; creates an empty file if none is found. |

Constants: `CA_TRUST_BUNDLE_FILENAME` (`ca-bundle.pem`) and `CA_TRUST_CONTAINER_DIR` (`/run/ca-trust`, the in-container mount point for the staged trust directory, passed as `CA_TRUST_DIR`).

## Container API (`container.sh`)

Source it in the container after setting `CA_TRUST_DIR`; set `CA_TRUST_JVM=1` as well if the build runs on a JVM (Maven, Gradle, ...) that needs its trust store configured:

```bash
CA_TRUST_DIR=/trusted
CA_TRUST_JVM=1
source tools/yscope-dev-utils/exports/docker/ca-trust/container.sh
```

It reads `ca-bundle.pem` from `CA_TRUST_DIR`. When the bundle is non-empty it exports `CURL_CA_BUNDLE`, `GIT_SSL_CAINFO`, `PIP_CERT`, `REQUESTS_CA_BUNDLE`, and `SSL_CERT_FILE`. When `CA_TRUST_JVM` is set, the bundle is non-empty, and `keytool` is available, it also generates a PKCS#12 trust store from the bundle via `generators/java-pkcs12/generate.sh`, writes it to `${CA_TRUST_DIR}/truststore.p12`, and appends `-Djavax.net.ssl.trustStore*` to `MAVEN_OPTS` (preserving any caller-supplied value).

**Persistence contract:** `CA_TRUST_DIR` must be a writable host bind-mount or tmpfs, not the container's writable overlay. `container.sh` verifies this with `findmnt` and refuses (with an error) to write to the overlay, since a file there would be retained by `docker commit`. If `findmnt` is unavailable it warns but proceeds. A generation failure errors.

JVM trust configuration is opt-in via `CA_TRUST_JVM`, since not every caller runs on a JVM; it's also skipped when the bundle is empty or `keytool` is absent. A no-op when `CA_TRUST_DIR` is unset, so CI builds that don't mount a trust directory are unaffected.

The caller owns and cleans up the staging directory; the scripts never modify the host or container trust stores, only the staged bundle. The generated PKCS#12 store is a per-build file in the caller's staging directory, removed when the caller cleans up.

## Extensibility

Add a backend under `generators/` when a trust format can't consume the PEM bundle directly. Keep host discovery and lifecycle in `host.sh`; keep format-specific conversion in the backend, run in-container. See `generators/java-pkcs12/README.md`.
