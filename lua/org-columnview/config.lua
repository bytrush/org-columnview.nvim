---Configuration of the column view plugin.
---
---The options are read through this module instead of nvim-orgmode's config, so
---that the column view can be installed and updated independently of the core
---plugin. The `prefix` option defaults to the prefix used by nvim-orgmode.
---@class OrgColumnViewConfig
---@field default_format string Column format used when no `COLUMNS` property or `#+COLUMNS:` keyword is found
---@field default_format_for_agenda? string Column format used in the agenda when nothing else is defined
---@field overriding_columns_format? string Column format that overrides everything in the agenda
---@field modify_value_for_display_function? fun(column: string|nil, value: string): string|nil Called to modify the displayed value
---@field prefix? string Prefix used for the mappings, defaults to the nvim-orgmode prefix
---@field mappings table Mappings of the plugin
local M = {}

---@class OrgColumnViewConfigOpts
---@field default_format? string
---@field default_format_for_agenda? string
---@field overriding_columns_format? string
---@field modify_value_for_display_function? fun(column: string|nil, value: string): string|nil
---@field prefix? string
---@field mappings? table

---Default mappings of the column view. The `column_view` group holds the
---buffer local mappings that are active while the view is open, the other
---entries are the global entry points.
M.defaults = {
  default_format = '%25ITEM %10Effort(Effort){:} %10CLOCKSUM %10CLOCKSUM_T %10Tags %10TODO',
  default_format_for_agenda = nil,
  overriding_columns_format = nil,
  modify_value_for_display_function = nil,
  prefix = nil,
  mappings = {
    org_columns = '<prefix>xc',
    org_agenda_columns = '<prefix>ac',
    column_view = {
      quit = 'q',
      move_left = 'h',
      move_right = 'l',
      move_up = 'k',
      move_down = 'j',
      next_value = 'n',
      prev_value = 'p',
      select_value = { '1', '2', '3', '4', '5', '6', '7', '8', '9', '0' },
      view_value = 'v',
      edit_allowed = 'a',
      edit_value = 'e',
      toggle_or_quit = '<C-c><C-c>',
      narrow_column = '<',
      widen_column = '>',
      insert_column = '<S-M-Right>',
      delete_column = '<S-M-Left>',
      move_column_left = '<M-Left>',
      move_column_right = '<M-Right>',
      move_row_up = '<M-Up>',
      move_row_down = '<M-Down>',
      edit_attributes = 's',
      refresh = 'r',
      content = 'c',
      overview = 'o',
      open_link = { '<C-c><C-o>', '<prefix>o' },
      todo = { '<C-c><C-t>', '<prefix>t' },
      show_help = 'g?',
    },
  },
}

M.opts = vim.deepcopy(M.defaults)

---Merge the user options into the defaults.
---@param opts? OrgColumnViewConfigOpts
function M.setup(opts)
  M.opts = vim.tbl_deep_extend('force', vim.deepcopy(M.defaults), opts or {})
  return M
end

---Prefix used to expand the `<prefix>` placeholder. Falls back to the prefix
---configured in nvim-orgmode.
---@return string
function M.get_prefix()
  if M.opts.prefix and M.opts.prefix ~= '' then
    return M.opts.prefix
  end
  local core_config = require('orgmode.config')
  return core_config.mappings.prefix or ''
end

---@return table
function M.get_mappings()
  return M.opts.mappings or {}
end

return setmetatable(M, {
  __index = function(_, key)
    return rawget(M, 'opts')[key]
  end,
})
