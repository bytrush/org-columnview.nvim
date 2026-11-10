---Compatibility helpers for Tree-sitter table handling inside dynamic blocks.
---
---Tree-sitter parses `#+BEGIN: columnview` contents as a generic `contents`
---node. The injection query in `queries/org/injections.scm` reparses them as
---an Org table, but nvim-orgmode queries the root tree and therefore misses
---that injected table. This module teaches its table lookup to use the
---injected node when the cursor is inside a dynamic block.
local M = {}

---@param node TSNode|nil
---@return boolean
local function in_dynamic_block(node)
  while node do
    if node:type() == 'dynamic_block' then
      return true
    end
    node = node:parent()
  end
  return false
end

---@param bufnr number
---@param cursor table 1-based { line, column }
---@return TSNode|nil
local function injected_table_node(bufnr, cursor)
  local parser = vim.treesitter.get_parser(bufnr, 'org')
  parser:parse(true)
  local row = cursor[1] - 1
  local column = cursor[2]

  for _, child in pairs(parser:children()) do
    if type(child) == 'table' and child.trees then
      for _, tree in ipairs(child:trees()) do
        local node = tree:root():named_descendant_for_range(row, column, row, column)
        local table_node = node and require('orgmode.utils.treesitter').closest_node(node, 'table')
        if table_node then
          return table_node
        end
      end
    end
  end
  return nil
end

---Patch nvim-orgmode's table lookup once.
function M.setup()
  local Table = require('orgmode.files.elements.table')
  if Table._org_columnview_dblock then
    return
  end
  Table._org_columnview_dblock = true

  local ts_utils = require('orgmode.utils.treesitter')
  local original = Table.from_current_node

  Table.from_current_node = function(cursor)
    local lookup_cursor = cursor or vim.api.nvim_win_get_cursor(0)
    local node = ts_utils.get_node_at_cursor(lookup_cursor)
    if node and in_dynamic_block(node) then
      local table_node = injected_table_node(vim.api.nvim_get_current_buf(), lookup_cursor)
      if table_node then
        local saved = ts_utils.get_node_at_cursor
        ts_utils.get_node_at_cursor = function()
          return table_node
        end
        local ok, table = pcall(original, cursor)
        ts_utils.get_node_at_cursor = saved
        if ok and table then
          return table
        end
      end
    end
    return original(cursor)
  end
end

return M
