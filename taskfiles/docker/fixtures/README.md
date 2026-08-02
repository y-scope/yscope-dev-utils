# Test fixtures

Self-signed certificates used by `../test-docker-libs.sh`. **Not real certificates, not trusted by anything, and not secret.** They exist so the expired-certificate filtering in `exports/docker/ca-trust/host.sh` can be tested against a known input.

| File | Subject | Validity |
|---|---|---|
| `valid-ca.pem` | `CN=yscope-dev-utils-test-valid-ca` | expires 2126 |
| `expired-ca.pem` | `CN=yscope-dev-utils-test-expired-ca` | expired 2020-01-02 |

Certificates only — the private keys were discarded at generation and never committed, so neither can sign anything.

They're committed rather than generated at test time because minting an already-expired certificate needs `openssl req -x509 -not_before/-not_after`, which isn't available everywhere, and because a fixture that changes per run makes a failure harder to reproduce.

To regenerate:

```bash
openssl req -x509 -newkey rsa:2048 -nodes -keyout /dev/null -out valid-ca.pem \
    -days 36500 -subj "/CN=yscope-dev-utils-test-valid-ca"

openssl req -x509 -newkey rsa:2048 -nodes -keyout /dev/null -out expired-ca.pem \
    -subj "/CN=yscope-dev-utils-test-expired-ca" \
    -not_before 20200101000000Z -not_after 20200102000000Z
```

Don't add explanatory text above the `-----BEGIN CERTIFICATE-----` line. It's legal PEM and `openssl` ignores it, but `ca_trust_stage_host_bundle` copies everything preceding a certificate into its output, so the text would end up in the staged bundle during tests.
