---
name: writing-for-agents
description: Create or revise instructions consumed by coding agents, including SKILL.md, AGENTS.md, CLAUDE.md, lane guidance, prompts, and agent-facing runbooks. Use when writing a skill, changing agent instructions, improving invocation triggers, reducing instruction drift, or deciding what should load always versus on demand.
---

# Writing for Agents

Write instructions that change behavior reliably without consuming unnecessary context.

## Confirm authority and audience

Identify the harness, model families, execution mode, and governing instruction hierarchy. Treat governance, kernel canon, and machine-level configuration as controlled surfaces. Editing instructions does not grant authority to weaken higher-priority rules.

## Put each fact in one place

Choose a single source of truth. Link to it from other surfaces instead of copying the rule. Treat configuration, directory layout, and executable help output as sources the agent can inspect, not prose that must be cached everywhere.

## Design the load path

Use always-loaded instructions for short, universal constraints. Use skill descriptions or conditional pointers for task-specific workflows. Put detailed branches and reference material behind direct links that say exactly when to read them.

For skills, make the description name both the capability and the phrases or situations that should trigger it. Keep the body focused on actions and completion criteria.

## Weigh context load against cognitive load

Always-loaded material spends the agent's context load: every token, every
turn, whether the situation calls for it or not. A pointer instead spends the
human's cognitive load: remembering the doc exists and when to reach for it.
Neither cost is free, and cognitive load is not a bug to eliminate; it is the
price of the human staying in control of judgment calls. Weigh both before
deciding what stays always-loaded versus what moves behind a pointer.

Name the concept a description or pointer leans on. A phrase like "fast,
deterministic, low-overhead" makes the reader assemble a concept from parts; a
single word like "tight" hands them one already formed. Prefer the single
word when one exists.

## Write checkable steps

Use imperative language. End each step with an observable completion condition. State the desired behavior positively, then retain explicit prohibitions where safety or authority requires them.

Remove:

- instructions the model already follows without prompting;
- duplicated rules;
- stale snapshots of discoverable configuration;
- vague demands such as "be thorough" without a measurable bound;
- background narrative that does not change execution;
- any line that fails the no-op test: if deleting it changes nothing about
  what an agent actually does, it is decoration, not a rule.

## Validate behavior

Check syntax with the harness's validator. Test representative trigger phrases, false-positive cases, and one realistic task. Confirm the instruction respects repository scope and does not silently acquire write, deploy, tracker, or secret authority.
