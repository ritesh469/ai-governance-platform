# Part 3 — Defending this project in an interview

Written to be honest. Nothing here asks you to overstate what you did — the
real work is interesting enough, and a fabricated claim collapses the moment
someone asks a follow-up.

---

## Start with the truth about provenance

**Say this early, unprompted:**

> "This started from an open-source teaching project by another developer.
> I got it running, found and fixed five real bugs in it, and added a
> lightweight deployment profile so it runs on a normal laptop. The original
> is credited in the repo's NOTICE file."

**Why volunteering it is the strong move:** an interviewer who discovers it
themselves has caught you out. An interviewer you tell up front sees someone
who understands attribution — which, in a project about governance and
compliance, is exactly the trait being tested. It also moves the
conversation straight onto your actual contributions, which is where you
want it.

Never say "I built a 7-layer AI governance platform from scratch." Say "I
took a governance platform, made it actually work, and hardened it."

---

## The strongest thing you did: the broken quality gate

This is your headline. Lead with it.

**The setup.** The model-promotion script runs each candidate through four
gates — coherence, safety, quality, tool-calling — and promotes whichever
passes and scores best. The quality gate is an LLM-judge score out of 5.

**The bug.** The code read the metric key `answer_correctness/v1/mean`. That
key is only emitted by MLflow's *built-in* judge. A custom metric emits
`answer_correctness/mean` — no `/v1/`. So:

```python
quality = metrics.get("answer_correctness/v1/mean", 0.0)   # always 0.0
```

Every candidate scored 0.0. The gate never failed anything, and the "best
model" was selected on coherence and latency alone.

**Why it was invisible.** Nothing errored. The pipeline ran green, models got
promoted, the log printed a number. It just wasn't the right number.

**The fix.** One accessor that tries both keys, used everywhere:

```python
def _quality(metrics, default=None):
    for key in ("answer_correctness/v1/mean", "answer_correctness/mean"):
        if metrics.get(key) is not None:
            return metrics[key]
    return default
```

**The proof it mattered** — the fix changed which model went to production:

| | quality | before fix | after fix |
|---|---|---|---|
| gpt-oss-20b | 3.5/5 | promoted (on a 0.0 tie-break) | Staging |
| qwen3.8-27b | **4.1/5** | Staging | **Production** |

**The line to land:**

> "A governance control that silently passes everything is worse than no
> control, because you trust it. It shipped green for months. The lesson I
> took is that any gate needs a test that proves it can actually *fail* —
> so I added one."

---

## Questions you will get, and honest answers

### "Why not just use AWS IAM / a cloud provider's tools?"

You could. The reason this stack is all self-hosted open source is
portability and inspectability: every policy is a file in the repo you can
read and test, rather than console state you have to click through. The
trade-off is real — you operate it yourself, and SPIRE in particular is
fiddly (see the known issue about join tokens). In a company already on AWS,
I would probably use IAM for workload identity and keep OPA for application
authorization, because OPA's rules are testable in CI.

### "Why OPA instead of `if` statements?"

Three reasons. Rules live in one place, so "who can issue refunds?" is
answerable by reading four files. They are unit-testable — there are 18 Rego
tests running in CI. And every decision lands in one decision log, which is
what makes the compliance evidence real rather than asserted.

The cost is a network hop per check and a second language to learn.

### "Is this actually production-ready?"

No, and I would not claim it. Containers still run as root. Dependencies are
pinned to versions with known CVEs. There is no horizontal scaling, no
secrets manager, and no TLS between services. SPIRE still uses
`insecure_bootstrap`, so the agent trusts the server's CA on first
connection rather than having it pre-shared out of band.

It is a working demonstration of the control patterns, not a deployment.

*(Saying this well is worth more than claiming otherwise. Interviewers are
testing whether you can assess your own work.)*

### "What would you do next?"

In order: run containers as non-root, upgrade the dependencies flagged by
`pip-audit`, then add tests around the promotion gate's *failure* paths —
right now I have tests that prove masking works, but the gate bug taught me
the important tests are the ones proving a control can reject.

### "Tell me about the lite profile."

The upstream project needs ~16GB of RAM for Docker alone, mostly because
OpenMetadata is four containers and about 5GB. I have 16GB total, so I could
not run it at all.

I gated those four behind a Docker Compose profile, so `docker compose up`
starts 11 services at about 2.2GB measured, and `--profile full` adds them
back. The subtlety was Layer 3: it reads PII column tags from OpenMetadata,
so without it that layer had nothing to work with. Rather than disable the
layer, I added a local tag file in the same shape. The tag *source* changes
between profiles; the masking *decision* is still OPA's in both. CI asserts
the lite profile stays lite.

### "How do you know it works?"

Six demo scenarios covering the allow path and four different block paths,
18 Rego policy tests, 10 Python tests, and a compliance report that pulls
real evidence from real logs — including verifying the audit log's hash
chain rather than just counting rows. All of it runs in CI.

### "What is the hash chain for?"

Tamper evidence. Each audit entry hashes its own content plus the previous
entry's hash. Editing entry 5 breaks entry 6's hash and every one after it,
so you cannot quietly rewrite a decision you regret. The compliance report
verifies the chain and reports the result as part of the evidence — counting
log entries would prove nothing about whether they had been altered.

---

## The other four bugs, in one line each

1. **Dead model.** The project pinned Groq's `llama-3.1-8b-instant`, which
   Groq has retired. Every evaluation 404'd. Repointed to a live model.

2. **Unbounded output.** No `max_tokens` anywhere, so Groq's free tier
   rejected requests outright — it estimates output up front and refused an
   estimated 1168 tokens against a 1000/minute ceiling. Capped at all four
   call sites. Bounding output is correct for an eval harness anyway: a
   degenerate model that loops should be cut off, not left running.

3. **Invisible logs.** No `PYTHONUNBUFFERED`, so every `print()` from the
   startup automation was buffered and never appeared. Startup failures
   looked like silence — this is why the first run seemed to do nothing.

4. **Fail-open data layer.** When the catalog was unreachable, the code
   masked *nothing* and served the row. I made it configurable and
   documented why fail-closed is the right default: an unreachable catalog
   is not evidence that a column is safe.

---

## Things you should be able to draw on a whiteboard

**The seven layers, in order:**

```
Identity -> Policy -> Data -> Model -> Guardrails -> Tool-call -> Logged
```

**The one non-obvious detail:** OPA is queried at layers 3, 5 *and* 6. It is
one shared policy hub, not a single stage in the pipeline. That is the
design point worth pointing at.

**Short-circuiting:** any layer can jump straight to `logged` via
LangGraph's `Command(goto=...)`. A blocked request is still logged — you
need the record of the denial as much as the record of the allow.

---

## If you are asked something you do not know

Say so, then reason out loud. "I haven't used SPIRE in production, so I
don't know how it behaves under node churn — but based on the join-token
problem I hit locally, I'd expect re-attestation to be the hard part."

That answer is worth more than a confident guess. Interviewers are
calibrating how much they could trust your claims about a system you built,
and someone who signals uncertainty accurately is more trustworthy than
someone who never does.
