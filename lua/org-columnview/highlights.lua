---Highlight groups of the column view.
---
---The groups are defined by the plugin, so that it does not depend on
---nvim-orgmode providing them.
local M = {}

---The highlight groups of the column view and the group they link to.
M.groups = {
  ['@org.column.border'] = '@punctuation.special',
  ['@org.column.value'] = '@markup.list',
  ['@org.column.header'] = '@markup.heading',
  ['@org.column.current'] = 'Visual',
  ['@org.column.summary'] = '@number',
}

---Define the highlight groups of the column view.
function M.define()
  for group, link in pairs(M.groups) do
    vim.api.nvim_set_hl(0, group, { link = link, default = true })
  end
end

return M
