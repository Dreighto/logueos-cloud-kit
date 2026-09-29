---
name: create-verification-map
description: Build a project-local list of every user-facing feature and exactly how to drive it live, so future QA has a maintained checklist instead of relying on memory. Use once per project when the operator says set up verification for X, build a feature map, or asks how to systematically check a whole app works. Do NOT use for a one-off manual QA pass on a single change; that is ordinary browser verification. Pairs with maintain-verification-map, which re-walks the list this skill creates.
---

# Create Verification Map

## Enumerate the features

Walk the project (routes, screens, API surfaces, background jobs) and list every user-facing feature. A feature is something a real user or operator does, not an internal function. For a chat app: send a message, trigger voice mode, open the artifact library, not sendMessage() or the internal event bus.

## Write the drive-it-live step for each

For every feature, write the exact, concrete action that proves it works right now: what to click or call, what to type, what the passing result looks like, in numbers where a number applies (streaming tokens within 2 seconds, not "loads fast"). A step someone cannot literally follow without guessing is not done.

## Save it as a project skill

Write the map to `.claude/skills/verify-<project>/SKILL.md` in the target repo, `disable-model-invocation: true`, invoked on demand. Keep it out of the fleet repo; it is specific to one project's features, not portable canon.

## Completion

The map is done when every feature in the project has a drive-it-live step someone unfamiliar with the code could follow and get a clear pass or fail.
