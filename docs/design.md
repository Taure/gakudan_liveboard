# gakudan_liveboard - design & research

Status: design (2026-05-27). The app is a Nova + Datastar dashboard with a run
list and a live transcript; this document defines what it should become.

## 1. Positioning: a live ops console, not a trace explorer

The LLM-observability space (LangSmith, Langfuse, Arize Phoenix, AgentOps,
Helicone, Braintrust, Weave) is crowded with **post-hoc trace explorers**: you
run agents, traces land in a store, you explore them later. gakudan already has
that lane covered by two sister libraries:

- `gakudan_metrics` - Prometheus aggregates (fleet-level, after the fact).
- `gakudan_otel` - OpenTelemetry span trees (per-run traces, after the fact).

`gakudan_liveboard` is deliberately the **third** thing those don't do: the
**real-time, human-readable operations console** for a running gakudan node.
You open it and *watch agents collaborate as it happens* - tokens streaming in,
turns being taken, the router deciding, guardrails firing, the budget burning -
and you can **intervene** (interrupt / resume / cancel) live.

It is not trying to be Langfuse. It is the lit conductor's stand in front of the
orchestra while the piece is being played.

## 2. What the field offers, and what people actually ask for

From the 2026 landscape and developer discussion (Reddit/HN/GitHub), the
recurring **table stakes** are:

- Hierarchical traces - every LLM call, tool invocation, retrieval step, with
  filtering by user / session / cost / latency.
- Token, cost, and latency metrics (P50/P99), per run and aggregate.
- Tool-call inspection - inputs, outputs, status.
- Multi-agent workflow visualisation; time-travel / session replay.
- Annotation queues that turn flagged runs into evaluation datasets.
- Alerting on quality (faithfulness, safety, drift), not just infra failures.

And the recurring **unmet wants**, in their words:

- *"Deep step-by-step visibility - black-box monitoring doesn't work for
  multi-step agents."*
- *"AI quality isn't engineering-only - PMs, QA, and domain experts need to
  validate behaviour without writing a script."* (cross-functional read access)
- *"Close the loop - let domain experts annotate a run, turn it into an eval
  case."*
- *"The primary failure is inaccurate output - irrelevant, incorrect, or
  **leaking private information**."* (safety + PII visibility)
- Self-hosting / data residency keeps coming up for regulated EU/finance/health
  shops: *"the data must stay inside our perimeter; we must be able to delete a
  user's data on a GDPR request without waiting for a vendor."*

