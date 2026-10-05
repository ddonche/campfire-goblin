# Campfire → Goblin port: experiment record

This repository is an attempt by a coding agent to port Basecamp's ONCE Campfire
to the Goblin programming language, in the spirit of DHH's Campfire ports to
Rust, Go, Elixir, Express, Django and Laravel.

## Frozen inputs

Run started: **2026-10-05**

| Input | Repository | Commit |
|---|---|---|
| Application being ported (behavioral oracle) | https://github.com/basecamp/once-campfire | `acef0c71cf166cb1d73d18788618a4876b22642e` |
| Goblin language (interpreter, VM, host) | https://github.com/ddonche/goblin-lang | `7f869818c2fbab9ba3063d5d40d2f42b8f32e131` |
| Sheriff (reference Goblin application) | https://github.com/ddonche/sheriff | `5490c5f77884e2ac746ea76a0be6bcb7ab9e1dca` |

## Rules of the run

- Goblin, Sheriff and Campfire are read-only references. Nothing in them is modified.
- All work happens in this repository.
- Goblin is learned from its source, tests, docs and Sheriff.
- Missing *libraries* are written here, in Goblin.
- Missing *language/runtime/host capabilities* are not added; they are reported
  (see `BLOCKERS.md` if present) with the smallest general-purpose Goblin addition
  that would unblock the port.
