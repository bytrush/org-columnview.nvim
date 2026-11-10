-- Manual test settings for starting the agenda in column view (7.1.9).
--
-- Load this after nvim-orgmode is available:
--   :luafile examples/columnview-agenda-initial-setup.lua
--
-- It points the agenda at the matching demo file and enables the column view
-- for newly opened agendas.

require('orgmode').setup({
  org_agenda_files = { vim.fn.getcwd() .. '/examples/columnview-agenda-initial-demo.org' },
})

require('org-columnview').setup({
  agenda_columns_initially = true,
})
