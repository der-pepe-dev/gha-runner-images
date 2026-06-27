---
name: start-task
description: Start an implementation session by reading the right project memory, inspecting relevant code, and creating a focused per-task plan file.
allowed-tools: Read, Grep, Glob, Bash, Edit, MultiEdit, Write
---

# Start task

Use this when beginning a non-trivial coding or documentation task.

## Steps

1. Read `docs/index.md`.
2. Read `docs/current-status.md`.
3. Read `docs/environment.md` (know what tools are available).
4. Read `docs/instructions/agent-rules.md`.
5. Read `docs/tasks/lessons.md` and apply relevant lessons.
6. Use `docs/context-map.md` to choose task-specific docs.
7. Inspect relevant source files before editing.
8. Create `docs/tasks/<task-name>.md` (copy `tasks/task-template.md`) with:
   - task goal,
   - relevant docs read,
   - files inspected,
   - checklist,
   - verification command(s),
   - risks/unknowns.
9. Keep the plan short enough to be useful.

## Do not

- Do not read the whole Obsidian tree by default.
- Do not use `todo.md` as a scratchpad.
- Do not update `current-status.md` before work is complete.
