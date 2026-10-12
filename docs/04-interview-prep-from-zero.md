# Part 4 — Interview prep, starting from zero

For the state of "I don't know any of this yet."

Parts 1–3 explain the system. This part tells you **what to study, in what
order, and what to memorise word for word.** Work through it in five sittings
of about an hour. Do not try to do it in one night; the Day 1 answers have to
be automatic before Day 4 makes sense.

Everything you are told to say here is true. Nothing in this file asks you to
claim work you did not do.

---

## The three things you memorise cold

Everything else you can reason out live. These three you should be able to say
in your sleep, because they are the first thing asked and the answer sets the
tone for the rest of the interview.

### 1. The 30-second pitch

> "It's an AI governance platform. The idea is that an AI agent with real
> permissions — reading customer data, issuing refunds, deleting records —
> needs the same controls a human employee would have. So every request passes
> seven layers: who are you, is your identity still valid, is this data
> sensitive, is this model approved, is this input an attack, are you allowed
> to call this specific tool, and then everything gets written to an audit log.
> If any layer denies, the request stops and the denial is logged too."

### 2. The provenance answer

Asked as "did you build this?" — and it *will* be asked.

> "No — I contributed to it. It's an open-source teaching project that didn't
> work when I picked it up. I got it running, found five real bugs, and added
> tests and CI. The original author is credited in the repo."

Say it plainly and move on. Do not apologise for it. In a project about
governance and compliance, demonstrating that you handle attribution correctly
is the point, not a weakness.

### 3. The bug story

Your headline. Full version in [Part 3](03-interview-guide.md); the short form:

> "The model-promotion gate scored every candidate 0.0 because it read the
> metric key `answer_correctness/v1/mean`, which only MLflow's built-in judge
> emits — the custom judge emits `answer_correctness/mean`, without the
> `/v1/`. So the quality gate never failed anything and models were being
> promoted on coherence and latency alone. Nothing errored; the pipeline ran
> green. After the fix, a different model got promoted.
>
> A governance control that silently passes everything is worse than no
> control, because you trust it. Any gate needs a test proving it can
> actually fail — so I added one."

---

## The five-day plan

### Day 1 — vocabulary only

Read [Part 1](01-concepts-from-scratch.md) sections 1–8. Do not touch the
code. Your only goal is that none of these words feel foreign tomorrow.

Then write out the Level 1 answers below from memory. Not perfectly — just
close enough that you are not blank.

### Day 2 — the rest of the vocabulary

Part 1, sections 9–14. Same drill.

By the end of Day 2 you should be able to answer every Level 1 question in
one sentence, out loud, without reading.

### Day 3 — run it

Follow [Part 2](02-how-to-use-it.md). Actually start the stack and click
through the dashboard. Watch a request get allowed, then watch one get denied.

This matters more than it sounds. An interviewer can tell within two questions
whether you have seen the thing run. Reading about a denial and watching one
land in the audit log are different kinds of knowing.

### Day 4 — your own contribution

Read [Part 3](03-interview-guide.md) properly. Memorise the three blocks at
the top of this file. Then open the actual commits:

```bash
git log --oneline
git show <the quality gate commit>
```

Look at the diff for each of your five bugs. You need to be able to say what
the code looked like before and after, because "tell me more about that bug"
is the obvious follow-up to your own headline.

### Day 5 — rehearse out loud

Work through the Level 2 and Level 3 questions below, speaking the answers.
Out loud, not in your head — the gap between the two is where interviews go
wrong.

Finish by drawing the request path on paper from memory: seven layers, in
order, no notes.

---

## Level 1 — the basics

One sentence each. If you cannot do these, nothing else will land.

**What is AI governance?**
> Making sure an AI system can only do what it is allowed to do, and that
> there is a record proving what it did.

**What is an AI agent?**
> An LLM that can take actions through tools — call an API, read a database,
> issue a refund — not just produce text.

**What is a container? What is Docker Compose?**
> A container packages an application with everything it needs so it runs the
> same anywhere. Compose starts many containers together as one system — this
> project has sixteen services.

**Authentication vs authorization?**
> Authentication is who you are. Authorization is what you are allowed to do.
> Keycloak answers the first, OPA answers the second.

**What is OIDC? What is Keycloak?**
> OIDC is the standard protocol for proving who a user is. Keycloak is the
> server that implements it and issues the tokens.

**What is a JWT?**
> A signed token carrying claims about the user — who they are, what roles
> they have. Signed, so it cannot be altered; readable, so it should not hold
> secrets.

**What is SPIFFE / SPIRE?**
> Identity for *software*, not people. Keycloak proves a human is logged in;
> SPIRE proves a service is the service it claims to be, using short-lived
> certificates instead of a shared password in a config file.

**What is OPA? What is policy as code?**
> Open Policy Agent is a separate service that answers allow/deny questions.
> Policy as code means those rules live in their own files, versioned and
> tested, instead of being scattered through the application as `if`
> statements.

**What is PII?**
> Personally identifiable information — email, phone, address. This project
> masks it before the model ever sees it, so it cannot be leaked in a reply.

