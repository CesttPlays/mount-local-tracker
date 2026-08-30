---
name: update-context
description: Refresh this repo's persistent project memory in context/. Use after a feature lands, a bug fix is validated in-game, or the addon's scope/structure/requirements change — and when the user asks for a project refresh.
---

# Update Context

Keep the `context/` files accurate so a fresh session can resume without rediscovering the project.

## When to run
- A feature lands (merged or working in-game).
- A bug fix is validated in the live client.
- Addon structure, scope, or requirements change.
- The user asks for a full project refresh.

## What to update

### `context/context-cache.md`
Durable state only. Update these sections as relevant:
- current addon goals and scope
- known constraints / compatibility assumptions (target game build, API caveats)
- recent changes and validated fixes
- active risks, open items, follow-ups
- API or structure notes future sessions will need
Bump `Last updated:` to today's date. Keep it brief but complete — trim stale detail rather than letting it grow unbounded.

### `context/immediate-next-steps.md`
- Remove completed items; add newly surfaced work.
- Keep the priority-ordered list honest about the current blocker.

### `context/future-features.md`
- Add deferred ideas here instead of implementing them ahead of the current blocker.

## How
- Edit in place; preserve the existing headings and tone.
- Be specific: name the function, event, file, or command involved.
- Show the user the diff before writing if the change to project direction is non-trivial.
