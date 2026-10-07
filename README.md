# antfarm-core

The reusable infrastructure of [A.N.T.F.A.R.M.](https://github.com/project-antfarm):
the workflows, guards, telemetry writer and role prompts that every specimen
runs. A specimen repository keeps only what is specific to it: `GOAL.md`,
`.antfarm/config.yml`, `.antfarm/toolkit.yml`, the boundary files, and four
thin workflows that call this repository at a pinned commit.

Nothing here knows what any product is.

## Layout

```
.github/workflows/queen.yml      reusable: plan, review, merge, declare DONE
.github/workflows/ant.yml        reusable: implement one Issue, open a PR
.github/workflows/oracle.yml     reusable: audit a DONE claim, advise on a blocked Issue
.github/workflows/project-sync.yml  reusable: mirror labels into the Project board
antfarm/budget.sh                deterministic guard, recomputed from telemetry
antfarm/telemetry.sh             writes one immutable event file per execution
antfarm/ledger.jq                shared reading of the event files
antfarm/queen.md worker.md oracle.md   role prompts, injected by the workflows
antfarm/toolkit/                 ponytail.md (appended system prompt), rtk config
template/                        what a new specimen receives
bootstrap.sh labels.json ruleset.json  turn a repository into a specimen
test/budget.sh                   the one runnable check of the ledger
```

## Roles

| Role   | Model (config) | Does | Never |
|--------|----------------|------|-------|
| Queen  | `queen.model`  | reads GOAL.md, DECISIONS.md, Issues, PRs, CI; reviews, merges, plans | edits product code or boundary files; changes limits |
| Worker | `worker.model` | implements exactly one `ready` Issue, tests, opens a PR | invents roadmap; touches other Issues |
| Oracle | `oracle.model` | audits a `done` claim item by item; advises on a `blocked` Issue | plans, builds, merges, labels |
| CI     |                | lint, tests, required checks | |
| Human  |                | GOAL.md, boundary files, emergency stop, final judgement | writes the backlog |

The Oracle's verdict is applied by a workflow step from its structured output:
a rejected DONE claim is closed with the findings and labelled `done-rejected`,
which wakes the Queen. If the Oracle fails to reach a verdict, `done` stays,
the colony stays paused, and the Issue is labelled `human`. Advice on a
blocked Issue is a comment; the Queen decides.

## How a specimen uses this

The caller workflow owns the triggers and pins this repository by commit, in
`uses:` and again in `core_ref` (GitHub does not expose the called workflow's
own commit, and the run manifest must record it):

```yaml
jobs:
  queen:
    uses: project-antfarm/antfarm-core/.github/workflows/queen.yml@<sha>
    with:
      core_ref: <sha>
    secrets: inherit
```

Each run of a reusable workflow checks out the specimen, fetches this
repository at `core_ref` into the runner's temp directory, reads
`.antfarm/config.yml` from the specimen, runs the guards, and starts the model
with the role prompt and the ponytail text from here. Nothing from this
repository enters the specimen's working tree, so a Worker cannot commit it.

Changing the pinned commit is an experimental variable: `core_sha` is written
to `manifest.json` by the first execution of a run.

## New specimen

```
./bootstrap.sh <owner>/<repo>
```

Copies `template/`, creates labels, the `main` ruleset, the kill switch
variable (off) and the status Issue, then prints what only a human can do:
install the Apps, provide the secrets, enable Pages, write `GOAL.md`.

Secrets live in the specimen or in the organisation (visible to it);
`secrets: inherit` passes them through. This repository needs none.

## Policy, state, telemetry

- **Policy** is the specimen's `.antfarm/config.yml`: models, effort, turns,
  runs per day per role, weekly cost and token locks, work-in-flight,
  attempts, lease. Prices per model feed the conservative cost estimate; an
  unknown model is priced as `default`.
- **Telemetry** goes to [`antfarm-telemetry`](https://github.com/project-antfarm/antfarm-telemetry)
  through a dedicated App. Event types: `queen.*`, `worker.*`, `oracle.*`
  (`started`, `completed`, `failed`), `guard.blocked`, `human.note`.
- **State** is never stored for decisions. `budget.sh` recomputes every
  counter from the event files before any model starts.

## Local check

```
test/budget.sh
```

Needs `jq` and `yq`, like the runners.
