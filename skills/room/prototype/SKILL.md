---
name: prototype
description: Build explicitly requested throwaway code to answer one design question about logic, state, interaction, or visual direction. Use only when the user directly asks for a prototype, proof of concept, disposable experiment, or several UI variants. Do not invoke merely because implementation is uncertain.
---

# Throwaway Prototype

A prototype answers one named question and carries no claim of production readiness.

## Set the boundary

Write down the question, success signal, authorized paths, runtime isolation, and disposal plan before creating files. Follow repository instructions and use an isolated branch or worktree when the prototype touches a real project.

Never point a prototype at production data, secrets, live write endpoints, or a canonical checkout used by a running service.

## Choose the artifact

- For logic or state questions, create the smallest runnable harness that exposes state transitions and difficult cases.
- For visual questions, create clearly separated alternatives so the user can compare directions. Apply the project's required frontend design skill before producing UI.

Keep state in memory unless persistence is the question being tested. Add only the error handling required to make the experiment safe and understandable. Label every prototype artifact as disposable.

## Close the experiment

Record the question, observed result, decision, and limitations. Move the accepted behavior into normal implementation through a separate authorized task. Remove the prototype or preserve it only on an explicitly named throwaway branch with a pointer from the decision record.

