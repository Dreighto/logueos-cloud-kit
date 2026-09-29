---
name: maintain-verification-map
description: Re-walk a project's verification map and actually drive every listed feature live, to catch silent feature rot before it's reported as a bug. Use when the operator says re-check the feature map, run the verification map for X, or before a release when a project already has a .claude/skills/verify-<project>/ map. Do NOT use to create the map for the first time; that is create-verification-map. Do NOT skip a feature because the source read clean; that is the exact failure this skill exists to catch.
---

# Maintain Verification Map

## Read the map

Open the target project's `.claude/skills/verify-<project>/SKILL.md`. If it does not exist, stop and run create-verification-map first.

## Drive every feature live

Walk the list top to bottom and actually perform each drive-it-live step against the running app or service. Reading the code and concluding a feature "looks fine" is not a pass. A pass requires seeing the real result the map describes.

## Update the map

If a feature's real behavior changed (a new step, a changed number, a removed feature), correct the map entry in place. If a feature was added since the last maintain pass and has no entry, add one before finishing.

## Report

List every feature checked, its result, and the date. Flag any feature that failed live despite a clean-looking diff or code review; that gap is the whole reason this skill exists, and it belongs in the report even if it feels embarrassing.
