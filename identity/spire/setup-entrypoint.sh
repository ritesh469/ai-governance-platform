#!/bin/sh
# Runs once (in the `spire-setup` helper container), after spire-certs has
# generated the node keypair and spire-server is up:
#   1. derive the node's x509pop SPIFFE ID from its certificate
#   2. render agent.conf onto a volume spire-agent reads
#   3. register the workload entry that maps the `agent` app container
#      (matched by its real UID on the shared Workload API socket) to a
#      real SPIFFE ID, so it can fetch an X.509-SVID instead of ever using
#      a static hardcoded credential as its own identity.
#
# WHY x509pop AND NOT join_token
# -----------------------------------------------------------------------
# This used to use join_token attestation. Join tokens are single-use by
# design, which produced a real, reproducible failure: the agent attests
# once, gets an SVID with a 1h TTL, and when that SVID reaches the end of
# its life the agent must re-attest. The token has already been consumed,
# the server answers PermissionDenied, and the agent logs
#
#   Agent needs to re-attest; removing SVID and shutting down
#
# and exits. The `agent` service then cannot boot either, because it
# refuses to start without a valid workload identity (which is Layer 1
# behaving correctly — falling back to an unauthenticated identity would
# be the actual bug). Net effect: the whole stack died roughly hourly.
#
# x509pop ("X.509 proof of possession") instead gives the node a long-lived
# certificate and private key. The agent proves possession of that key on
# every attestation, so it can re-attest as many times as it likes. That is
# the documented purpose of the attestor, and it is the right shape for a
# node whose identity is a durable secret rather than a one-time handshake.
set -e
apk add --no-cache jq openssl >/dev/null 2>&1

CERTS=/shared/certs
if [ ! -f "$CERTS/agent.crt" ]; then
  echo "[spire-setup] FAILED: $CERTS/agent.crt missing — did spire-certs run?" >&2
  exit 1
fi

# SPIRE derives the agent's SPIFFE ID from the SHA-1 fingerprint of the DER
# form of the attestation certificate:
#   spiffe://<trust_domain>/spire/agent/x509pop/<fingerprint>
# That is the parent ID the workload entry must be registered under, so we
# compute it the same way SPIRE does rather than guessing.
FINGERPRINT=$(openssl x509 -in "$CERTS/agent.crt" -outform DER \
  | openssl dgst -sha1 | sed 's/^.*= *//' | tr 'A-Z' 'a-z')
AGENT_ID="spiffe://governance.demo/spire/agent/x509pop/$FINGERPRINT"
echo "[spire-setup] node attests as $AGENT_ID"

echo "[spire-setup] waiting for spire-server..."
until docker exec spire-server /opt/spire/bin/spire-server healthcheck >/dev/null 2>&1; do
  sleep 2
done
echo "[spire-setup] spire-server is up"

# Clear the agent's cached trust bundle. agent.conf.template sets
# insecure_bootstrap, so the agent trusts the server's CA on first
# connection and caches it in its data_dir. If spire-server's CA is ever
# regenerated (volume reset, CA rotation), that cached bundle no longer
# verifies the server and the agent crash-loops permanently with
# "x509: certificate signed by unknown authority" — it never re-bootstraps
# on its own.
if [ -d /agent-data ]; then
  rm -rf /agent-data/* /agent-data/.[!.]* 2>/dev/null || true
  echo "[spire-setup] cleared cached agent trust bundle in /agent-data"
fi

cp /template/agent.conf.template /shared/agent.conf
echo "[spire-setup] wrote /shared/agent.conf"

EXISTING_ID=$(docker exec spire-server /opt/spire/bin/spire-server entry show \
  -spiffeID spiffe://governance.demo/agent/demo-agent -output json 2>/dev/null | jq -r '.entries[0].id // empty')
if [ -n "$EXISTING_ID" ]; then
  docker exec spire-server /opt/spire/bin/spire-server entry delete -entryID "$EXISTING_ID" >/dev/null 2>&1 || true
fi

docker exec spire-server /opt/spire/bin/spire-server entry create \
  -spiffeID spiffe://governance.demo/agent/demo-agent \
  -parentID "$AGENT_ID" \
  -selector unix:uid:0

echo "[spire-setup] done — agent SPIFFE ID: spiffe://governance.demo/agent/demo-agent"
