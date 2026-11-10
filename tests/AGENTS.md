# AGENTS.md

## Test-specific learnings

- Org-view specs reuse the same temp `columns.org` buffer. If a test calls
  `view:open()` and does not quit, that buffer stays `nomodifiable`; later
  `file:set_node_text()` calls are swallowed by an internal `pcall` and edits
  appear to do nothing. Reset `vim.bo[file:bufnr()].modifiable = true` in view
  helpers or close the view.
- Agenda specs share `org.files` across tests: every file created earlier is
  still returned by `files:all()`. Use unique headline titles and unique
  `PROPERTY_ALL` names, otherwise `headline_index` can resolve to an older file
  and implicit allowed-value lookup can leak between tests.
- Run `make test FILE=...` invocations sequentially. Parallel headless nvim
  runs share plenary/temp state and can hang or time out.
- CI matrix jobs have no sibling nvim-orgmode checkout, so
  `tests/minimal_init.lua` clones it. The clone must be **prepended** to
  `runtimepath` (`load_plugin(..., true)`); appending it lets Neovim's own
  `ftplugin/org.vim` set `b:did_ftplugin` first, so nvim-orgmode's ftplugin
  never runs and fold-dependent tests fail with `E490: No fold found`.
- Headless UI must be stubbed: `Calendar.new` needs an
  `open():next(function(date, cleared) ... end)` stub with real `Date` values,
  and `delete_column` needs `vim.fn.confirm` stubbed or it blocks.
- Dblock tests must call `require('org-columnview').setup()` before testing the
  injected table/tools; the command registration and `ts_compat` patch are
  installed by `setup()`.
