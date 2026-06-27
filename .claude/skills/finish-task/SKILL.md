---
name: finish-task
description: Finish a task by verifying changes, recording evidence, and updating only the project memory that actually changed.
allowed-tools: Read, Grep, Glob, Bash, Edit, MultiEdit, Write
---

# Finish task

Use this at the end of a coding or documentation task.

## Steps

1. Run the narrowest relevant verification: targeted test, project build, solution
   build, smoke run, or log/output check.
2. Capture verification evidence in `docs/tasks/<task-name>.md`.
3. Summarize exact files changed.
4. Update `docs/tasks/todo.md` only if backlog status changed.
5. Update `docs/current-status.md` only if durable project status changed.
6. Update `docs/index.md` only if important docs were added/removed/renamed.
7. Append to `docs/tasks/lessons.md` only if a reusable lesson was learned.
8. Move the task file to `docs/tasks/done/`.
9. Report: completed work, verification evidence, unverified items, next step.

## Completion rule

Do not mark the task complete without evidence. If evidence is unavailable, say why.
