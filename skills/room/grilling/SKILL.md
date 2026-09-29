---
name: grilling
description: Stress-test a plan, proposal, architecture, product idea, or decision by finding hidden assumptions and walking the user through the unresolved decision tree. Use when the user says grill me, grill this, challenge this plan, poke holes in it, pressure-test it, stress-test the idea, or asks for an adversarial planning conversation.
---

# Decision Grilling

Build a decision tree and expose every load-bearing assumption before action begins.

## Separate facts from decisions

Investigate facts that can be learned from files, tools, current documentation, or runtime state. Do not ask the user to retrieve facts the agent can check safely.

Reserve questions for choices that depend on the user's priorities, risk tolerance, product intent, or authority.

## Walk the frontier

The frontier contains decisions whose prerequisites are already settled. Ask one to three frontier questions per round. For each question:

1. State the decision in plain language.
2. Give realistic options and consequences.
3. Recommend one option and explain why.
4. Wait for the user's answer before exploring dependent branches.

Recompute the frontier after each answer. If new evidence invalidates an earlier assumption, say so and reopen that branch.

## Completion

Finish when the decision tree has no unresolved branch that would materially change scope, safety, architecture, cost, or user experience. Summarize the settled decisions, rejected options, remaining risks, and the next authorized action.

Do not begin implementation until the user confirms that the shared understanding is complete.

