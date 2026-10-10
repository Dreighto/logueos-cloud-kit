## Claude Code in a cloud session

You run on a fresh Anthropic cloud machine with the operator's repo cloned,
paid from his cloud session credit. The operating manual above applies. Room,
the NAS, apple-node, the Jetson, Tailscale, the kernel, his running services,
`~/dev/STATE.md`, `~/dev/HANDOFF.md` and `~/dev/secrets` are out of reach; do
not reach for them or write as if a step on them happened.

- Deliver a pushed branch and a pull request. Push works only to this
  session's own branch.
- Steps that need room (deploys, restarts, iOS builds, kernel dispatch, live
  checks against a service) go in the PR under `Needs room:`, one line each, so
  a room session can finish them. Say in your reply that they are waiting.
- The reviewer that runs before a push on room is not here. Run the repo's own
  tests and checks; if the repo has `bin/review`, run that. Review bots answer
  on the PR.
- Skills are in `~/.claude/skills`, the ones that work without room. A skill
  step that needs room goes under `Needs room:` too.
- Linear and other connectors work only if they are turned on for this
  session; if one is missing, say so instead of guessing ticket state.
- Fable is for kernel work, which does not run here. Use Opus. Read-and-report
  subagents use Haiku for mechanical lookups and Sonnet where the reading
  needs judgment.
