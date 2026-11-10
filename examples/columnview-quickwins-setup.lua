-- Settings used by examples/columnview-quickwins-demo.org.
--
-- Load after nvim-orgmode and org-columnview.nvim are set up:
--   :luafile examples/columnview-quickwins-setup.lua
--
-- Change these values and reload to observe the behavior.

require('org-columnview').setup({
  -- 7.1.12: try '~' or '..'.
  ellipsis = '~',
  -- 7.1.13 / 7.2.8: extra intermediate state for the cycle.
  checkbox_allowed_values = { '[ ]', '[X]', '[-]' },
  -- 7.1.10: set to false to include the ARCHIVE-tagged tree.
  skip_archived_trees = true,
})
