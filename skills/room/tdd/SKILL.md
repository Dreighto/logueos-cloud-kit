---
name: tdd
description: Implement behavior through test-driven red-green slices. Use when the user asks for test-first development, TDD, red-green-refactor, regression tests, integration tests, or asks to build or fix behavior with proof that the test failed before the implementation.
---

# Test-Driven Development

Work one observable behavior at a time.

## Choose the seam

Identify the public interface through which callers observe the behavior. Prefer the seam named by the ticket, specification, existing tests, or repository convention. Ask the user only when competing seams would materially change the design.

Do not test private methods merely because they are easy to reach. If no honest public seam exists, surface that design problem before creating a misleading test.

## Run one red-green slice

1. State the behavior in user or domain language.
2. Write one focused test through the selected seam.
3. Derive the expected value from the specification, a worked example, or another independent source.
4. Run the focused test and capture its expected failure.
5. Write only enough implementation to make that test pass.
6. Run the focused test again.
7. Run the nearest relevant surrounding tests.
8. Repeat for the next behavior.

Keep slices vertical. Do not write an entire imagined test suite before learning from the first implementation cycle.

## Reject weak tests

Avoid tests that:

- duplicate the production algorithm inside the assertion;
- verify private calls or incidental implementation structure;
- mock every internal collaborator;
- pass before the requested behavior exists;
- rely on a broad snapshot when a direct behavior assertion is available;
- fail because of unrelated setup rather than the intended missing behavior.

## Refactor after green

Refactor only after the focused and surrounding tests are green. Preserve the same observable behavior and rerun the relevant suite after structural changes.

At handoff, report the seam, the fail-before-fix command and result, the passing command and result, and any behavior that remains intentionally uncovered.

