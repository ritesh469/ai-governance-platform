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

## Known issue: the SPIRE agent stops after about an hour

**Symptom.** The `agent` container exits and will not restart, logging:

```
RuntimeError: could not fetch SPIFFE SVID from unix:///run/spire/sockets/agent.sock
```

and `docker compose ps` shows `spire-agent` gone. Its own log ends with:

```
Agent needs to re-attest; removing SVID and shutting down
error="failed to fetch authorized entries: rpc error: code = PermissionDenied"
```

**Cause.** `spire-setup` attests the agent with a SPIRE **join token**, which
is single-use by design. When the agent's SVID reaches the end of its TTL it
must re-attest, the already-consumed token is refused, and the agent shuts
itself down. The `agent` service then cannot boot, because it will not start
without a real workload identity.

That last part is Layer 1 behaving correctly, and worth noticing: the agent
refuses to run rather than falling back to an unauthenticated identity. A
governance system that started anyway would be the actual bug.

**Recovery.** Mint a fresh join token and restart the identity chain:

```bash
docker compose up -d --force-recreate spire-setup
docker compose up -d --force-recreate spire-agent
docker compose up -d agent
```

**Proper fix (not done here).** Join-token attestation is meant for
bootstrapping, not for a long-running node. A deployment that needs to
survive unattended should use a re-attestable node attestor — `x509pop`, or
the Docker workload attestor — so the agent can prove its identity again
without a one-time secret. That is a real change to `identity/spire/` and is
left as a deliberate follow-up rather than a rushed patch.
