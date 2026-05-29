# gakudan_liveboard

Live web dashboard for [gakudan](https://github.com/Taure/gakudan) runs.

A Nova + Datastar app that shows active multi-agent runs and a live
transcript per run. Subscribes to the gakudan blackboard via `pg` and streams
updates over SSE, so entries appear as they're appended - no client framework.

## Pages

- `/` - list of active runs, plus a button to spawn a stub demo run.
- `/runs/:run_id` - live transcript of a single run.

## Try it

```bash
make setup
make serve
# open http://localhost:8080/
```

## Status

Working. A live run dashboard - the "conductor's stand" console for a running
gakudan node. The run index lists active and recent runs and updates live over
SSE; the run detail page streams the transcript and per-run stats as they
happen, with interrupt/resume/cancel controls wired to gakudan.

## License

MIT.
