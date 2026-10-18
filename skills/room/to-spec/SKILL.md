---
name: to-spec
description: Turn an already-discussed conversation directly into a written spec, no interview, pure synthesis of what was already said. Use when the operator says write this up as a spec, capture what we decided, or turn this conversation into a doc, after the discussion already happened. Do NOT use this to start a discussion; if the plan still needs sharpening, use grilling or grill-me first, then to-spec once it's settled. Do NOT ask the operator new questions; if a gap appears, mark it Out of Scope or Undecided rather than interviewing.
---

# To Spec

## Synthesize, do not interview

Read back through the conversation and extract what was actually decided. Do not ask the operator anything new. A gap in the discussion is a gap in the spec, marked as such, not a prompt to go interview them.

Read the code the spec touches before writing, so the decisions name the real parts of the system and the testing section points at tests that exist.

## Structure

- **Problem**: what is wrong or missing, in plain language, from the Captain's side.
- **Solution**: what will exist once this ships, from the Captain's side.
- **Decisions**: the concrete choices made in the conversation, each traceable to something actually said.
- **Testing decisions**: for each part, the behaviour that proves it works and where that check runs (an existing test file, the simulator, a live call). Prefer one check at the highest point that sees the whole behaviour over many small ones. Name tests that already do something similar. `to-tickets` carries these into each ticket's test methods, which the manual requires before any ticket is dispatched.
- **Out of scope / Undecided**: anything explicitly ruled out, and every gap the conversation left open.

No file paths and no code snippets in the spec, with one exception: a snippet from an already-built prototype that encodes a decision more precisely than prose can.

Bad testing decision: "Add tests for the new settings."
Good testing decision: "Saving the new field survives an app restart: one UI test that sets it, relaunches, and reads it back, next to the existing settings persistence test."

## Where it goes

Save the spec in Linear as a ticket in the team its work belongs to (FLT, TNG, OPO and so on), titled with what will exist, in Backlog. The tickets `to-tickets` makes from it become its sub-issues, so the spec and its work stay linked. Don't ask where to put it, and don't write it into a repo.

## Completion

The spec is done when someone who was not in the conversation could read it and know what is being built, why, and how each part will be shown to work, without asking a single follow-up question about what was decided. Give the Captain the ticket link.
