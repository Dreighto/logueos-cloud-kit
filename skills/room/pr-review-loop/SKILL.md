---
name: pr-review-loop
description: Own the review loop for a change in a Dreighto GitHub repo (grandline, minecraft-knowledge), from "before I push" to merged. Triggers: "I pushed a PR", "open a PR", "address the review comments", "merge when clear", any push to an open PR, and any change that is about to be committed. The author reviews and verifies their own change with `bin/review` before pushing; the gate runs the same reviewer on the PR head; CodeRabbit advises and never gates. The operator is not a review step.
---

# PR review loop

Operator ruling (2026-09-04): agents write the code right. Nobody else checks
their work for them. CodeRabbit and other outside reviewers are advisory. The
kernel's LSR is not used in these repos; each repo carries its own reviewer.

The agent that writes a change owns it until it is merged or handed back with
a reason. Mechanics: `bin/review` and `bin/pr-gate` (grandline),
`scripts/review` and `scripts/pr-gate` (minecraft-knowledge). Read
`bin/review --help` once.

1. While editing: `bin/review --working` (add `--model none` for a fast
   deterministic-only pass). Fix every BLOCKING line. Done when it prints
   `REVIEW PASS`.
2. Before pushing: `bin/review` on the branch (merge-base with `origin/main`
   to HEAD, about five minutes with the model pass). Fix blocking findings;
   note advisory ones you leave in the PR body. A finding under UNVERIFIED
   is a model claim whose quoted evidence is not in the code; read it once,
   it does not count. Done when it prints `REVIEW PASS` on the commit you
   are about to push.
3. Push, open the PR with `gh pr create`, body: summary, test plan, and an
   `Operator decision:` line only if the change deploys to the live server,
   edits a rules section of CLAUDE.md (a PR that only updates the synced
   operating-manual block is exempt: the manual was already reviewed in
   logueos-fleet), or touches credentials. Done when the
   PR URL prints.
4. Run `bin/pr-gate <number>`. It fetches the branch, runs `bin/review` on
   the PR head, posts the summary on the PR, waits up to five minutes for
   CodeRabbit, and prints READY, BLOCKED, NOREVIEW or NOMERGE.
5. BLOCKED: for each listed finding or thread, either fix it and push, or
   reply on the thread with the evidence it is wrong, naming the commit.
   Rerun step 4. Done when the gate prints anything but BLOCKED.
6. NOREVIEW: the reviewer could not run (no model reachable, tool error).
   Fix the cause or stop and report it. Nothing merges on NOREVIEW.
7. NOMERGE: resolve the conflict on the branch, or stop and report why.
8. READY and no `Operator decision:` line: `bin/pr-gate <number> --merge squash`
   (`--merge rebase` when the branch carries another author's commits worth
   keeping). Then `git pull` on main in every checkout you own. Done when
   the gate prints MERGED.
9. READY with an `Operator decision:` line: post the decision needed as a
   one-line comment on the PR and tell the operator. Do not merge.

Rules that hold regardless of harness:

- Never push a commit `bin/review` has not passed. "The gate will catch it"
  is the attitude this ruling exists to end.
- Never resolve a bot thread without a reply that says what changed or why not.
- Never dismiss a review by hand; the gate dismisses stale ones on merge.
- Never merge with an open thread, a draft flag, a conflict, or a NOREVIEW.
- Never wait on a silent bot; its window is the gate's, not yours.
- One agent per PR at a time. If another agent's PR is blocked, comment, do
  not push to its branch. The review fixer's cloud agent counts: before
  pushing to an open PR, run `bin/review-fixer status Dreighto/<repo>` from a
  grandline checkout. If that PR shows `running` or `slow`, wait for it to
  finish; if it shows `needs-human`, `failed` or `no-summary`, the open
  threads are yours to answer.