Sources: [LangSmith](https://www.langchain.com/langsmith/observability),
[Langfuse](https://langfuse.com/docs/observability/overview),
[Langfuse self-hosting](https://langfuse.com/self-hosting),
[AI observability comparison (Softcery)](https://softcery.com/lab/top-8-observability-platforms-for-ai-agents-in-2025),
[Agent observability ranking (Laminar)](https://laminar.sh/article/2026-04-23-top-6-agent-observability-platforms),
[Garvata - debugging the agent stack (HN)](https://news.ycombinator.com/item?id=42293942).

## 3. gakudan's distinct angle

gakudan_liveboard wins on the four things the Python dashboards structurally
cannot do as well:

1. **It is live.** The board is server-rendered on the BEAM and streams diffs
   over SSE (Datastar) as the blackboard is appended and tokens stream, with no
   polling and no client framework. Watching a run is the product, not a replay
   of one.
2. **The supervision tree *is* the agent graph.** Every other tool reconstructs
   a graph from emitted spans. gakudan has a *real* OTP process tree per run -
   so the board can show live process state, crashes, restarts, and supervised
   resume as they happen. "Agent orchestration is a supervision tree" is the
   demo no one else can give.
3. **Human-in-the-loop is built in.** gakudan ships `interrupt/2`, `resume/2`,
   `cancel/1`. The board exposes them as live controls - pause a run for
   approval, resume it, kill a runaway generation - which read-only dashboards
   don't.
4. **Self-hosted by construction.** It runs *inside* the BEAM node it observes.
   No external store (no ClickHouse, no Docker-compose sprawl), no CDN, no
   third-party fonts or trackers. Nothing leaves the perimeter - the regulated
   default, not a paid tier.

## 4. What to show (mapped to gakudan's real surface)

Everything below already exists in gakudan as telemetry, blackboard entries,
the registry, stream pubsub, budget, guardrail decisions, or audit events - the
board *reads* it, it does not add instrumentation.

### MVP (v0.1)
- **Run index** - active + recent runs. Per run: id, status
  (`initialising | idle | running | awaiting_human | completed | error |
  cancelled`), actor / tenant, agent ids, turn count, tokens in/out, started,
  duration, a live pulse for running runs. Filter by status / actor / tenant.
- **Run detail - the transcript.** The blackboard, role-attributed
  (user / agent / system), agent-coloured, appended live, with **token-level
  streaming** for the in-flight agent (the headline view).
- **Turn timeline** - a vertical "score" of turns: which agent, when, duration,
  tokens. Fan-out rounds shown as parallel staves.
- **HITL controls** - Interrupt / Resume / Cancel buttons wired to the gakudan
  API, with the current state gating which are enabled.

### v1
- **Tool calls** - name, arguments, result, ok/error, per turn (collapsible).
- **Router decisions** - `next` / `handoff` / `fanout` / `done`, and who's next.
- **Guardrail decisions** - allow / transform / block, which guardrail, reason.
  (Directly answers the "is it leaking private info / safety" want.)
- **Budget gauge** - tokens & calls vs cap, live, turning amber/red near the
  ceiling; shows the `budget_exceeded` stop when it happens.
- **Audit trail** - `run_started/resumed/interrupted/stopped` + guardrail events
  with actor, read from the audit sink.
- **Process / supervision view** - the per-run sup tree, worker pids, and any
  crash → restart → resume, live.

### Later / maybe
- **Annotate a run → export a `gakudan_eval` case.** Closes the feedback loop
  the field keeps asking for, and gakudan already has the eval harness to
  receive it.
- **PII reveal control** - transcripts render redacted by default; revealing raw
  content is a gated, audited action (see §5).
- Cross-links to `gakudan_metrics` (Grafana) and `gakudan_otel` (trace backend)
  for the after-the-fact view.
- Run search / filter across history; saved views per team.

### Explicitly out of scope
Eval dataset management, prompt CMS/playground, and a hosted SaaS - those are a
product, not a live console, and the field is saturated with them.

## 5. GDPR & privacy by design

The board renders run transcripts, which routinely contain personal data, so it
is a personal-data processor and is designed as one:

- **No third-party requests, ever.** All assets - fonts, CSS, JS - are bundled
  in `priv/static/assets` and served from the same origin. No Google Fonts, no
  CDN, no analytics, no trackers, no external images. A strict
  `Content-Security-Policy` (`default-src 'self'`) is part of the design - set
  at the Nova layer (see §8) so a stray external URL fails loudly rather than
  silently phoning home. The prototype already makes zero off-origin connections.
- **Self-hosted fonts.** IBM Plex Mono + Instrument Serif (both SIL OFL), latin
  subset, ~105 KB total, fetched at build time by `scripts/fetch-fonts.sh` into
  `priv/static/assets/fonts` and `@font-face`'d from there. Never loaded from a
  font CDN at runtime.
- **No second copy of the data.** The board reads gakudan's blackboard and audit
  records live; it does not persist its own store. Retention and right-to-erasure
  live with gakudan's checkpointer - delete the run there and it is gone here.
- **Data minimisation + reveal-on-demand.** Default to redacted transcripts
  (honouring the guardrail boundary); revealing raw content is an explicit,
  permissioned, audited action.
- **Auth in front.** Runs are not exposed unauthenticated; the board sits behind
  the host app's auth (Nova middleware). Access itself is an audit event.

## 6. Design language - "the conductor's console"

gakudan is 楽団, an orchestra. The board is the lit conductor's stand in a dark
hall: a calm, precise instrument panel, warmed by an editorial/score voice so it
reads as a *program*, not a terminal.

- **Type.** `Instrument Serif` for the wordmark, run titles, and section
  headings - the human, editorial voice. `IBM Plex Mono` for everything else -
  labels, body, ids, tokens, transcript - the instrument-panel voice. Both
  self-hosted, both OFL. (Deliberately *not* Inter/Roboto/system.)
- **Colour.** Deep ink blue-black ground with subtle layered depth and a faint
  grain - a dark hall, not a flat `#000`. Warm "paper" off-white text.
  **Brass/amber** is the single primary accent (orchestral, warm - not the
  ubiquitous SaaS purple). A cool **cyan "signal"** marks *live* / streaming.
  Semantics: green = idle/ok, amber = awaiting-human, red = error/blocked,
  muted slate = done/inactive.
- **Motion, used sparingly.** A metronome/baton **pulse** on running runs; a
  soft streaming caret on the in-flight token text; staggered reveal as new
  transcript entries arrive. Nothing decorative that an operator staring for an
  hour would come to hate.
- **Layout.** A left **score index** (runs), a centre **transcript** (the
  performance), and a right **rail** of instruments (turn timeline, tools,
  guardrails, budget, audit, process tree). Hairline dividers, generous space,
  data in mono, headings in serif.

A static, fully self-hosted prototype of this language lives at
`docs/prototype/index.html` (run index + run detail) - it is the visual spec the
Nova + Datastar pages are ported from, and it makes zero off-origin requests.

## 7. Architecture

Nova for routing/auth/static, Datastar (SSE) for the live updates.

- **Data sources (all existing):** `gakudan_registry` for the run list; the per
  run `gakudan_blackboard` pub/sub (`{gakudan_blackboard, RunId, {entry_added,
  _}}`) for the transcript; `gakudan_stream` subscription for token deltas;
  the gakudan `:telemetry` surface for turn/llm/tool/router/budget events; the
  audit sink for the audit trail; `gakudan:interrupt/resume/cancel` for HITL.
- **Pages and stream:** `gakudan_liveboard_page_controller` server-renders the
  index and run-detail pages; `gakudan_liveboard_sse` registers a `{stream, ...}`
  Nova return-handler that subscribes to the relevant pub/sub and pushes
  `datastar:patch_elements` frames over SSE.

## 8. Next steps

1. Port the prototype's CSS + structure into the layout and the two pages.
2. Wire the right-rail instruments to telemetry + audit (read-only first).
3. Wire the HITL buttons to `gakudan:interrupt/resume/cancel`.
4. Add the CSP header + the `fetch-fonts.sh` build step to CI.
5. Then: process/supervision view, redaction reveal, eval-case export.
