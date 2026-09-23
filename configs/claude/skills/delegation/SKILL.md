---
name: delegation
description: Dispatch work to the coder, reviewer, or adversary seats through the opencode-rescue subagent. Load this when making a dispatch, or when backend, quota, cost, or model selection for those seats comes up.
---

# Delegation

The seats run through the `opencode-rescue` subagent, which forwards to the
opencode companion CLI. Call the `Agent` tool with
`subagent_type: "opencode:opencode-rescue"` and put the request in the prompt.
Name the seat in the prompt when it is not `coder`, which is the default.

## Transports

Two transports carry the seats. `opencode` is the default. It reaches
opencode's own models plus OpenRouter against a paid key. `agy` drives the
antigravity CLI on the Google account the Jio subscription pays for. Pass
`--backend agy` in the rescue prompt to pick it. The wrapper forwards the flag
to `task`. Leaving it off keeps the default.

`task` accepts `--agent`, `--backend`, `--background`, `--fresh`, `--model`,
`--resume-last`, `--task-file`, `--wait`, and `--write`. It rejects anything
else.

## Cost and quota

opencode removed the free muse spark contributor tier, so
`opencode/muse-spark-1.3-contributor-free` no longer answers. A prompt to it
hangs with no error. `coder` now reaches the same model through OpenRouter as
`meta/muse-spark-1.3-contributor`, which bills the wallet at $0.10 and $0.20
per million with cache reads at $0.002. Cache hits run near 79%, so the 21%
that misses is most of the bill. The flag used to escape a rate limit. It now
avoids spending.

The two backends draw separate quotas, so one being spent says nothing about
the other. agy quota is per Google account with a weekly window and a
five-hour window. The five-hour one binds first. Gemini models and the Claude
and GPT models sit in separate buckets, so the seat default of
`gemini-3.8-flash-high` can have room while the Claude group reads 0%. Check
the quota panel in the agy TUI before leaning on it.

## Concurrency

Two coding jobs may run at once, machine-wide. Both backends share that one
counter, even though agy enforces no concurrency limit of its own. An
unmetered backend on a quota that refills every five hours is the case the cap
was written for. A six-way fan-out once drained a five-hour agy window in
thirty-five minutes and left every job for the next sixteen hours with nothing
to run on. The count covers every workspace on the machine because roughly
half the overlap in a week of records came from a second Claude Code session
working the same repo, which no rule addressed to one session alone can catch.

`OPENCODE_MAX_CONCURRENT` overrides the cap. The companion reads it once per
command, at module load, so it raises the cap only for the invocation that
carries it. The rescue subagent has no handling for it, so there is no way to
pass it through a rescue dispatch. Raising it means running the companion
directly, which is a decision for the user, not something to arrange around a
refusal. Treat a refusal as the answer.

## Fallbacks

Each seat has a second model that takes over when the first cannot be reached.
That happens inside the plugin, so you do not arrange it. `coder` falls onto
agy. The `reviewer` fallback is a Claude Code subagent on Sonnet, which only
you can start because opencode has no Anthropic credential and lists no Claude
model. A job that fails with a `handoff` marker is asking you to run that
review yourself.

`reviewer` and `adversary` both spend the same synthetic.new key, and that plan
allows one agent at a time. Never run them together, and do not run either
alongside `synclaude`. Review one after the other, or send the second one to
Sonnet.
