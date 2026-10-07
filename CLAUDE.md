# CLAUDE.md

Guidance for Claude Code (and any AI assistant) working in this repository.

## What this project is

A local AI governance platform: a LangGraph multi-agent system where every
request passes through seven governance layers before it may answer. Each
layer is enforced by a real, self-hosted open-source tool — no mocks.

```
identity -> policy -> data -> model -> guardrails_input -> routing
   -> route_authz -> tool_select -> tool_authz -> agt_execute
   -> final_answer -> guardrails_output -> logged
```

Any node can short-circuit to `logged` via LangGraph's `Command(goto=...)`
the moment a layer denies. The graph **is** the control flow — it is not a
diagram describing code that does something else.

| Layer | Tool | Lives in |
|---|---|---|
| 1 Identity | Keycloak (OIDC) + SPIFFE/SPIRE | `agent/keycloak_auth.py`, `identity/` |
| 2 Policy | Open Policy Agent | `policy/policies/*.rego` |
| 3 Data | OpenMetadata *or* local tag file | `agent/om_client.py`, `data-governance/` |
| 4 Model | MLflow Model Registry | `model-governance/` |
| 5 Agent | Guardrails AI + Agent Governance Toolkit | `agent/governance_middleware.py` |
| 6 Tool-call | Open Policy Agent (again) | `policy/policies/tool_access.rego` |
| 7 Logged | Langfuse + hash-chained Postgres audit log | `agent/audit_log.py` |

OPA is deliberately queried from layers 3, 5 and 6 — it is one shared policy
hub, not a single stage.

## Running it

```bash
docker compose up -d --build          # lite profile, ~2.2GB, 11 services
docker compose --profile full up -d   # adds OpenMetadata, ~8.5GB, 15 services
```

Read `RUNNING.md` before changing anything about the profiles.

## Non-negotiable rules

**Never weaken a governance control to make a demo pass.** If a layer blocks
something, that is the product working. Fix the request or the policy — with
a reason — rather than bypassing the check.

**Fail closed when a control cannot be evaluated.** `DATA_LAYER_FAIL_MODE`
exists because the original code served unmasked data when the catalog was
unreachable. An unreachable control is not a passing control. New controls
should follow the same principle.

**No mocks, stubs, or simulated governance decisions.** Every check must hit
a real running service. If a service is unavailable, say so explicitly in the
layer result — never fabricate a pass.

**Evidence must name its source.** The compliance report states which tag
source produced a PASS. A reader must be able to tell which profile generated
a report. Do not emit a bare "PASS" that hides where it came from.

**Never commit `.env`.** It holds real API keys. It is gitignored — keep it
that way. Run a secret scan before any push.

## Gotchas that have bitten before

- **Python output buffering.** Containers set `PYTHONUNBUFFERED=1`. Without
  it `print()` output is invisible and startup failures look like silence.
- **Metric key drift.** MLflow's built-in judge emits
  `answer_correctness/v1/mean`; a custom `make_metric` emits
  `answer_correctness/mean`. Always read through `_quality()` in
  `promote_model.py`, never a hardcoded key. Reading one key silently
  scored every candidate 0.0.
- **Unbounded completions.** Always pass `max_tokens`. This was found on a
  free tier that estimates output up front and rejects oversized requests,
  but bounding output is correct regardless: a degenerate model that loops
  should be cut off, not left to run.
- **Provider URIs.** MLflow genai metrics understand `openai:/...` and
  gateway URIs only. Any other provider must use this repo's own judge
  (`_make_llm_judge` in `promote_model.py`). Only the `openai` profile
  ships today; that fallback is the extension point for adding another.
- **Compose profiles.** A service without a profile cannot `depends_on` a
  profile-gated service, or Compose refuses to start.
- **Line endings.** Shell scripts mounted into Linux containers must stay
  LF. `.gitattributes` enforces this; CRLF breaks `init_db.sh` silently.
- **Model versions are immutable.** Changing a model in `model_card.yaml`
  registers a NEW version. Do not mutate an existing one to hide history.

## Testing

```bash
docker compose run --rm opa test /policies -v          # 18 Rego policy tests
docker compose run --rm agent sh -c \
  "pip install -q -r requirements-dev.txt && python -m pytest tests/ -q"
```

Both run in CI on every push. Add a test with any behaviour change —
especially to a policy, where an untested rule is an unenforced one.

## Style

Match the surrounding code. This codebase comments the *why*, not the what,
and is unusually explicit about its own limitations — preserve that. When
something is a known weakness, say so in the comment rather than hiding it.
