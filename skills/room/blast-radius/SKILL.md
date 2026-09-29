---
name: blast-radius
description: Find what a change could break elsewhere before it ships, and prove the safety-critical facts by running code instead of writing a convincing paragraph. Use when the operator says blast radius of X, what could this break, or asks for a second look at a risky diff before merging. Do NOT use for a routine change with no shared-state, authorization, or cross-caller surface; the confidence ladder in global CLAUDE.md rule 6 already covers ordinary claims.
---

# Blast Radius

## Find the load-bearing facts

Read the change, then name the one or two facts its safety actually depends on. A writeup with ten facts and no ranking is not this; find the ones that, if wrong, break everything else in the writeup. Listing every caller is not the job; the model can grep those in a second. The job is the breakage a grep will not show.

## Prove them, do not assert them

For each load-bearing fact, climb the confidence ladder from global CLAUDE.md rule 6 (said-so, pointed-at-the-line, walked-the-failure-through, ran-it, reproduced-live) to at least ran-it. A writeup that reads as convincing is not evidence; that is the trap. Run the script, test, or command that fails loud if the fact is false.

## Say what you could not verify

If a load-bearing fact cannot be pushed past pointed-at-the-line in the time available, say so plainly in the writeup. Do not let confident prose imply a fact was checked when it was not.

## Report

State each load-bearing fact, the rung it reached, and what proved it. A finding that never named a load-bearing fact, or never went past said-so, did not do this skill.
