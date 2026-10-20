# AGENTS.md

## AI Disclosure

If AI was used in any way for a commit, add an `AI-assisted: <tool name>` trailer to the commit message.
If the user commits manually, remind them to add it.

Commit messages follow Conventional Commits (`feat:`, `fix:`, `docs:`).

## Progress tracking

`COLUMN_VIEW_IMPLEMENTATION_PLAN.md` is the source of truth for progress. It is
both a reconciled plan and an Emacs parity backlog. Items are tagged `[DONE]`,
`[TODO]`, `[DROPPED]` (decided against) or `[N/A]`. When a change lands, update
the tag, the `file:line` reference in the backlog table, and the checkbox in
§7.6.

## Commands

```sh
make test                                             # whole suite
make test FILE=tests/plenary/org/columnview/parser_spec.lua   # one file or dir
make test-ci                                          # CI: runs the suite 3x
make lint                                             # stylua --check lua/ tests/
make format                                           # stylua
```

- `make test FILE=...` only honours paths containing `tests/plenary/`
  (`tests/test.lua:21`); anything else silently runs the whole suite.
- `stylua` is not vendored and is not on `PATH` here - install it before
  `make lint` / `make format`. Config (`stylua.toml`): 120 columns, 2 spaces,
  single quotes preferred, `call_parentheses = "Always"`.
- No typecheck command is configured. Types are only expressed through the
  LuaCATS annotations that `.luarc.json` feeds to lua-language-server.

## Test harness

`tests/test.lua` -> `tests/minimal_init.lua`:

- nvim-orgmode is located in this order: `$ORGMODE_PATH`, `../orgmode`,
  `../nvim-orgmode`, otherwise it is cloned into `tests/.deps/`. The sibling
  `../orgmode` checkout sits on the `feat/columns` branch; CI additionally runs
  the suite against nvim-orgmode `master`
  (`.github/workflows/tests.yml`, job `tests-against-orgmode-master`).
  Use `ORGMODE_PATH=<checkout> make test` to pin a version.
- The minimal init installs the tree-sitter grammar and exits 1 when that
  fails. On Windows it exits 0 without running any test.
- Test environment: `TZ=Europe/London` and `mapleader=','` - date and
  priority assertions depend on them.
- Specs live in `tests/plenary/**/*_spec.lua`. There are no fixture files on
  disk; `tests/plenary/helpers.lua` writes temp `.org` files
  (`create_file`, `create_agenda_file`, `create_agenda_files`, `load_file`).
- `tests/.deps/` is gitignored; `make clean` removes it.

## Architecture

`lua/org-columnview/`:

| module | role |
|---|---|
| `init.lua` | `setup()`, the `org_columns` / `org_agenda_columns` entry points, agenda type and completion registration |
| `view.lua` | `ColumnView` class: overlay rendering in an org buffer, navigation, editing |
| `agenda.lua` | the agenda view type, registered as `columns` |
| `parser.lua` | parse / unparse of the column format, list of special columns |
| `summary.lua` | the summary operators |
| `cells.lua` | cell value rendering, shared by the org and the agenda view |
| `completion.lua` | completion source for the allowed values of a property |
| `columns_completion.lua` | completion source for the column format in `#+COLUMNS:` / `:COLUMNS:` |
| `config.lua` | plugin options and the default mappings |
| `mappings.lua` | in-view mappings, the help window, registration in the nvim-orgmode mapping groups |
| `types.lua` | LuaCATS type definitions only |
| `compat.lua` | helpers for the nvim-orgmode APIs the plugin needs but nvim-orgmode does not expose |
| `highlights.lua` | the `@org.column.*` highlight groups, defined by the plugin and not by nvim-orgmode |

## nvim-orgmode coupling

- The plugin uses **internal** nvim-orgmode modules, not a stable API:
  `orgmode.files*`, `orgmode.config*`, `orgmode.agenda.view.{init,line,token}`,
  `orgmode.agenda.types`, `orgmode.agenda.filter`, `orgmode.agenda.sorting_strategy`,
  `orgmode.objects.*`, `orgmode.org.links`, `orgmode.ui.input`,
  `orgmode.utils.promise`. Upstream changes can break the plugin.
- `compat.lua` exists so the plugin works against nvim-orgmode `master`:
  file-level `#+COLUMNS:` / `#+PROPERTY:` reads, writing the format back into
  the buffer, link extraction, the TODO fast access and the parent-headline
  lookup are implemented locally instead of using nvim-orgmode helpers.
- Read file-level keywords through the **un-memoized** `file:_get_directive(name)`
  (`compat.get_file_directive`). The public memoized `get_directive` can return
  a stale value.
- `require('org-columnview').setup()` must run **after**
  `require('orgmode').setup()`, because that call creates a new instance. The
  agenda type and the completion source are registered on that instance, so
  they have to be registered again after every `orgmode.setup()`.
- `init.lua:check_compatibility()` lists the nvim-orgmode modules the plugin
  requires and errors with a clear message when one is missing. Keep that list
  in sync when a new nvim-orgmode module is used.
- `orgmode.completion` uses the start position of the **first** source that
  returns one, and applies that shared base to every source. A source must
  therefore return `nil` for lines it does not own; otherwise other sources'
  results are filtered against the wrong prefix (this broke the second token of
  `:COLUMNS:`).

## Conventions

- LuaCATS annotations (`---@class`, `---@param`, `---@return`, `---@field`) on
  the public API of every module. Keep `types.lua` in sync with the fields
  you add.
- A short module doc comment at the top of each file.
- Column spec grammar: `%[width]NAME(Title){summary}{allowed values}`. The
  second brace group (inline allowed values) is a **deliberate** divergence
  from Emacs, where allowed values live only in `NAME_ALL` properties. Do not
  "fix" it without updating `COLUMN_VIEW_IMPLEMENTATION_PLAN.md` §7.3.2.
- New special columns go into `SPECIAL_COLUMNS` in `parser.lua` and get a
  branch in `cells.lua:get_special_value`.
- The org-buffer view draws its header into the window `winbar` and the cells
  as `virt_text` overlay extmarks in the `orgmode_column_view` namespace; the
  agenda view uses the `orgmode_agenda_columns` namespace and only binds the
  actions listed in `agenda.lua:COLUMN_ACTIONS`.
