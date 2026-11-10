-- Settings used by examples/columnview-summary-writeback-demo.org.
--
-- Load after nvim-orgmode and org-columnview.nvim are set up:
--   :luafile examples/columnview-summary-writeback-setup.lua
--
-- This is the opt-in that makes opening or refreshing the view write computed
-- summaries into existing parent properties.

require('org-columnview').setup({
  write_summaries = true,
})
