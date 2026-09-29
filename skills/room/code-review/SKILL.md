---
name: code-review
description: "Review a branch, pull request, commit range, or working diff against two separate axes: the requested specification and the repository's engineering standards. Use when the user asks to review a PR, branch, diff, work in progress, implementation, or changes since a fixed point. Reviewing does not authorize fixing findings."
---

# Two-Axis Code Review

Judge what changed, not what the author intended to change.

## Establish the review target

Resolve the base commit, branch, tag, or merge base. Confirm the comparison exists and inspect both the commit list and the full diff. If the user did not name a base, infer the repository's normal base only when it is unambiguous.

Locate the originating ticket, specification, acceptance criteria, or operator request. Read repository instructions and standards before judging style or architecture.

## Review the specification axis

Check whether the change:

- implements every acceptance criterion;
- preserves behavior the specification says must remain;
- handles required failure and boundary cases;
- includes evidence at the correct seam;
- avoids functionality the specification did not authorize.

Do not invent requirements. Mark a spec gap as uncertainty rather than converting a preference into a defect.

## Review the standards axis

Check repository-specific rules first. Then inspect for concrete maintainability defects such as duplicated logic, unclear names, scattered changes for one concept, hidden coupling, speculative abstractions, leaky boundaries, missing cleanup, unsafe error handling, or tests tied to implementation details.

Tool-enforced formatting is not a review finding unless the tool actually fails.

## Report findings

List findings in severity order. Each finding must include:

- the affected file and line;
- the observable failure or maintenance cost;
- the evidence or scenario that demonstrates it;
- the smallest correction that would resolve it.

Keep the two axes distinguishable in the evidence, then provide one overall verdict. State when no findings were found and name any limits, such as missing runtime proof or unavailable specification material.

Remain read-only unless the user separately asks to address findings. An agent reviewing its own work is a quality check, not independent kernel verification.
