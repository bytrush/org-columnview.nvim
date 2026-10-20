# AGENTS.md

## AI Disclosure

If AI was used in any way for a commit, add an `AI-assisted: <tool name>` trailer to the commit message.
If the user commits manually, remind them to add it.

## Progress tracking

Track the progress in COLUMN_VIEW_IMPLEMENTATION_PLAN.md

## Relationship to nvim-orgmode

This plugin depends on [nvim-orgmode](https://github.com/nvim-orgmode/orgmode),
which provides the org file, headline and agenda handling. It uses these
nvim-orgmode modules:

- `orgmode.files` / `orgmode.files.headline` / `orgmode.files.file` — the data model
- `orgmode.config` — todo keywords, priority range, property inheritance
- `orgmode.agenda.view.*` — the agenda view primitives
- `orgmode.agenda.types` — the agenda view type registry (the plugin adds `columns`)
- `orgmode.objects.*` — dates, durations, todo and priority state, help
- `orgmode.org.links` — following links
- `orgmode.ui.input` — the input prompt

These are internal modules of nvim-orgmode, not a stable public API, so
changes there can break this plugin.
