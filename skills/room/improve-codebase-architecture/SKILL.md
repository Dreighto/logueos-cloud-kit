---
name: improve-codebase-architecture
description: Scan a repo for real architecture-deepening opportunities, publish a scored report, then interrogate whichever candidate the operator picks. Use when the operator says improve the architecture, find deepening opportunities, audit module boundaries, or asks where a codebase should be simplified. It is a survey, not a rescue: it finds real candidates on an old codebase, it does not untangle the mud for you. Do NOT use for a single known bug or a refactor that already has a target; just do the work.
---

# Improve Codebase Architecture

## Explore

Weight the scan toward recent git activity (`git log` churn, hot files) over a cold static pass; a module touched often earns scrutiny a stable one does not. Apply the deletion test from `codebase-design`: for each candidate, ask what disappears and what reappears elsewhere if it were deleted. A pass-through that adds no complexity elsewhere is not a candidate; a seam that would force complexity into every caller is.

## Report

Publish the findings through `html-communication` (a page on the operator's own artifact host, self-contained, no CDN). Score each candidate Strong, Worth exploring, or Speculative, with the concrete evidence behind the score: churn count, caller count, the specific complexity that reappears on deletion. Do not inflate the count. A codebase with two real candidates gets a two-item report.

## Interrogate

Once the operator picks a candidate, call the Skill tool with 'grilling' to work the decision tree for that specific change: what it costs, what it risks, whether the operator actually wants it now.

## Scope

This is a survey, not a rescue. On a genuinely aged codebase it surfaces real candidates; it does not untangle years of accumulated shortcuts in one pass. Say so plainly in the report rather than promising more than the scan found.
