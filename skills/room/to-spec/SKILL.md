---
name: to-spec
description: Turn an already-discussed conversation directly into a written spec, no interview, pure synthesis of what was already said. Use when the operator says write this up as a spec, capture what we decided, or turn this conversation into a doc, after the discussion already happened. Do NOT use this to start a discussion; if the plan still needs sharpening, use grilling or grill-me first, then to-spec once it's settled. Do NOT ask the operator new questions; if a gap appears, mark it Out of Scope or Undecided rather than interviewing.
---

# To Spec

## Synthesize, do not interview

Read back through the conversation and extract what was actually decided. Do not ask the operator anything new. A gap in the discussion is a gap in the spec, marked as such, not a prompt to go interview them.

## Structure

- **Problem**: what is wrong or missing, in plain language.
- **Solution**: what will exist once this ships.
- **Decisions**: the concrete choices made in the conversation, each traceable to something actually said.
- **Out of scope**: anything explicitly ruled out or left undecided.

No file paths and no code snippets in the spec, with one exception: a snippet from an already-built prototype that encodes a decision more precisely than prose can.

## Where it goes

Save the spec to the target repo, not the fleet repo; a spec is project-specific. If the project has a docs or peer_reviews convention already, use it; otherwise ask where before guessing.

## Completion

The spec is done when someone who was not in the conversation could read it and know what is being built and why, without needing to ask a single follow-up question about what was decided.
