# gakudan_liveboard

Live web dashboard for [gakudan](https://github.com/Taure/gakudan) runs.

A Nova + Arizona LiveView app that shows active multi-agent runs and a live
transcript per run. Subscribes to the gakudan blackboard via `pg`, so
entries appear as they're appended.

## Pages

- `/` - list of active runs, plus a button to spawn a stub demo run.
- `/runs/:run_id` - live transcript of a single run.

## Try it

```bash
make setup
make serve
# open http://localhost:8080/
```

## Status (2026-05-22)

WIP. The supervision tree, views, router, and demo seeder are in place, but
the app does **not boot yet** against the current upstream:

- `arizona_nova/main` calls `arizona_pubsub:set_scope/1` in
  `arizona_nova_sup:init/1`.
- `arizona/main` no longer exports `set_scope/1` (removed in
  arizona-framework/arizona@0681492 "Profile-driven framework
  optimisations").

So the upstream pair is currently incompatible. To unblock, either fix
`arizona_nova` to stop calling `set_scope/1` or pin `arizona` to a commit
that still has it. The first option is the right one and likely a
one-line PR.

Once that's fixed, the views should run as-is (they were written against
the new tuple-template API).

## License

MIT.
