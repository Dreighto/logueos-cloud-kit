---
name: architect
description: Sketch two structurally different designs with stub bodies before writing real implementation, so the shape gets picked deliberately instead of by whatever got typed first. Use when the operator says design this first, sketch some options, or the work is bigger than a routine fix and the right shape isn't obvious yet. Do NOT use for a change with one obvious correct shape; sketching two options nobody would choose between is wasted motion.
---

# Architect

## Ground

State the actual constraint driving the design: what must be true when this is done, not how it should be built. Confirm it with the operator before sketching if there is any ambiguity.

## Sketch

Produce at least two structurally different candidates: types, function signatures, and module boundaries, with `not implemented` bodies. Structurally different means a different seam or a different owner of the state, not the same shape with renamed variables.

## Agree

Present both candidates plainly, with the real tradeoff between them, and let the operator pick, or make the call yourself and say why if you have standing authority to.

## Implement

Fill in the chosen sketch's real bodies. Do not silently change the shape while implementing; if the sketch turns out wrong once real code is written, that is a scrap signal, not a place to quietly improvise a third shape.

## Scrap signals

Stop and reconsider the shape if any of these show up mid-build: the same kind of workaround repeating in more than one place, needing `any` or a cast to make it compile, or reaching for a lock because state that was not supposed to be shared turned out to be shared. Any of these means the sketch was wrong, not that the implementation needs to try harder.
