# Column View Implementation Plan

## Overview
Implement Emacs Orgmode's Column View feature. Column View overlays a tabular structure over headlines, allowing viewing and editing of properties in a spreadsheet-like interface.

Reference: https://orgmode.org/manual/Column-View.html

> **Status: implemented as a separate plugin, with a known parity backlog.**
>
> The column view is **not** part of nvim-orgmode. It lives in its own
> repository, [org-columnview.nvim](https://github.com/nvim-orgmode/org-columnview.nvim),
> which depends on nvim-orgmode for the org file, headline and agenda
> handling. The split keeps a large feature out of the nvim-orgmode upstream
> and gives it its own release cycle.
>
> This document started as a design plan and has been reconciled with the
> shipped code. Items are tagged:
> `[DONE]` implemented, `[MISSING]` not in the codebase, `[DROPPED]` decided
> against (do not implement), `[TODO]` known gap that is queued for work.
>
> Documentation is shipped ([DONE] §6). The remaining work is the Emacs parity
> backlog tracked in [Phase 7](#phase-7-emacs-parity-backlog).

---

## Architecture

### Module Structure (actual)

Plugin (`org-columnview.nvim`):
```
lua/org-columnview/
├── init.lua              # setup(), org_columns/org_agenda_columns entry
│                         #   points, agenda type and completion registration
├── view.lua              # ColumnView class: render, navigation, editing,
│                         #   mapping setup, row/column move [DONE]
├── agenda.lua            # Agenda column view type [DONE]
├── parser.lua            # parse/unparse column definitions, specials [DONE]
├── summary.lua           # summary computations [DONE]
├── cells.lua             # shared value rendering (org + agenda) [DONE]
├── completion.lua        # allowed values completion source [DONE]
├── config.lua            # plugin options and default mappings [DONE]
├── mappings.lua          # in-view mappings and their help [DONE]
└── types.lua             # type definitions [DONE]
```

nvim-orgmode keeps the parts the plugin builds on:
```
lua/orgmode/
├── agenda/types/init.lua  # view type registry, the plugin adds 'columns' [DONE]
├── files/file.lua         # get_file_columns/set_file_columns,
│                          #   get_keyword_property [DONE]
└── files/headline.lua     # get_property/set_property, todo/priority state [DONE]
```

[DROPPED] `columns/renderer.lua` and `columns/editor.lua`: rendering and editing
are implemented inside `ColumnView` (`view.lua`), tightly coupled to view state.
Splitting them adds indirection without benefit.

### Integration Points
- **Plugin setup** (`org-columnview.setup()`): registers the agenda view type
  and the completion source on the current orgmode instance, and attaches the
  `org_columns`/`org_agenda_columns` mappings. It has to run after
  `require('orgmode').setup()`, because that call creates a new instance [DONE]
- **Agenda** (`lua/orgmode/agenda/init.lua`): the view type registry calls the
  optional `clear_mappings`/`clear_highlights` of every registered type before
  a view is rendered [DONE]
- **Agenda** (`lua/orgmode/agenda/init.lua`): `type = 'columns'` view, opened
  with `require('orgmode').action('agenda.columns')` [DONE]
- **Headline** (`lua/orgmode/files/headline.lua`): reuses `get_property`/`set_property` [DONE]

---

## Migration: From nvim-orgmode to this Plugin

The column view was implemented inside nvim-orgmode first (branch
`feat/columns`) and then moved into this repository, so that a large
feature does not have to be merged into nvim-orgmode upstream.

### What moved into the plugin

| Part | Location |
|------|----------|
| The column view of the org buffer | `lua/org-columnview/view.lua` |
| The column view of the agenda | `lua/org-columnview/agenda.lua` |
| The column format parser | `lua/org-columnview/parser.lua` |
| The summary computation | `lua/org-columnview/summary.lua` |
| The value rendering | `lua/org-columnview/cells.lua` |
| The highlight groups | `lua/org-columnview/highlights.lua` |
| The completion of the column format | `lua/org-columnview/columns_completion.lua` |
| The completion of the allowed values | `lua/org-columnview/completion.lua` |
| The options and the default mappings | `lua/org-columnview/config.lua` |
| The in-view mappings and the help | `lua/org-columnview/mappings.lua` |
| The helpers that nvim-orgmode does not provide | `lua/org-columnview/compat.lua` |

### What stays in nvim-orgmode

Only the generic parts, so that they can be merged upstream:

- the agenda calls the optional `clear_mappings`/`clear_highlights` of the
  registered view types before a view is rendered
- the agenda view types can edit a headline through the `on_edit` hook
- the agenda reports an error when a view type is not available
- the priority range is always a string
- the parent headline of an entry is nil when it has none
- the completion of the `CATEGORY` and `REPEAT_TO_STATE` values
- the `#+columns:`, `#+property:` and `:COLUMNS:` keywords in the
  completion of the directives and the properties

### What was dropped

- [DROPPED] The column view as an agenda custom command type
  (`org_agenda_custom_commands` with `type = 'columns'`). The agenda view
  is opened with the `org_agenda_columns` mapping and from the agenda
  prompt, which covers the use case. The core would have to know the
  options of the column view for the custom command.
- [DROPPED] The summary values are not written back to the property
  drawer, see §1.3.

### Integration with nvim-orgmode

The plugin uses internal modules of nvim-orgmode:

- `orgmode.files`, `orgmode.files.headline`, `orgmode.files.file` — the
  data model
- `orgmode.config` — todo keywords, priority range, property inheritance
- `orgmode.agenda.types` — the view type registry, the plugin adds the
  `columns` type to it
- `orgmode.agenda.view.*` — the agenda view primitives
- `orgmode.objects.*` — dates, durations, todo and priority state, help
- `orgmode.org.links` — following links
- `orgmode.ui.input` — the input prompt

These are not a stable public API, so changes in nvim-orgmode can break
the plugin. The test suite runs against the `master` branch of nvim-orgmode
in CI to catch that.

---

## Phase 1: Core Infrastructure

### 1.1 Column Definition Parser (`lua/org-columnview/parser.lua`) [DONE]

Parse column format strings like:
```
%25ITEM %10Effort(Effort){:} %10CLOCKSUM %Owner %Status_ALL
```

**Column Spec Format:**
- `%[width]NAME(Title){summary_type}{allowed_values}`

**Special columns implemented** (`Parser.is_special_column`):
`ITEM`, `CLOCKSUM`, `CLOCKSUM_T`, `AGE`, `TAGS`, `ALLTAGS`, `TODO`,
`PRIORITY`, `CATEGORY`, `SCHEDULED`, `DEADLINE`, `CLOSED`, `TIMESTAMP`,
`TIMESTAMP_IA`, `FILE`, `BLOCKED`.
(Plan originally listed only a subset; `ALLTAGS`, `SCHEDULED`, `DEADLINE`,
`CLOSED`, `FILE`, `BLOCKED`, `TIMESTAMP`, `TIMESTAMP_IA` were missing.)

**Parser Output:** `{ columns = OrgColumnSpec[], allowed_values = table }`
(see `columns/types.lua`).

**Sources for column definitions (in priority order):**
1. `COLUMNS` property on current/parent headline
2. `#+COLUMNS:` line in file
3. `org_columns_default_format` config
4. Agenda: `org-agenda-overriding-columns-format`,
   `org-columns-default-format-for-agenda`

`Parser.unparse` + `ColumnView:_store_format` (`org-columns-store-format`)
round-trip a changed layout back to the `COLUMNS` property or the first
`#+COLUMNS:` line. [DONE] (was missing from the plan)

### 1.2 Column View Class (`lua/org-columnview/view.lua`) [DONE]

Public surface (see `OrgColumnView` in `columns/types.lua`):
```lua
ColumnView:new(opts)        -- opts: files, links, headlines, columns_def,
                            --        subtree, bufnr, winid, on_quit
ColumnView:open()           -- lock buffer, winbar header, mappings, render
ColumnView:_render()        -- overlay header+rows via extmarks / winbar
ColumnView:edit_value()     -- minibuffer editing for the current cell
ColumnView:move_left/right/up/down()
ColumnView:quit()
```
[DROPPED] `edit_cell(row, col)` + floating inline editor: editing uses the
minibuffer (`vim.fn.input` / `vim.ui.select`), matching Emacs.
[DROPPED] generic `move_cursor(direction)`: implemented as distinct
`move_left/right/up/down` methods, clearer for keymap handlers.

### 1.3 Summary Computation (`lua/org-columnview/summary.lua`) [DONE]

Summary types implemented (superset of the original table):
| Type | Description |
|------|-------------|
| `+` / `$` (`+;%.2f`) / `+;FORMAT` | Sum (optionally formatted) |
| `min`, `max`, `mean` | Numeric extremes / mean |
| `:` | Sum of durations (`H:MM`) |
| `:min`, `:max`, `:mean` | Duration extremes / mean (was missing) |
| `X`, `X/`, `X%` | Checkbox all / fraction / percent (`X%` was missing) |
| `@min`, `@max`, `@mean` | Age (duration) extremes / mean (was missing) |
| `est+` | Combine low/high estimates |

Algorithm: compute per parent from its children's rendered values; values are
displayed inline as `Σ=...`.
[DROPPED] write-back of summary values to the parent's property drawer.
Emacs displays computed values inline; no store-to-property command is planned.

---

## Phase 2: Org Buffer Column View

### 2.1 Activation [DONE]
- Mapping: `org_columns` (default `<prefix>xc`); Emacs chord added separately
- Entry point: `OrgMappings:org_columns()`
- Context: point before first headline → whole file; inside subtree → that subtree

### 2.2 Rendering Strategy [DONE]
- Header rendered in the window **winbar** so it stays visible while scrolling
  (`ColumnView:_build_winbar`). [DROPPED] per-headline header extmark.
- Row cells overlaid with `nvim_buf_set_extmark` / `virt_text` (`overlay`),
  namespace `orgmode_column_view`; transient marks use `orgmode_column_view_track`.

### 2.3 Navigation & Editing [DONE]
Original list was incomplete. Shipped `column_view` actions
(`config/defaults.lua`):
- `move_left`/`move_right` (`h`/`l`), `move_up`/`move_down` (`k`/`j`)
- `move_row_up`/`move_row_down` (`M-Up`/`M-Down`)
- `select_value` (`1`..`9`,`0`), `next_value`/`prev_value` (`n`/`p`)
- `edit_value` (`e`), `toggle_or_quit` (`C-c C-c`), `quit` (`q`)
- `view_value` (`v`), `edit_allowed` (`a`)
- `narrow_column`/`widen_column` (`<`/`>`)
- `insert_column` (`S-M-RIGHT`), `delete_column` (`S-M-LEFT`)
- `move_column_left`/`move_column_right` (`M-LEFT`/`M-RIGHT`)
- `content` (`c`), `overview` (`o`), `open_link` (`C-c C-o` / `<prefix>o`),
  `todo` (`C-c C-t` / `<prefix>t`), `edit_attributes` (`s`), `refresh` (`r`),
  `show_help` (`g?`)
The plan omitted `content`, `overview`, `open_link`, `todo`, help, attributes,
and refresh.

### 2.4 Inline Editor [DONE]
- Allowed values from `PROPERTY_ALL` (`select_value`, `edit_value`)
- Checkbox toggle via `toggle_or_quit`
- Enum via `vim.ui.select` with an input fallback
- Free text via `vim.fn.input`
- On confirm: `headline:set_property(name, value)` / `set_todo` /
  `set_priority` / `set_tags`, then re-render
[DROPPED] floating input window (step 4 in the original plan).

---

## Phase 3: Agenda Column View

### 3.1 Agenda Type (`lua/org-columnview/agenda.lua`) [DONE]
Renders the agenda buffer as a column table; entry point `org_agenda_columns`
(`type = 'columns'`). (The plan did not mention the entry point.)

### 3.2 Column Format Resolution [DONE]
Per Emacs:
1. `org_agenda_overriding_columns_format` (custom agenda command)
2. `org_columns_default_format_for_agenda`
3. Format from the first agenda item (property or `#+COLUMNS`)
4. `org_columns_default_format`

### 3.3 Summary in Agenda [DONE]
Summary row is rendered; values are computed from the visible agenda rows.

---

## Phase 4: Configuration & Mappings

### 4.1 Config Defaults (`lua/org-columnview/config.lua`) [DONE]
```lua
default_format = '%25ITEM %10Effort(Effort){:} %10CLOCKSUM %10CLOCKSUM_T %10Tags %10TODO',
default_format_for_agenda = nil,
overriding_columns_format = nil,
modify_value_for_display_function = nil, -- [DONE] was missing
```
The options moved to the plugin together with the feature. The original
default format was stale (missing `CLOCKSUM_T`, `Tags`, `TODO`) and
`org_columns_modify_value_for_display_function`
(`org-columns-modify-value-for-display-function`) was not listed.

### 4.2 Mappings [DONE]
The `org_columns`/`org_agenda_columns` entry points and the in-view
`column_view` mapping group live in the plugin (`lua/org-columnview/init.lua`
and `lua/org-columnview/mappings.lua`). The in-view actions are buffer-local
and are set while the view is active. Actual action names:
`quit`, `move_left`, `move_right`, `move_up`, `move_down`, `move_row_up`,
`move_row_down`, `select_value`, `next_value`, `prev_value`, `edit_value`,
`toggle_or_quit`, `view_value`, `edit_allowed`, `narrow_column`,
`widen_column`, `insert_column`, `delete_column`, `move_column_left`,
`move_column_right`, `content`, `overview`, `open_link`, `todo`,
`edit_attributes`, `refresh`, `show_help`.
The original `col_view_*` names were never used.

---

## Phase 5: Testing

### 5.1 Unit Tests [DONE]
- `tests/plenary/org/columnview/parser_spec.lua`
- `tests/plenary/org/columnview/summary_spec.lua`
- `tests/plenary/org/columnview/view_spec.lua` (the plan's `view_spec.lua`)

### 5.2 Integration Tests [DONE]
- `tests/plenary/org/columnview/view_spec.lua` (org buffer view)
- `tests/plenary/agenda/types/columns_spec.lua` (agenda view)
- `tests/plenary/org/columnview/completion_spec.lua` (allowed values, column
  format)
- `tests/plenary/org/columnview/mappings_spec.lua` (entry points, agenda
  prompt menu)
The plan's `org_buffer_spec.lua` / `agenda_spec.lua` / `editing_spec.lua`
names do not exist; coverage lives in the files above.

### 5.3 Test Fixtures
[DONE] via inline buffers in the specs (no dedicated fixture files); acceptable.

---

## Phase 6: Documentation [DONE]

Shipped in the plugin (`README.md`) and, as a pointer, in the
`docs/configuration.org` (section "Column View") of nvim-orgmode with the
generated `doc/orgmode.txt`. Contents:
- Overview and activation (`org_columns`, `org_agenda_columns`)
- Column format syntax, special columns and summary types
- In-view keybindings
- Configuration (`org_columns_default_format`,
  `org_columns_default_format_for_agenda`,
  `org_agenda_overriding_columns_format`,
  `org_columns_modify_value_for_display_function`)
- Format persistence (`COLUMNS` / `#+COLUMNS`)
- Agenda column view

---

## Phase 7: Emacs Parity Backlog

Findings from a full diff of the shipped code against Emacs' `org-colview.el`
(Org 9.8.10) and `org.el`. Every item lists the Emacs behaviour, the current
behaviour in this codebase and where it lives.

Status: `[TODO]` queued, `[DONE]` shipped, `[DROPPED]` decided against,
`[N/A]` does not apply to the target Emacs version.

### 7.1 Missing features

| # | Feature | Emacs reference | Current state | Status |
|---|---------|-----------------|---------------|--------|
| 7.1.1 | `BEGIN_COLUMNVIEW` dynamic block (`org-columns-insert-dblock`) — export the view as a static table | `org-colview.el:1553` (`org-dblock-write:columnview`), `org-colview.el:1729` | no `COLUMNVIEW` support anywhere in `lua/` | [TODO] |
| 7.1.2 | Block parameters `:id`, `:format`, `:hlines`, `:indent`, `:match`, `:maxlevel`, `:skip-empty-rows`, `:vlines`, `:link`, `:exclude-tags`, `:formatter` | `org-colview.el:1553` | — | [TODO] (with 7.1.1) |
| 7.1.3 | Summary write-back into the parent's property drawer (`org-columns-compute-all`, `org-compute-property-at-point`) | `org-colview.el:1364`, `org.el:13994` | summaries are computed on the fly only; see §1.3 [DROPPED] | [TODO] (revisit the [DROPPED] decision) |
| 7.1.4 | User-defined summary operators (`org-columns-summary-types`) | `org-colview.el:88` | fixed table in `lua/org-columnview/summary.lua:6` | [TODO] |
| 7.1.5 | Allowed-values hook (`org-property-allowed-value-functions`) | `org.el:14007` | — | [TODO] |
| 7.1.6 | Per-date-line summaries in a normal agenda (`org-agenda-colview-summarize`) | `org-colview.el:1819` | agenda column view is one flat table, `lua/org-columnview/agenda.lua:441` | [TODO] |
| 7.1.7 | Recompute summaries in contributing buffers (`org-agenda-columns-compute-summary-properties`) | `org-colview.el:1883` | — | [TODO] |
| 7.1.8 | Appointment duration counts toward `Effort` (`org-agenda-columns-add-appointments-to-effort-sum`) | `org-colview.el:1883` | — | [TODO] |
| 7.1.9 | Start the agenda in column view (`org-agenda-view-columns-initially`) | `org-agenda.el:2103` | — | [TODO] |
| 7.1.10 | Skip archived trees (`org-columns-skip-archived-trees`) | `org.el:4142` | — | [TODO] |
| 7.1.11 | Global column view via prefix argument (`C-u C-c C-x C-c`) | `org-colview.el:887` | scope is always the cursor's headline, `lua/org-columnview/init.lua:70` | [TODO] |
| 7.1.12 | Configurable truncation marker (`org-columns-ellipses`, default `..`) | `org.el:3221` | hardcoded `…`, `lua/org-columnview/cells.lua:229` | [TODO] |
| 7.1.13 | Configurable checkbox values (`org-columns-checkbox-allowed-values`) | `org-colview.el:62` | hardcoded `[ ]`/`[X]` | [TODO] |

### 7.2 Editing semantics that diverge from Emacs

| # | Action | Emacs behaviour | Current behaviour | Status |
|---|--------|-----------------|-------------------|--------|
| 7.2.1 | `e` on `ITEM` | `org-edit-headline` on the source entry | writes a property named `ITEM`, `lua/org-columnview/view.lua:1107` | [TODO] |
| 7.2.2 | `e` on `CLOCKSUM`/`CLOCKSUM_T` | error "This special column cannot be edited" | writes a `clocksum` property | [TODO] |
| 7.2.3 | `e` on `SCHEDULED`/`DEADLINE` | opens the date editor | writes a plain property | [TODO] |
| 7.2.4 | `n`/`p` on `SCHEDULED`/`DEADLINE` | shifts the date by ±1 day (`org-colview-construct-allowed-dates`) | cycles `[ ]`/`[X]` into the property, `lua/org-columnview/view.lua:792`, `lua/org-columnview/view.lua:711` | [TODO] |
| 7.2.5 | `n`/`p`, `1`–`0` on a property without allowed values | error "Allowed values for this property have not been defined" | silently cycles `[ ]`/`[X]` and writes it | [TODO] |
| 7.2.6 | `:ETC` in a `PROP_ALL` list (means "other values allowed") | marks the first value `org-unrestricted`, prompt accepts anything | not supported | [TODO] |
| 7.2.7 | `edit_allowed` storage format | raw string, as typed | comma separated list | [TODO] |
| 7.2.8 | Checkbox toggle (`C-c C-c`) | toggles whenever the raw value matches `\[[ xX-]\]` | also requires a non-special column, `lua/org-columnview/view.lua:1131` | [TODO] |

### 7.3 Format / parser gaps

| # | Item | Emacs behaviour | Current behaviour | Status |
|---|------|-----------------|-------------------|--------|
| 7.3.1 | Per-column format `FMT` (`{op;fmt}`) | `+`, `min`, `max`, `mean` honour it; any column with a format renders `(format fmt (string-to-number value))` | only `+;fmt` is honoured (`summary.lua:30`); `min;fmt`/`max;fmt`/`mean;fmt` ignored; the format is never applied to the displayed cell value (`cells.lua:32`) | [TODO] |
| 7.3.2 | Format grammar | one brace group `{OPERATOR}`; allowed values live only in the `PROP_ALL` property | a second brace group carries inline allowed values (`parser.lua:235`), so `%10Owner{Owner_ALL}` is an unknown operator in Emacs | [DROPPED] (diverges by design, but formats are not exchangeable with Emacs) |
| 7.3.3 | `%%` escaping, `!` no-summary, `+`/`-`/`:` prefixes | not in Org 9.8 | not implemented | [N/A] |

### 7.4 Summary semantics gaps

| # | Item | Emacs behaviour | Current behaviour | Status |
|---|------|-----------------|-------------------|--------|
| 7.4.1 | `X/` and `X%` | also count `[n/n]` and `[100%]` as done | only `[X]` counts (`summary.lua:245`, `summary.lua:263`) | [TODO] |
| 7.4.2 | `@min`/`@max`/`@mean` (age) | age = `now - timestamp` in minutes, or a duration | the raw value is parsed as number/duration, no timestamp handling (`summary.lua:285`) | [TODO] |
| 7.4.3 | Summary values stored in the drawer | written for the first column using the property | never written back | [TODO] (same as 7.1.3) |

### 7.5 Scope and UX differences

| # | Item | Emacs behaviour | Current behaviour | Status |
|---|------|-----------------|-------------------|--------|
| 7.5.1 | View scope | scoped to the ancestor that owns the `COLUMNS` property | scoped to the headline under the cursor, so a child of a `:COLUMNS:`-owning parent shows only its own subtree | [TODO] |
| 7.5.2 | Header rendering | `header-line-format` with `\|` separators, scrolls horizontally with the window | winbar with `│` borders, no hscroll sync (`init.lua:373`) | [DROPPED] (winbar is the Neovim equivalent) |
| 7.5.3 | `narrow`/`widen` | accept a prefix argument (width ± N) | fixed ±1, `view.lua:1150`, `view.lua:1169` | [TODO] |
| 7.5.4 | `delete_column` | asks for confirmation (`y-or-n-p`) | deletes without confirmation, `view.lua:1240` | [TODO] |
| 7.5.5 | `insert_column` (`org-columns-new`) | prompts for Property (with completion from buffer property keys), Title, Width, Summary (with completion) and Format | prompts only for name and width, `view.lua:1186` | [TODO] |
| 7.5.6 | `edit_attributes` | same prompt set as `org-columns-new` | prompts name/title/width/summary, no completion and no format part, `view.lua:1209` | [TODO] |
| 7.5.7 | `content`/`overview` | `org-cycle-content` / `org-cycle-overview` (toggle) | implemented with folding, `view.lua:642`, `view.lua:650` | [DROPPED] |
| 7.5.8 | Agenda column view | overlays the existing agenda buffer | separate agenda type `type = 'columns'` | [DROPPED] |
| 7.5.9 | `ITEM` column | level stars (`* `), omitted in the agenda | indentation by two spaces per level | [DROPPED] |
| 7.5.10 | `org-columns-move-row-up`/`-down` | moves the subtree and restores the column position | implemented, `view.lua:522` | [DONE] |

### 7.6 Progress

Ordered by value per effort; update the checkbox when an item ships.

- [ ] 7.2.1–7.2.5 editing semantics (correctness: today these can write junk
      values such as `[ ]` into `POINTS` or `SCHEDULED`)
- [ ] 7.3.1 per-column format `FMT`
- [ ] 7.4.1, 7.4.2 summary semantics
- [ ] 7.1.11 global column view, 7.5.1 view scope
- [ ] 7.5.3–7.5.6 column editing polish
- [ ] 7.1.4, 7.1.5 config hooks
- [ ] 7.1.1, 7.1.2 `BEGIN_COLUMNVIEW` block
- [ ] 7.1.6–7.1.9 agenda parity
- [ ] 7.1.3, 7.4.3 summary write-back
- [ ] 7.1.12, 7.1.13, 7.2.6–7.2.8 small config/behaviour items

---

## Implementation Priority (as shipped)

| Priority | Component | Status |
|----------|-----------|--------|
| 1 | Column parser | [DONE] |
| 2 | Summary computation | [DONE] |
| 3 | Org buffer view + rendering | [DONE] |
| 4 | Inline editing | [DONE] |
| 5 | Navigation mappings | [DONE] |
| 6 | Agenda column view | [DONE] |
| 7 | Config & defaults | [DONE] |
| 8 | Tests | [DONE] |
| 9 | Documentation | [DONE] |
| 10 | Extraction into a separate plugin | [DONE] |
| 10a | Migration cleanup of the core | [DONE] |
| 11 | Emacs parity backlog | [TODO] (see [Phase 7](#phase-7-emacs-parity-backlog)) |

---

## Key Technical Decisions

### Rendering Approach
**Option A: virtual text overlay (chosen)**
- Pros: non-destructive, preserves folds, fast
- Cons: limited to single line per headline

**Option B: buffer replacement (rejected)**
- Pros: full table editing
- Cons: complex, breaks folds, conflicts with other features

### Property Storage
- `Headline:get_property` / `set_property`; properties in `:PROPERTIES:`.
- [DROPPED] summary write-back to the parent's drawer.
  Reopened as backlog item 7.1.3 / 7.4.3: Emacs writes the aggregate into the
  drawer for the first column that uses the property.

### Treesitter Integration
- Reuse the existing `Headline` class; no new parser queries.
- Row visibility is derived from `foldclosed` (`ColumnView:_is_row_visible`).

### Folding (added after the original plan)
- Rows inside closed folds are skipped.
- `move_row_up`/`move_row_down` re-close the folds opened by `:move` after the
  fold structure is recomputed, and only fall back to disabling folding when
  the moved range partially overlaps a closed fold.

### Async vs Sync
- Rendering: sync; file loading: async (`files:load`); summaries: sync.

---

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Performance on large files | Limit to visible subtree; lazy computation |
| Conflict with folds | `virt_text_pos = 'overlay'`; skip/restore closed folds |
| Property inheritance complexity | Reuse `get_property(name, true)` |
| Editing during column view | Lock buffer modifications while view active |

---

## Future Enhancements (Post-MVP)
- Column view in capture/refile
- Column sorting/filtering (like `org-colviewx`)
- Persistent column layouts per file

Items that are Emacs parity work rather than new ideas are tracked in
[Phase 7](#phase-7-emacs-parity-backlog):
- Export column view to table → 7.1.1 / 7.1.2 (`BEGIN_COLUMNVIEW` block)
- Custom summary types via config → 7.1.4
