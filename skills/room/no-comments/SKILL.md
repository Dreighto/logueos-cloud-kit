---
name: no-comments
description: Challenge every comment in a diff and require the author to defend it or delete it, catching comments that narrate code instead of explaining a non-obvious why. Use when the operator says check the comments, review this diff's comments, or before finishing any change that added or kept a comment. Do NOT use for a diff with zero new or touched comments; there is nothing to challenge.
---

# No Comments

## Read every comment cold

For each comment touched or added in the diff, read it without the surrounding code's intent in mind. Ask: what does this comment claim that the code and identifiers do not already say?

## Challenge it

If the comment restates what the next line does, names something the identifiers already name, or narrates control flow, challenge it directly: what non-obvious constraint, invariant, or workaround is this actually protecting? If there is a real answer, the comment should say that instead. If there is no real answer, the comment should be deleted.

## The author defends or cuts

Do not let a comment survive on the strength of already being there. Either sharpen it to state the actual hidden reason (a bug it works around, an external constraint, a subtle invariant a future reader would violate without warning) or remove it.

## Report

List each challenged comment, the verdict (kept and sharpened, or removed), and why. A diff with comments nobody challenged did not run this skill.
