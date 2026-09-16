---
name: adversary
description: Send the current plan to an adversarial reviewer that hunts for holes in it, then report the findings. Use when the user runs /adversary, or asks to red-team, stress-test, poke holes in, or find problems with a plan or design before committing to it.
user-invocable: true
---

# adversary

Run one hostile pass over a plan before acting on it. The reviewer is a separate
model in fresh context that only reports problems; it never edits and never
rewrites the plan.

## When to use it

The user runs `/adversary`, usually while in plan mode, before the plan is
approved. It works on any plan or design that is written down: a plan-mode
draft, a design document, a migration approach, an architecture proposal.

It is not a code reviewer. For a diff, use `/code-review` instead.

## One round, then stop

Dispatch the reviewer once. Fold in what survives, tell the user what you
rejected and why, and stop.

Do not send the revised plan back for another pass on your own initiative. A
second round happens only if the user asks for one, or if a blocking finding
changed the plan's shape rather than its details. Repeated rounds degrade: once
the real problems are gone the reviewer starts inventing objections, and
answering those makes the plan worse, not better.

## Procedure

1. **Assemble the input.** The reviewer needs the goal in the user's own words
   and the full plan text. Write both to a file in the scratchpad rather than
   passing them inline, so quoting cannot mangle them.

   Send the plan as it stands. Do not send your reasoning, your notes, or the
   conversation. If the plan does not stand on its own, that is a finding worth
   getting.

2. **Dispatch to the `adversary` opencode agent**, from the repository the plan
   concerns:

   ```
   node "$COMPANION" task --background --agent adversary "$(cat <brief-file>)"
   ```

   where `$COMPANION` is
   `~/.claude/plugins/cache/tasict-opencode-plugin-cc/opencode/*/scripts/opencode-companion.mjs`.

   The agent is defined at `~/.config/opencode/agent/adversary.md` and runs
   Kimi K3 on synthetic with writes disabled.

3. **Poll from the repository directory.** The companion keys job state by
   workspace, so `status` run from anywhere else reports `unknown`. Phase never
   changes mid-run, so a heartbeat proves nothing; check real progress through
   the opencode session message API instead:

   ```
   curl -s http://127.0.0.1:4096/session/<session-id>/message
   ```

4. **Verify the job actually did something.** The companion reports `completed`
   when the process exits, including when the model was rate-limited or cut off
   mid-generation. Before trusting a result, confirm the final assistant message
   has content and no `error`. An empty result with `finish: undefined` is a
   failed run, not an empty finding list.

5. **Judge the findings, do not just relay them.** Check each one against the
   plan and the code. Adversarial reviewers overreach: they flag things as
   unverified that are in fact verified, and assert failure modes that the
   design already handles. Verify before accepting. Rejecting a finding with a
   stated reason is a correct outcome.

6. **Report to the user**: the verdict, the findings you accepted and what you
   changed, and the findings you rejected with the reason. Say plainly if the
   plan came back sound.

## Fallbacks

The reviewer runs on synthetic, whose $30 tier allows only one concurrent
agent. Do not run it alongside another synthetic-backed agent.

If Kimi K3 is unavailable or rate-limited, fall back to GLM-5.2
(`synthetic/hf:zai-org/GLM-5.2`), then to Claude Sonnet. Do not fall back to
muse spark: adversarial critique rewards a strong model, and a weak critic
produces exactly the invented-objection noise this skill exists to avoid.

## What good output looks like

Few findings, each naming a concrete trigger. A reviewer that returns three
real problems is more useful than one that returns twelve observations. If
every finding is minor and none names a trigger, the pass failed; say so rather
than dressing it up as a clean bill of health.
