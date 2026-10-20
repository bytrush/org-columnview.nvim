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
    'nvim-orgmode/org-columnview.nvim',
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
  buffer. It shows the subtree of the headline under the cursor, or the whole
  file when the cursor is before the first headline.
- `org_agenda_columns` (`<prefix>xc` by default) opens the agenda as a column
  view.

The prefix defaults to the prefix configured in nvim-orgmode
(`mappings.prefix`, `<Leader>o` by default).

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
| `<` / `>` | narrow / widen the current column |
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
%[width]PROPERTY[(Title)][{summary}][{allowed values}]
```

- `width` - column width in characters (optional)
- `PROPERTY` - any property name, or one of the special column names below
- `(Title)` - display title (optional, defaults to the property name)
- `{summary}` - summary type used for entries with children (optional)
- `{allowed values}` - comma separated list (whitespace separated when there is
  no comma), or `NAME_ALL=` to reference the `NAME_ALL` property (optional).
  A referenced `NAME_ALL` property is looked up on the entry and its ancestors,
  and finally file-wide via `#+PROPERTY: NAME_ALL ...` or `#+NAME_ALL: ...`

Special column names: `ITEM`, `CLOCKSUM`, `CLOCKSUM_T`, `AGE`, `TAGS`,
`ALLTAGS`, `TODO`, `PRIORITY`, `CATEGORY`, `SCHEDULED`, `DEADLINE`, `CLOSED`,
`TIMESTAMP`, `TIMESTAMP_IA`, `FILE` and `BLOCKED`.

Summary types: `+` (sum), `$` or `+;%.2f` (formatted sum), `:` (duration sum),
`:min`, `:max`, `:mean` (duration extremes and mean), `min`, `max`, `mean`
(numeric), `X`, `X/`, `X%` (checkboxes), `@min`, `@max`, `@mean` (age extremes
and mean) and `est+` (low/high estimates).

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
  -- Prefix used for the mappings, defaults to the nvim-orgmode prefix
  prefix = nil,
  mappings = {
    org_columns = '<prefix>xc',
    org_agenda_columns = '<prefix>xc',
    column_view = {
      quit = 'q',
      move_left = 'h',
      -- ... see the table above
    },
  },
})
```

## Differences to Emacs

The column view is a port, not a byte for byte copy. The known differences are
tracked in the [Emacs parity backlog][parity] of the nvim-orgmode repository.

[parity]: https://github.com/nvim-orgmode/org-columnview.nvim/blob/master/COLUMN_VIEW_IMPLEMENTATION_PLAN.md
