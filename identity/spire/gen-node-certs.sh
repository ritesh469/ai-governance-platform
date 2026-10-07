#!/bin/sh
# Generates the x509pop node-attestation keypair, BEFORE spire-server starts.
#
# This is its own one-shot service rather than part of setup-entrypoint.sh
# because of an ordering constraint that is easy to get wrong: spire-server
# refuses to start if the x509pop ca_bundle_path does not exist, while
# setup-entrypoint.sh waits for spire-server to be healthy before it can
# register entries. Generating certs inside that script deadlocks — the
# server waits for a file the script cannot write until the server is up.
#
# So: spire-certs (this) -> spire-server -> spire-setup.
set -e
apk add --no-cache openssl >/dev/null 2>&1

CERTS=/shared/certs
mkdir -p "$CERTS"

# IDEMPOTENT ON PURPOSE — do not "freshen" these on every boot.
#
# An earlier version of this script regenerated the keypair every time it
# ran, and that was wrong in a way worth recording. The node's SPIFFE ID is
# derived from its certificate fingerprint, so regenerating the cert changes
# the node's identity. On the second `docker compose up`, spire-certs minted
# a new keypair and spire-setup registered the workload under the NEW
# fingerprint, while the already-running spire-agent was still attested
# under the OLD one. The entry matched nothing, and every workload request
# failed with:
#
#   No identity issued ... registered=false
#
# The whole reason for moving off join_token was that node identity should
# be durable rather than one-shot. Regenerating it on every boot throws that
# away. So: generate once, reuse thereafter. To deliberately rotate, delete
# the spire-shared volume (which is what a full `docker compose down -v`
# does) and let this run again from clean.
if [ -f "$CERTS/agent.crt" ] && [ -f "$CERTS/agent.key" ] && [ -f "$CERTS/node-ca.crt" ]; then
  echo "[spire-certs] node keypair already present, reusing it"
  openssl x509 -in "$CERTS/agent.crt" -noout -fingerprint -sha1 2>/dev/null || true
  exit 0
fi

echo "[spire-certs] generating x509pop node CA and agent certificate"

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$CERTS/node-ca.key" -out "$CERTS/node-ca.crt" \
  -subj "/CN=governance.demo node CA" >/dev/null 2>&1

openssl req -newkey rsa:2048 -nodes \
  -keyout "$CERTS/agent.key" -out "$CERTS/agent.csr" \
  -subj "/CN=governance.demo agent node" >/dev/null 2>&1

# keyUsage=digitalSignature is REQUIRED, not decoration. Without it SPIRE
# rejects the node at attestation time with:
#   nodeattestor(x509pop): unable to generate challenge:
#   certificate not intended for digital signature use
# x509pop's challenge is a signature made with this key, so a certificate
# that does not assert that usage really is unusable for the protocol.
cat > /tmp/agent-ext.cnf <<'EXT'
keyUsage = critical, digitalSignature
extendedKeyUsage = clientAuth
EXT

openssl x509 -req -in "$CERTS/agent.csr" -days 3650 \
  -CA "$CERTS/node-ca.crt" -CAkey "$CERTS/node-ca.key" -CAcreateserial \
  -extfile /tmp/agent-ext.cnf \
  -out "$CERTS/agent.crt" >/dev/null 2>&1

rm -f "$CERTS/agent.csr"
chmod 644 "$CERTS"/node-ca.crt "$CERTS"/agent.crt
chmod 600 "$CERTS"/node-ca.key "$CERTS"/agent.key

echo "[spire-certs] wrote node-ca.crt, agent.crt, agent.key to $CERTS"
openssl x509 -in "$CERTS/agent.crt" -noout -ext keyUsage 2>/dev/null || true
