# Java PKCS#12 generator

A `generators/` backend that produces a Java PKCS#12 trust store from a PEM CA
bundle. Invoked by `container.sh` inside the build container; also runnable
directly.

## Usage

```bash
./tools/yscope-dev-utils/exports/docker/ca-trust/generators/java-pkcs12/generate.sh \
    <host-ca-bundle.pem> <truststore.p12>
```

It needs a JDK: it locates `keytool` via `JAVA_HOME`, falling back to `keytool`
on `PATH`, then reads the JDK's base trust store (`jssecacerts` if present, else
`cacerts`). Given the inputs, it:

1. Copies the base JDK trust store into a new PKCS#12 store via
   `keytool -importkeystore`, preserving the standard Mozilla CA set alongside
   the host's corporate CAs.
2. Imports each certificate from the PEM bundle with `keytool -importcert`,
   splitting the bundle first (keytool reads only the first certificate from a
   multi-cert PEM file) and using unique `host-ca-<n>` aliases. Certificates
   already present under any alias are silently skipped.
3. Writes the result to the output path (store password `changeit`, an
   integrity password for public certificates, not a secret).

`container.sh` runs this and feeds the result to Maven via
`-Djavax.net.ssl.trustStore=<path> -Djavax.net.ssl.trustStoreType=PKCS12
-Djavax.net.ssl.trustStorePassword=changeit`, appended to `MAVEN_OPTS`, avoiding
edits to the JDK's installed `cacerts`.

## Notes

The generator runs in the build container, which already has a JDK for the
build, so no separate generator container or host JDK is required. The output
store is written to the caller-supplied output path, which `container.sh` places
in `CA_TRUST_DIR` -- a writable host bind-mount, not the container's writable
overlay -- so it never enters the image, caches, packages, or layers and is
cleaned up by the caller.

## Files

- `generate.sh` -- validates inputs, locates the JDK trust store, runs keytool.