**What is a model registry? What is a promotion gate?**
> MLflow stores model versions and their stage — Staging, Production. A
> promotion gate is the check a model must pass before it is allowed to move
> to Production. This is where my headline bug was.

**What are guardrails?**
> Checks on the input and the output. Input: is someone trying a prompt
> injection. Output: did the model leak something or say something unsafe.

**What is an audit log? What is a hash chain?**
> A record of every decision. Each entry includes a hash of the previous
> entry, so deleting or editing an old row breaks the chain and the tampering
> becomes detectable.

**What is a kill switch?**
> One flag that stops an agent immediately, without a redeploy. The point is
> speed — if something is going wrong you cannot wait for a release.

**What is LangGraph?**
> A framework for building multi-agent systems as a graph: nodes are steps,
> edges are what runs next. This project has three agents and routes between
> them.

---

## Level 2 — about this project specifically

**Walk me through what happens when a user asks a question.**
> It hits the seven layers in order. Keycloak validates the JWT and the user's
> roles. SPIRE confirms the calling service's identity. The data layer looks
> up which columns are sensitive and masks them. MLflow is checked so only an
> approved model version serves traffic. Guardrails scan the input for
> injection. OPA decides whether this user may call this specific tool. Then
> the result and the decision go into the audit log. A denial at any layer
> stops it there — and the denial is logged too.

**Why seven layers? Isn't one check enough?**
> Because they fail differently. A valid token does not mean the user should
> see this column. An approved model does not mean the input is safe. Each
> layer answers a question the others cannot.

**What is the smartest part of the design?**
> Agent-level isolation. There are three agents — orders, billing, admin — and
> a normal user is blocked from reaching the admin agent at the routing stage.
> Not "you may not press delete" but "you may not enter the room where delete
> exists." Blocking at routing is stronger than blocking at the tool, because
> the dangerous capability is never in reach.

**Why OPA instead of `if` statements in the code?**
> Three reasons. The rules are testable on their own — there are eighteen Rego
> tests. They can be changed without redeploying the app. And an auditor can
> read the policy files directly instead of hunting through application code.

**Tell me about the lite profile.**
> The full stack needs about 8.5 GB and I have a 16 GB laptop, so it could not
> run. I split it into Docker Compose profiles — twelve of the sixteen
> services in the default profile, which measures about 2.2 GB. The four
> heavy services are opt-in.

**How do you know it works?**
> Eighteen Rego policy tests that were already in the project, ten Python
> tests I added, and a four-job CI pipeline: policy tests, unit tests, config
> validation, and secret scanning plus dependency audit. The important one is
> the test I added that proves the quality gate can fail — that is the test
> that would have caught my headline bug.

**Is this production-ready?**
> No, and I would not claim it is. Containers run as root, the credentials in
> the repo are placeholders, and it is local-only. It demonstrates the control
> patterns; hardening it for production is a separate piece of work.

---

## Level 3 — the harder ones

**What would you do next?**
> Patient-level or tenant-level separation in the audit store, proper secret
> management instead of environment files, and non-root containers. And I
> would want the quality gate tested against a model I know is bad, not just
> one I know is good — a gate you have only seen pass is a gate you have not
> really tested.

**Why not just use AWS IAM or a cloud provider's tools?**
> IAM controls which *service* may call which *API*. It does not know that
> this column is PII, that this model version is unapproved, or that this
> input looks like a prompt injection. Those are application-level decisions,
> and they are what this project is about.

**What was the hardest bug?**
> Not the headline one — that was subtle but, once found, a one-line fix. The
> hardest was SPIRE node attestation. The whole stack died about every hour
> and the logs did not say why. The agent was using a join token, which is
> single-use: fine at first boot, useless when the agent needed to
> re-attest. Switching to x509pop certificates, which can re-attest, fixed it.

**What did you learn?**
> That silent failures are the dangerous ones. Four of my five bugs produced
> no error at all — the quality gate scored 0.0 and ran green, the logs were
> buffered so startup failures looked like silence, the data layer failed open
> and served unmasked rows. A system that crashes tells you something is
> wrong. A system that quietly does the wrong thing does not.

---

## Self-test

Tick these only when you can do them with nothing in front of you.

- [ ] Say the 30-second pitch without stumbling
- [ ] Name all seven layers, in order
- [ ] Answer every Level 1 question in one sentence
- [ ] Explain the quality-gate bug, including why it was invisible
- [ ] Say the provenance answer without sounding apologetic
- [ ] Draw the request path on paper
- [ ] Name the five bugs
- [ ] Explain why agent-level isolation beats tool-level blocking
- [ ] State two things wrong with the project

That last one matters. Someone who can only praise their own project has not
understood it.

---

## When you do not know

You will get a question you cannot answer. Everyone does. The answer is not
to guess:

> "I don't know. My guess would be X, but I'd want to check before saying so."

Then stop. Interviewers are not testing whether you know everything — they are
testing whether you will quietly make something up when you don't. In a
governance interview specifically, saying "I don't know" *is* a correct
answer to give.

Never claim you wrote code you did not write. The eighteen Rego tests were
already in the project; the ten Python tests are yours. If you blur that and
they ask you to walk through a Rego test, the interview is over — and it ends
over something you never needed to claim in the first place.
