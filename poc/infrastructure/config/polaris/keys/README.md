# Token-broker signing keys (POC only)

Polaris signs the OAuth tokens it issues with an RSA key pair. If no key files are configured it
**generates a fresh pair at every start**, which silently invalidates every token already handed out
— long-lived clients such as the Kafka sink then fail with:

```
NotAuthorizedException: Not authorized: Failed to verify the token
```

Mounting a stable pair fixes that (see `polaris.authentication.token-broker.rsa-key-pair.*` in
`docker-compose.yml`).

| File | Purpose |
|---|---|
| `private_key.pem` | signs tokens (keep secret — anyone holding it can mint catalog tokens) |
| `public_key.pem` | verifies tokens |

## These keys are committed deliberately. Do not copy this pattern to production.

They exist so the POC stack is reproducible: `docker compose up` yields a Polaris whose restarts
do **not** invalidate tokens. In a real deployment:

- supply both files from a **secret manager**, not the repository;
- keep `private_key.pem` out of version control entirely;
- support **rotation** — publish the new public key before switching the private key, so tokens
  signed with the retiring key keep verifying until they expire.

Regenerate a pair with:

```bash
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out private_key.pem
openssl rsa -pubout -in private_key.pem -out public_key.pem
```
