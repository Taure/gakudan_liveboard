# AGENTS.md

Working agreement for **gakudan_liveboard** - a live web dashboard for gakudan
runs. **Nova + Datastar** (no Arizona).

## Ecosystem

A gakudan sister library in a BEAM-native multi-agent stack (all under
https://github.com/Taure):

- **[gakudan](https://github.com/Taure/gakudan)** - agent orchestration runtime
  (this dashboard visualises its runs).
- **[saiten](https://github.com/Taure/saiten)** - runtime-agnostic eval/scoring
  + CI gate.
- **[madoguchi](https://github.com/Taure/madoguchi)** - MCP *server* framework.
- **[sekisho](https://github.com/Taure/sekisho)** - LLM gateway / control plane.

Other gakudan sisters: gakudan_metrics, gakudan_otel, gakudan_tickets
(+ gakudan_tickets_github).

**This repo** is the "conductor's console". The `{stream, ...}` Nova
return-handler in `gakudan_liveboard_sse` (it `stream_reply`s and never returns,
so Nova's buffered reply never fires) is the reference pattern for true SSE
through Nova - relevant to sekisho's deferred push-streaming.

## Architecture

Arizona was dropped: it migrated to its own roadrunner HTTP server, breaking the
Nova/cowboy + arizona_nova bridge. The board is now a plain Nova app that serves
server-rendered HTML and streams live updates over SSE via Datastar.

- `gakudan_liveboard_router` - Nova routes: `/`, `/runs/:run_id`,
  `/sse/runs/:run_id` (SSE), `/runs/:run_id/{interrupt,resume,cancel}` (POST),
  `/heartbeat`, `/assets/[...]`.
- `gakudan_liveboard_page_controller` - server-renders the conductor's-console
  pages (3-column shell + instrument rail) and exports `rail_html/2`.
- `gakudan_liveboard_sse` - **the live stream**. Registers a `{stream, ...}`
  Nova return-handler (as a `fun/3` - Nova's `{Mod,Fun}` form wraps to /4 and
  badarity's). The handler `stream_reply`s SSE headers, subscribes to the run's
  blackboard + `gakudan_liveboard_stats`, pushes `datastar:patch_elements`
  frames, and **never returns** (so Nova's buffered reply never fires). On
  Nova's own listener; no separate Cowboy, no Nova patch. See nova#387.
- `gakudan_liveboard_stats` - telemetry handler -> per-run stats (tokens, turns,
  score, events) in ETS, with subscribe/notify for live rail updates.
- `gakudan_liveboard_action_controller` - HITL POSTs -> gakudan
  interrupt/resume/cancel, one-shot Datastar SSE response via Nova's
  `handle_status`.
- `gakudan_liveboard_demo` - stub planner/coder run for offline data
  (`start_demo_run/0`, `nudge/0`).

Self-hosted: fonts + CSS + datastar.js in `priv/static/assets` (GDPR; CSP
`default-src 'self'`, `unsafe-eval` only for Datastar's expression eval).

## Gotchas (load-bearing)

- Datastar v1 has no `data-on-load`; use **`data-init`** to run `@get` on load.
- gakudan pulls `kura` transitively; its pre-compile migration hook crashes when
  built as a dep here, so `rebar.config` overrides gakudan's `provider_hooks`.
- Declare `telemetry` directly (transitive deps aren't on the release path).

## Run it

```bash
make serve            # or: rebar3 release && .../bin/gakudan_liveboard foreground
# rpc gakudan_liveboard_demo start_demo_run, open http://localhost:8080/
```

## Pre-push

```bash
rebar3 fmt --check && rebar3 xref && rebar3 compile
```

## Git and PRs

Conventional commits. Always open a PR - never push to `main`. Every merge to
`main` tags a release.
