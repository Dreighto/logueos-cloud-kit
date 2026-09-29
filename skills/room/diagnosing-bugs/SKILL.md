---
name: diagnosing-bugs
description: Diagnose hard bugs, regressions, flaky behavior, crashes, incorrect output, and performance problems through a reproducible evidence loop. Use when the user says diagnose, debug, investigate a failure, find the root cause, or reports that something is broken, failing, throwing, flaky, or slow. A diagnosis request does not authorize implementing the fix.
---

# Diagnosing Bugs

Build evidence before forming a confident explanation.

## Preserve the requested scope

Determine whether the user asked for diagnosis, a fix, or both. Keep diagnosis-only work read-only apart from temporary local test artifacts that the repository rules explicitly permit. Do not turn a diagnosis request into an implementation.

## Build a feedback loop

Create the smallest practical signal that exercises the reported symptom. Prefer, in order:

1. A focused test at the public seam.
2. A CLI, HTTP, or fixture-driven reproduction.
3. A browser script that asserts the visible or network symptom.
4. A captured trace replay or differential old-versus-new run.
5. A narrowly scoped local harness.
6. Read-only telemetry or profiler evidence when production behavior cannot be reproduced locally.

Run the loop before treating it as evidence. Record the command, exact symptom, and result. Tighten it until it is as deterministic, fast, and specific as the environment permits.

If no usable loop is possible, state what was attempted and name the missing artifact or access needed. Do not present an untested theory as the root cause.

## Minimize and hypothesize

Reduce the reproduction one variable at a time. Keep only inputs and dependencies required for the failure.

Write three to five ranked, falsifiable hypotheses. For each one, state the observation that would support it and the observation that would disprove it. Test one variable at a time.

## Instrument narrowly

Prefer debugger or REPL inspection, then targeted boundary logs, then profiling for performance problems. Tag temporary instrumentation with a unique marker and remove it before completion. Do not log secrets or broad production payloads.

## Finish at the authorized boundary

For diagnosis-only work, report:

- the confirmed symptom and reproduction method;
- the root cause, or the remaining ranked hypotheses if proof is incomplete;
- the evidence that rules alternatives in or out;
- the smallest recommended fix and regression seam;
- what remains uncertain.

When a fix is authorized, turn the minimized reproduction into a failing regression test at the correct seam, apply the smallest fix, rerun the original loop, run relevant surrounding tests, and remove all temporary instrumentation.

