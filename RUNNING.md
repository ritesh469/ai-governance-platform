# Running this on a 16GB laptop

The upstream README asks you to give Docker **at least 16GB of RAM**. On a
machine with 16GB *total*, that is not possible — Windows itself needs
4-6GB. This file documents the two profiles that make the project runnable
anyway, and exactly what each one costs.

## The two profiles

| | Services | Approx. RAM | Layer 3 (PII tags) comes from |
|---|---|---|---|
| **lite** (default) | 11 | ~3.5GB | `data-governance/column_tags.yaml` |
| **full** | 15 | ~8.5GB | OpenMetadata (the real catalog) |

The four services the `full` profile adds — `om-mysql`, `om-elasticsearch`,
`om-migrate`, `openmetadata-server` — are ~5GB on their own. OpenMetadata
alone wants 6GB by its own docs.

### What lite does NOT fake

Layer 3's **decision** is identical on both profiles. The agent sends column
tags to OPA, and `policy/policies/data_access.rego` decides what gets
masked. Only the *source of the tags* changes — catalog vs. local file. The
policy engine, the masking, and the audit trail are the same code path.

What you lose on lite is OpenMetadata's UI, lineage graph, and the
demonstration that tags were discovered by a real catalog rather than
declared in a file. That is a real difference; it is not a mock of the
decision.

## Run it

```bash
docker compose up -d --build
```

That is the lite profile — profile-gated services simply don't start.

```bash
docker compose --profile full up -d --build
```

That adds OpenMetadata. Close your browser and other apps first; on 16GB
total this will be tight and OpenMetadata takes several minutes to migrate
on first boot.

Check what came up:

```bash
docker compose ps
```

## Fail-open vs fail-closed

`get_columns_to_mask()` originally returned "mask nothing" when OpenMetadata
was unreachable. For a demo that is convenient. For a governance system it
is the wrong default: an unreachable catalog is not evidence that a column
is safe to serve.

`DATA_LAYER_FAIL_MODE` now makes that explicit:

```bash
DATA_LAYER_FAIL_MODE=closed docker compose up -d
```

- `open` (default) — serve unmasked if no tag source is reachable
- `closed` — mask every column rather than risk leaking a column the
  catalog would have flagged

Both paths are covered by `tests/test_data_governance.py`.

## Tests

```bash
docker compose run --rm agent python -m pytest tests/ -v
```

The Rego policy tests run separately:

```bash
docker compose run --rm opa test /policies -v
```

## Fixed: the SPIRE agent used to stop after about an hour

**The symptom.** The `agent` container would exit and refuse to restart:

```
RuntimeError: could not fetch SPIFFE SVID from unix:///run/spire/sockets/agent.sock
```

with `spire-agent` gone, its log ending:

```
Agent needs to re-attest; removing SVID and shutting down
error="failed to fetch authorized entries: rpc error: code = PermissionDenied"
```

**The cause.** `spire-setup` attested the node with a SPIRE **join token**,
which is single-use by design. When the agent's SVID reached the end of its
TTL it had to re-attest, the already-consumed token was refused, and the
agent shut itself down. The `agent` service then could not boot, because it
will not start without a real workload identity.

That last part is Layer 1 behaving correctly, and worth noticing: the agent
refuses to run rather than falling back to an unauthenticated identity. A
governance system that started anyway would be the actual bug.

**The fix.** Node attestation now uses **x509pop** (X.509 proof of
possession). The node holds a long-lived certificate and private key, and
proves possession of that key on every attestation — so it can re-attest
indefinitely. SPIRE reports this directly:

```
$ docker exec spire-server /opt/spire/bin/spire-server agent list

SPIFFE ID         : spiffe://governance.demo/spire/agent/x509pop/83ea8ada...
Attestation type  : x509pop
Can re-attest     : true
```

`Can re-attest: true` is the line that matters; under join_token it read
`false`. The agent's `KeyManager` also moved from `memory` to `disk`, so a
restarted agent resumes its identity instead of needing a fresh bootstrap.

Two things that had to be right, both found by running it:

- The node certificate must carry `keyUsage = digitalSignature`. x509pop's
  challenge *is* a signature, so without it the server rejects attestation
  with `certificate not intended for digital signature use`.
- Certificate generation must be **idempotent**. A first version regenerated
  the keypair on every boot; since the node's SPIFFE ID is derived from the
  certificate fingerprint, the second `docker compose up` registered the
  workload under a new fingerprint while the running agent still held the
  old one, and every request failed with `No identity issued ...
  registered=false`. Durable node identity was the entire point of moving
  off join tokens.

To deliberately rotate the node keypair, remove the `spire-shared` volume
(`docker compose down -v` does this) and let `spire-certs` run from clean.

**Still a local-demo simplification:** `insecure_bootstrap` is on, so the
agent trusts the server's CA on first connection rather than pre-sharing it
out of band. A real multi-node deployment would pre-distribute the trust
bundle.
