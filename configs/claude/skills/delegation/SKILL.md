---
name: delegation
description: Dispatch work to the coder, reviewer, or adversary seats through the opencode-rescue subagent. Load this when making a dispatch, or when backend, quota, cost, model selection, or the reviewer/coder review loop for those seats comes up.
---

# Delegation

The seats run through the `opencode-rescue` subagent, which forwards to the
opencode companion CLI. Call the `Agent` tool with
`subagent_type: "opencode:opencode-rescue"` and put the request in the prompt.
Name the seat in the prompt when it is not `coder`, which is the default.

## Transports

Two transports carry the seats. `agy` drives the antigravity CLI on the Google
account the Jio subscription pays for. `opencode` reaches opencode's own models
plus OpenRouter against a paid key. Pass `--backend opencode|agy` in the rescue
prompt to pin one; the wrapper forwards the flag to `task`.

Leaving it off no longer means "opencode". Each seat can pin its own default
transport, and `coder` pins `agy` on `gemini-3.8-flash-high`. Only an explicit
`--backend` overrides that.

`task` accepts `--agent`, `--backend`, `--background`, `--fresh`, `--model`,
`--resume-last`, `--review-rounds`, `--task-file`, `--wait`, and `--write`. It
rejects anything else.

## Cost and quota

opencode removed the free muse spark contributor tier, so
`opencode/muse-spark-1.3-contributor-free` no longer answers and a prompt to it
hangs with no error. That is why `coder` moved to agy: agy is already paid for,
and muse spark is now reachable only through OpenRouter as
`meta/muse-spark-1.3-contributor`, which bills the wallet at $0.10 and $0.20 per
million with cache reads at $0.002. Cache hits run near 79%, so the 21% that
misses is most of the bill.

The direction of that trade has flipped. `--backend agy` used to be the flag
that avoided spending; agy is now the default, and reaching muse spark is what
spends. A `coder` job that falls back has left the paid seat for the metered
one — worth knowing when it happens, not worth arranging around in advance.

The two backends draw separate quotas, so one being spent says nothing about
the other. agy quota is per Google account with a weekly window and a five-hour
window. The five-hour one binds first. Gemini models and the Claude and GPT
models sit in separate buckets, so the seat default of `gemini-3.8-flash-high`
can have room while the Claude group reads 0%. Check the quota panel in the agy
TUI before leaning on it.

## Seat prompts across backends

A seat is a file at `~/.config/opencode/agent/<name>.md`: frontmatter picking
the model, variant and temperature, then a body that is the seat's system
prompt. opencode reads the whole file. agy reads none of it — it maps the seat
name to a `--mode` and nothing else.

The companion carries the prompt body across itself, so a coder dispatch on agy
still runs with coder.md's instructions. The frontmatter cannot cross: agy takes
its model from `--model` and has no variant or temperature flag. So `variant:
xhigh` and `temperature: 0.1` apply on opencode only, and a dispatch that needs
them has to say `--backend opencode`.

## Concurrency

Two coding jobs may run at once, machine-wide. Both backends share that one
counter, even though agy enforces no concurrency limit of its own. An unmetered
backend on a quota that refills every five hours is the case the cap was written
for. A six-way fan-out once drained a five-hour agy window in thirty-five
minutes and left every job for the next sixteen hours with nothing to run on.
The count covers every workspace on the machine because roughly half the overlap
in a week of records came from a second Claude Code session working the same
repo, which no rule addressed to one session alone can catch.

`OPENCODE_MAX_CONCURRENT` overrides the cap. The companion reads it once per
command, at module load, so it raises the cap only for the invocation that
carries it. The rescue subagent has no handling for it, so there is no way to
pass it through a rescue dispatch. Raising it means running the companion
directly, which is a decision for the user, not something to arrange around a
refusal. Treat a refusal as the answer.

## The review loop

A write dispatch can hand its own diff to the reviewer and send the blocking
findings straight back to the coder, without coming back through you. It runs
inside the coder's job, so it holds one concurrency slot for the whole loop
rather than taking a new one per round.

It triggers by itself only when the dispatch was `--write`, actually produced a
diff, and that diff is more than one file or at least 30 changed lines. It never
triggers on a read-only dispatch or on `--resume-last`, where the user is
already reviewing by hand. `--review-rounds 0` turns it off; `--review-rounds N`
turns it on regardless of size and caps it at N.

Two fix rounds, hard: review, fix, verify. The second review is a verify pass
scoped to the first round's findings, not a fresh review, because a fresh one
re-litigates the design every round and never converges. Only `critical` and
`high` findings go back to the coder; everything else is reported to the user,
so a rename cannot spend a coder round.

It halts rather than spins on three things: a reviewer handoff, a coder fallback
to the metered seat, and either seat throwing. A halted loop is not a pass —
nobody confirmed the change, and its summary says what stopped it.

The stop-time review gate stands down for ten minutes after a loop runs, so the
same diff is not reviewed twice by two mechanisms.

## Fallbacks

Each seat has a second model that takes over when the first cannot be reached.
That happens inside the plugin, so you do not arrange it. `coder` falls from agy
onto muse spark through OpenRouter, which is the metered route. The `reviewer`
fallback is a Claude Code subagent on Sonnet, which only you can start because
opencode has no Anthropic credential and lists no Claude model. A job that fails
with a `handoff` marker is asking you to run that review yourself.

`reviewer` and `adversary` both spend the same synthetic.new key, and that plan
allows one agent at a time. Never run them together, and do not run either
alongside `synclaude`. Review one after the other, or send the second one to
Sonnet. The review loop holds that same one-at-a-time reviewer for its whole
life, so do not start a second loop or a separate review while one is running.
