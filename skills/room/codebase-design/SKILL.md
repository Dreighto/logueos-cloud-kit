---
name: codebase-design
description: Analyze and improve module boundaries, public interfaces, seams, dependency direction, locality, and testability. Use when the user asks about architecture, codebase design, module structure, abstractions, interfaces, refactoring boundaries, deep modules, or where a responsibility should live.
---

# Codebase Design

Design from verified callers and current constraints, not from an abstract preference.

## Understand the current shape

Trace the relevant callers, data flow, side effects, tests, and deployment boundaries. Read the repository's architecture records and use its established domain vocabulary. Do not rename familiar concepts merely to impose a generic terminology.

Name the concrete pressure that motivates a design change: repeated edits, leaked knowledge, an untestable seam, cyclic dependencies, scattered policy, or another observed cost.

## Compare designs

For a nontrivial boundary, compare at least two viable shapes. Evaluate each against:

- interface size and clarity;
- how much complexity it hides from callers;
- locality of future changes;
- dependency direction;
- testability through real behavior;
- migration and rollback cost;
- consistency with the existing codebase.

Prefer a deep module: a small, stable interface that hides substantial implementation detail. Avoid pass-through layers that merely rename another API.

Use the deletion test. If removing the module spreads its complexity back across several callers, it is probably earning its place. If removing it only removes forwarding code, it probably is not.

## Keep seams honest

Introduce an abstraction when something actually varies or when it contains a policy that callers should not know. One hypothetical adapter is not enough evidence by itself. Accept dependencies at the seam instead of constructing hidden global dependencies inside the module.

Return values where practical and isolate side effects at clear boundaries. Callers and tests should normally cross the same public seam.

## Deliver the decision

State the recommended shape, alternatives considered, verified callers affected, migration sequence, tests needed, and unresolved tradeoffs. Do not implement a redesign unless the user authorized implementation.

