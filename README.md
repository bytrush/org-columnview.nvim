# org-columnview.nvim

A port of the Emacs Org [column view](https://orgmode.org/manual/Column-View.html)
(`org-colview.el`) for Neovim.

The column view overlays a spreadsheet like table of properties on the headlines
of an org buffer and renders the agenda as a table of columns. Values can be
edited in place, and the column layout can be changed and is written back to the
buffer, like in Emacs.

This plugin requires [nvim-orgmode](https://github.com/nvim-orgmode/orgmode) for
the org file, headline and agenda handling. It works with the `master` branch
of nvim-orgmode; no patches are needed.

The plugin uses a few internal modules of nvim-orgmode (`orgmode.files`,
`orgmode.config`, `orgmode.agenda.view.*`, `orgmode.objects.*`,
`orgmode.org.links`), which are not a stable public API. Everything the plugin
needs beyond that is implemented in `lua/org-columnview/compat.lua`.

## Installation

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  'nvim-orgmode/orgmode',
  dependencies = {
    'bytrush/org-columnview.nvim',
  },
  config = function()
    require('orgmode').setup()
    require('org-columnview').setup()
  end,
}
```

`require('org-columnview').setup()` has to be called **after**
`require('orgmode').setup()`, because the plugin registers itself on the
orgmode instance.

## Usage

- `org_columns` (`<prefix>xc` by default) toggles the column view in an org
  buffer. It shows the subtree of the headline that owns the `COLUMNS`
  property, the subtree under the cursor when no entry owns it, or the whole
  file when the cursor is before the first headline. A count prefix
  (`1<prefix>xc`) always shows the whole file, like Emacs' `C-u C-c C-x C-c`.
- `org_columns_insert_dblock` (`<prefix>xx` by default) inserts a
  `#+BEGIN: columnview` dynamic block.
- `org_columns_update_dblock` (`<prefix>xu` by default) updates the block at
  the cursor; a count prefix (`1<prefix>xu`) updates every block in the
  buffer.
- `org_agenda_columns` (`<prefix>ac` by default) opens the agenda as a column
  view.

The prefix defaults to the prefix configured in nvim-orgmode
(`mappings.prefix`, `<Leader>o` by default), so the defaults are `<Leader>oxc`
for the org buffer and `<Leader>oac` for the agenda.

In the agenda, `<prefix>xc` opens the column view of the agenda as well, like
in Emacs, where the same key opens the view of the current buffer.

The column view is also an entry of the agenda prompt (`<prefix>oa`), under
the key `c`.

Both entry points are registered in the mapping groups of nvim-orgmode, so they
are attached to the org and the agenda buffer and are listed in the nvim-orgmode
help (`g?`). A global mapping is set as well, so that the column view can also
be opened from a buffer that was opened before the plugin was loaded.

The column format is read from the `COLUMNS` property of the headline or one of
its ancestors, from the `#+COLUMNS:` keyword of the file, or from the
`default_format` option. Without any of them the view is not shown.

## Dynamic blocks

`#+BEGIN: columnview` dynamic blocks export the view as a static Org table.
Place the cursor where the table should go and run
`:OrgColumnsInsertDblock`. Update the block at the cursor with
`:OrgColumnsUpdateDblock`, or every block in the buffer with
`:OrgColumnsUpdateAllDblocks`. The same actions are bound to `<prefix>xx`
(insert) and `<prefix>xu` (update; a count prefix updates all blocks).

```org
#+BEGIN: columnview :id local :hlines 1
|ITEM|OWNER|SCORE|
|-|
|Project||Σ=5|
#+END:
```

| Parameter | Value | Description |
|---|---|---|
| `:id` | `local` (default), `global`, `<ID>`, `file:<path>` | Scope of the table: the current `COLUMNS` owner subtree, the whole file, an entry with that `:ID:`, or a file. |
| `:format` | column format | Overrides the normal `COLUMNS` format. Quote it when it contains spaces: `:format "%10ITEM %10OWNER"`. |
| `:hlines` | `t` or a number | `t` inserts a horizontal line before every row. A number inserts one before rows with level ≤ N. Insert uses `1`. |
| `:indent` | `t` | Indents the ITEM cell by two spaces per outline level. |
| `:match` | match string | Keeps only entries matching the Org agenda tag/property match expression. |
| `:maxlevel` | number | Omits headlines below this outline level. |
| `:skip-empty-rows` | `t` | Drops rows whose non-ITEM columns are all empty. |
| `:vlines` | `t` | Adds Org column-group markers for vertical lines. |
| `:link` | `t` | Turns ITEM cells into links to their source headlines. |
| `:exclude-tags` | space-separated tags | Excludes entries carrying any of these tags. |
| `:formatter` | Lua function | Custom table formatter. Pass it through `require('org-columnview').update_columnview_dblock({ formatter = fn })`. |

`t` is the Org/Emacs boolean true value, not a placeholder: `:hlines t` means
“hline before every row”. Boolean parameters accept `t`/`true`/`1` to enable
and `nil`/`false`/`f`/`0` to disable.

Parameter names are case-insensitive in the block line. A quoted value may
contain spaces; unquoted values end at the next `:parameter`.

The table inside the block is parsed through a Tree-sitter injection, so
nvim-orgmode's table formatting, cell navigation and table-aware highlighting
work inside `columnview` blocks. Completion suggests `#+BEGIN: columnview`,
the block parameters, and common parameter values.

## Mappings

While the column view is active, these buffer local mappings are available:

| Key | Action |
|-----|--------|
| `h` / `l` | previous / next column |
| `k` / `j` | previous / next row |
| `1` … `9`, `0` | select the 1st..10th allowed value |
| `n` / `p` | next / previous allowed value |
| `e` | edit the value at point |
| `C-c C-c` | toggle the checkbox at point, or quit the column view |
| `q` | quit the column view |
| `v` | view the full value of the current cell |
| `a` | edit the allowed values of the current column |
| `<` / `>` | narrow / widen the current column (a count prefix adjusts by N) |
| `S-M-Right` / `S-M-Left` | insert / delete a column |
| `M-Left` / `M-Right` | move the current column left / right |
| `M-Up` / `M-Down` | move the current row up / down |
| `s` | edit the current column attributes (name, title, width, summary) |
| `r` | refresh the view from the file |
| `c` / `o` | switch between content and overview |
| `C-c C-o` | open the link at point |
| `C-c C-t` | change the TODO state |
| `g?` | show the help |

## Column format

A column format is a space separated list of column specifications:

```
%[width]PROPERTY[(Title)][{summary}]
```

- `width` - column width in characters (optional)
- `PROPERTY` - any property name, or one of the special column names below
- `(Title)` - display title (optional, defaults to the property name)
- `{summary}` - summary operator used for entries with children, optionally
  followed by `;FMT` (optional)

Allowed values are read from the `PROPERTY_ALL` property, matching Emacs. The
property is looked up on the entry and its ancestors, and finally file-wide via
`#+PROPERTY: PROPERTY_ALL ...` or `#+PROPERTY_ALL: ...`.

Legacy formats may still contain a second brace group with inline values or a
`{NAME_ALL}` reference. The plugin reads it for backwards compatibility, but
writes the values to `PROPERTY_ALL` and drops the brace on the next format
change. Inline allowed values are not portable to Emacs.

Add `:ETC` to a `PROPERTY_ALL` list to mark the values as suggestions rather
than a closed set. Cycling skips `:ETC`, while `e` accepts arbitrary input.

Editing the allowed values with `a` stores the string exactly as typed; both
comma-separated and whitespace-separated lists are parsed for cycling.

Special column names: `ITEM`, `CLOCKSUM`, `CLOCKSUM_T`, `AGE`, `TAGS`,
`ALLTAGS`, `TODO`, `PRIORITY`, `CATEGORY`, `SCHEDULED`, `DEADLINE`, `CLOSED`,
`TIMESTAMP`, `TIMESTAMP_IA`, `FILE` and `BLOCKED`.

Summary types: `+` (sum), `$` (currency sum), `:` (duration sum), `:min`,
`:max`, `:mean` (duration extremes and mean), `min`, `max`, `mean` (numeric),
`X`, `X/`, `X%` (checkboxes), `@min`, `@max`, `@mean` (age extremes and mean)
and `est+` (low/high estimates).

An optional `;FMT` after `+`, `min`, `max` or `mean` formats the summary and
the displayed cell values, e.g. `{+;%.2f}` or `{min;%.1f}`.

`X/` and `X%` count `[n/n]` and `[100%]` cookies as done. Age summaries
(`@min`, `@max`, `@mean`) accept Org timestamps or duration values.

With `write_summaries = true`, opening or refreshing the view writes each
summary into the first column's property on the parent entry. Only existing
properties are updated; missing properties are not created.

The format is looked up in this order: a `COLUMNS` property on the headline or
one of its ancestors, the `#+COLUMNS:` keyword in the file, and finally the
`default_format` option.

Changing the column layout (attributes, width, insert, delete, move) is
written back to the buffer, like in Emacs: into the `:COLUMNS:` property of the
headline the view started at when it has one, otherwise into the first
`#+COLUMNS:` keyword (created before the first headline if missing).

## Configuration

```lua
require('org-columnview').setup({
  -- Column format used when no COLUMNS property or #+COLUMNS: keyword is found
  default_format = '%25ITEM %10Effort(Effort){:} %10CLOCKSUM %10CLOCKSUM_T %10Tags %10TODO',
  -- Column format used in the agenda when nothing else is defined
  default_format_for_agenda = nil,
  -- Column format that overrides everything in the agenda
  overriding_columns_format = nil,
  -- Called with the column title and value to produce the text shown in the
  -- column view. Return nil to keep the original value.
  modify_value_for_display_function = nil,
  -- Custom summary operators. A definition is either a function
  -- (values, format) or a table { summarize = fn, collect = fn }.
  summary_types = {},
  -- Functions that return allowed values for a property, or nil.
  allowed_value_functions = {},
  -- Marker appended to truncated cells.
  ellipsis = '…',
  -- Values cycled by checkbox summary columns.
  checkbox_allowed_values = { '[ ]', '[X]' },
  -- Ignore trees tagged ARCHIVE.
  skip_archived_trees = true,
  -- Write computed summaries into existing parent properties.
  write_summaries = false,
  -- Prefix used for the mappings, defaults to the nvim-orgmode prefix
  prefix = nil,
  mappings = {
    org_columns = '<prefix>xc',
    org_agenda_columns = '<prefix>ac',
    column_view = {
      quit = 'q',
      move_left = 'h',
      -- ... see the table above
    },
  },
})
```

## Help

The full documentation is in the help file: `:help org-columnview`.

## Differences to Emacs

The column view is a port, not a byte for byte copy. The known differences are
tracked in the [Emacs parity backlog][parity] of this repository.

[parity]: https://github.com/nvim-orgmode/org-columnview.nvim/blob/master/COLUMN_VIEW_IMPLEMENTATION_PLAN.md
