# AGENTS.md

## Module-specific learnings

- `Parser.unparse` never writes allowed values. `ColumnView:_store_format`
  migrates `col.allowed_values` into `PROPERTY_ALL` (headline property or
  `#+PROPERTY`) before serializing, and `edit_allowed` clears the legacy brace.
  Change these together or legacy values are lost or written non-portably.
- Custom summary operators are resolved in three places: `Parser` uses
  `Summary.is_summary_type`, `Summary.compute` prefers a configured custom
  `summarize`, and `Cells:get_value` applies a custom `collect`. A new feature
  touching summary types usually needs all three.
- The Tree-sitter grammar stores `#+BEGIN: columnview` bodies in a generic
  `contents` node. `queries/org/injections.scm` reparses them as Org tables, and
  `ts_compat.lua` patches `Table.from_current_node` because
  `vim.treesitter.get_node` defaults to `ignore_injections = true`. Both files
  are required for table tools inside dynamic blocks.
- When delegating from the patched `Table.from_current_node`, pass the original
  `cursor` through unchanged: a `nil` cursor means "use end of line" in
  nvim-orgmode's table lookup.
- New mapping entry points need four pieces kept in sync: the default in
  `config.lua`, the entry in `mappings.lua:M.entry_points`, a public function in
  `init.lua`, and a special case in `setup_entry_points` when a count prefix is
  significant. Vim uses `vim.v.count`; `<C-u>` is not a normal-mode count.
- `compat.input_with_completion` uses a `customlist,v:lua...` callback and
  requires `_G.orgmode`; tests can stub `vim.fn.input` and ignore the table
  argument. Keep prompts synchronous unless the whole call chain is promise-based.
