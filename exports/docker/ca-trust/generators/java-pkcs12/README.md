# Java PKCS#12 generator

A `generators/` backend that produces a Java PKCS#12 trust store from a PEM CA bundle. Invoked by `container.sh` inside the build container; also runnable directly:

```bash
tools/yscope-dev-utils/exports/docker/ca-trust/generators/java-pkcs12/generate.sh \
    <ca-bundle.pem> <truststore.p12>
```

It requires a JDK (`keytool` is located via `JAVA_HOME`, falling back to `PATH`); the build container already has one for the build, so no separate generator container or host JDK is needed. Given the inputs, it:

1. Copies the JDK's base trust store (`jssecacerts` if present, else `cacerts`) into a new PKCS#12 store, keeping the standard public CA set alongside the bundle's CAs so downloads from hosts not behind the gateway still verify.
2. Imports each certificate from the PEM bundle under a unique `host-ca-<n>` alias, splitting the bundle first since `keytool -importcert` reads only the first certificate of a multi-cert file. Certificates already present in the store are silently skipped.
3. Writes the store to the output path with password `changeit` (an integrity password for public certificates, not a secret).

`container.sh` points the JVM at the result via `-Djavax.net.ssl.trustStore*` options appended to `MAVEN_OPTS`, avoiding edits to the JDK's installed `cacerts`. The store is written to the caller-supplied output path -- for `container.sh`, inside `CA_TRUST_DIR`, a writable bind mount rather than the container's overlay -- so it never enters an image, cache, or artifact, and is removed when the caller cleans up the staging directory.
