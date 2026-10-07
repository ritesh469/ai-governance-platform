#!/usr/bin/env bash
# Runs once when the Codespace is created.
#
# Deliberately does NOT start the stack. Starting it would make real LLM API
# calls, and the person opening this Codespace has not supplied a key yet —
# so it would fail in a confusing way before they had a chance to. Instead:
# prepare everything, then tell them the one thing they have to do.
set -euo pipefail

cd "$(dirname "$0")/.."

if [ ! -f .env ]; then
  cp .env.example .env

  # LANGFUSE_PUBLIC_KEY / LANGFUSE_SECRET_KEY are not fetched from anywhere —
  # Langfuse's headless init creates the project from whatever values it finds
  # here on first boot. Generating them removes a manual step that otherwise
  # confuses everyone the first time.
  PUB="pk-lf-$(openssl rand -hex 16)"
  SEC="sk-lf-$(openssl rand -hex 16)"
  sed -i "s|^LANGFUSE_PUBLIC_KEY=.*|LANGFUSE_PUBLIC_KEY=${PUB}|" .env
  sed -i "s|^LANGFUSE_SECRET_KEY=.*|LANGFUSE_SECRET_KEY=${SEC}|" .env
  echo "[setup] created .env with generated Langfuse keys"
fi

pip install --quiet --no-input -r requirements-dev.txt pyyaml 2>/dev/null || true

# Pull base images now so the first `docker compose up` is quick. Build-only
# services are skipped; a failure here is not fatal, it just means the pull
# happens later.
docker compose pull --ignore-buildable --quiet 2>/dev/null || true

cat <<'BANNER'

  ======================================================================
   AI Governance Platform — Codespace ready
  ======================================================================

   ONE thing left: add an OpenAI API key.

     1. Get one at https://platform.openai.com/api-keys
     2. Open the file  .env  (it is already here)
     3. Put it on the OPENAI_API_KEY line, keeping the '=':

          OPENAI_API_KEY=sk-proj-your-key-here

        No spaces around '=', no quotes, nothing after the key.

   Then start everything:

          docker compose up -d --build

   First boot takes a few minutes: it registers two model versions and
   runs a real evaluation against both before either may serve traffic.
   Watch it with:

          docker compose logs -f agent

   When the dashboard port is forwarded, open it and log in as
   student / student123.

   Tests need no API key at all:

          python -m pytest tests/ -v
          docker compose run --rm opa test /policies -v

  ======================================================================

BANNER
