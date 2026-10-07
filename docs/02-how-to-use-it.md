# Part 2 — Running it and using the dashboard

A walkthrough you can follow start to finish, and repeat live in a demo.

---

## Before you start

You need:

- **Docker Desktop**, running. Settings → Resources → Memory: **8GB** is
  plenty for the default profile.
- **An OpenAI API key** — from [platform.openai.com](https://platform.openai.com/api-keys).
  Needs credit on the account; a full evaluation run is roughly 40 short calls.

```bash
cp .env.example .env
```

Open `.env` and set `OPENAI_API_KEY=sk-proj-...`. Two rules that cause most
first-time failures:

- Use `=`, not a dash. `OPENAI_API_KEY — sk-...` silently sets nothing.
- Use the site's **copy button**. Selecting the key by hand can grab an
  extra character, and the key then fails with a 401.

An expired key stays expired: adding credit to the account does not revive
it. Create a new key instead.

`LANGFUSE_PUBLIC_KEY` and `LANGFUSE_SECRET_KEY` are not fetched from
anywhere — you invent them, and Langfuse creates the project from whatever
you put there on first boot. Generate them with `openssl rand -hex 16`.

---

## Start the stack

```bash
docker compose up -d --build
```

First run pulls about 4.4GB of images and builds two of its own. Check
progress:

```bash
docker compose ps
```

You want 10 services `running` and `spire-setup` `exited` — that one is a
one-shot job that mints SPIRE's join token and is *supposed* to finish.

The agent then registers both model versions and runs a real evaluation
against both. That takes a few minutes and makes real API calls. Watch it:

```bash
docker compose logs -f agent
```

You are waiting for `promote_model.py exit=0`.

---

## The URLs

| URL | What it is |
|---|---|
| **http://localhost:8501** | **The dashboard — start here** |
| http://localhost:5000 | MLflow — model versions and evaluation runs |
| http://localhost:3000 | Langfuse — request traces |
| http://localhost:8080 | Keycloak admin (`admin` / `admin_change_me`) |
| http://localhost:8181 | OPA API |
| http://localhost:8000/health | Agent health + its SPIFFE ID |

---

## Using the dashboard

### Log in

Two accounts, and **which one you pick is the whole point**:

| Account | Password | What it can do |
|---|---|---|
| `student` | `student123` | order lookups, refunds |
| `instructor` | `instructor123` | everything, including purging data |

There is no role dropdown. Your permissions come from the signed token
Keycloak issues. That is the design — a role you can *select* is a role an
attacker can select.

### Send a request

Type into the chat box, for example:

```
What is the status of order 1?
```

You get an answer, and the **seven layer lights** update live. Click any
layer to see the real reason from that layer's own logs.

### The tabs

- **Governance** — the seven-layer checklist for the last request
- **Live Database** — the actual Postgres rows, so you can watch a refund
  land after Scenario F
- **Compliance Report** — the generated report with real evidence

---

## The six demo scenarios

Each is one command. Run them in order in a demo — the story builds.

### A — everything allowed

```bash
docker compose exec agent python demos/scenario_a_approved.py
```

All seven layers pass. Note that `data` still reports
`columns to mask this request: ['email']` — masking happened even on the
happy path.

### B — unauthorized agent handoff (the best one)

```bash
docker compose exec agent python demos/scenario_b_policy_block.py
```

A `student` tries to reach `admin_agent`. Blocked:

```
tool_call  pass=False  routing to 'admin_agent' forced by request, but denied:
           role 'demo-agent' not permitted to call tool 'route:admin_agent'
```

**Say this out loud in a demo:** the *handoff itself* needed permission. The
admin agent's tools were never reachable — we did not block a dangerous tool
call, we blocked getting to where dangerous tools live.

### C — PII caught on the way out

```bash
docker compose exec agent python demos/scenario_c_pii_mask.py
```

Layer 3 masked the email column, and the model *still* produced an email
address in its prose — so the output guardrail withheld the response:

```
agent_guardrails  pass=False  output still contains an unmasked email address
```

That is defence in depth working. One layer missed; the next caught it.

### D — kill switch

```bash
docker compose exec agent python demos/scenario_d_killswitch.py
```

Revokes the agent's identity, proves the next request is blocked at Layer 2,
then restores it automatically.

### E — model stage gate

```bash
docker compose exec agent python demos/scenario_e_model_stage_gate.py
```

Pins the request to the Staging model version. Blocked at Layer 4 **before
any LLM call** — no tokens spent on a request that was never going to be
allowed.

### F — an authorized write

```bash
docker compose exec agent python demos/scenario_f_refund_write.py
```

A real refund written to real Postgres. Check the dashboard's Live Database
tab afterwards.

---

## Tests

```bash
# 18 Rego policy tests
docker compose run --rm opa test /policies -v

# 10 Python tests
docker compose run --rm agent sh -c \
  "pip install -q -r requirements-dev.txt && python -m pytest tests/ -v"
```

Both run automatically in CI on every push.

---

## The compliance report

```bash
docker compose exec agent python compliance/generate_report.py
```

Writes `compliance/reports/compliance_report.md` and prints a score. Every
row cites real evidence — decision-log counts with hash-chain verification,
MLflow model-card text, kill-switch log entries, Langfuse trace counts.

Current run: **7/8**. The eighth needs a companion package that is only a
name-reservation stub on PyPI, and the report says so rather than quietly
claiming a pass.

---

## Switching profiles

```bash
MODEL_PROFILE=openai   # the only profile that ships
```

Both the champion and the challenger are OpenAI models, so `OPENAI_API_KEY`
is the single key this project needs. To add another provider, add a profile
to `model-governance/model_card.yaml` — the judge already falls back to a
provider-agnostic implementation for anything MLflow cannot address.

Change it in `.env`, then `docker compose up -d --force-recreate agent`.
Switching registers **new** model versions rather than mutating the old
ones — a different underlying model genuinely is a different version, and
the registry should show that history rather than hide it.

To run the full stack with the real OpenMetadata catalog:

```bash
docker compose --profile full up -d --build
```

Close other applications first — that is ~8.5GB.

---

## When something breaks

**Agent exited, complains about the SPIFFE socket.** SPIRE's join token is
single-use and the agent shuts down when its SVID expires. See the known
issue in `RUNNING.md`. Recovery:

```bash
docker compose up -d --force-recreate spire-setup
docker compose up -d --force-recreate spire-agent
docker compose up -d agent
```

**`Incorrect API key provided` or `Your API key has expired`.** Create a new
key at platform.openai.com/api-keys and replace the value in `.env`. Adding
credit does not revive an expired key.

**`no credits remaining` from OpenAI.** The account has no balance. Add
credit at platform.openai.com/settings/organization/billing.

**Everything is slow / containers dying.** Docker needs more memory, or you
started the `full` profile on a 16GB machine.

**Start completely fresh** (deletes all data — models, traces, database):

```bash
docker compose down -v
docker compose up -d --build
```
