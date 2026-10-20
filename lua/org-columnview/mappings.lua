---Mappings of the column view.
---
---The `column_view` group holds the buffer local mappings that are active while
---the view is open, the other entries are the global entry points that open
---the view.
local config = require('org-columnview.config')

---@class OrgColumnViewMappings
local M = {}

---Keys that were attached per buffer, so that they can be removed again.
---@type table<number, string[]>
M._attached = {}

---Descriptions of the in-view actions, shown in the help window.
M.descriptions = {
  quit = 'Quit the column view',
  move_left = 'Move to the previous column',
  move_right = 'Move to the next column',
  move_up = 'Move to the previous row',
  move_down = 'Move to the next row',
  next_value = 'Select the next allowed value',
  prev_value = 'Select the previous allowed value',
  select_value = 'Select the nth allowed value (1-9, 0 for the 10th)',
  view_value = 'View the full value of the current cell',
  edit_allowed = 'Edit the allowed values of the current column',
  edit_value = 'Edit the value at point',
  toggle_or_quit = 'Toggle the checkbox at point, or quit the column view',
  narrow_column = 'Make the current column narrower',
  widen_column = 'Make the current column wider',
  insert_column = 'Insert a new column',
  delete_column = 'Delete the current column',
  move_column_left = 'Move the current column left',
  move_column_right = 'Move the current column right',
  move_row_up = 'Move the current row up',
  move_row_down = 'Move the current row down',
  edit_attributes = 'Edit the attributes of the current column',
  refresh = 'Refresh the view from the file',
  content = 'Switch to the content view',
  overview = 'Switch to the overview',
  open_link = 'Open the link at point',
  todo = 'Change the TODO state',
  show_help = 'Show this help',
}

---Expand the `<prefix>` placeholder in a key.
---@param key string
---@return string
function M.expand_prefix(key)
  local prefix = config.get_prefix()
  if prefix == '' then
    return key
  end
  return (key:gsub('<prefix>', prefix))
end

---Normalize a mapping definition into a list of keys.
---@param mapping string|string[]|false|nil
---@return string[]|nil
local function to_keys(mapping)
  if mapping == nil or mapping == false then
    return nil
  end
  if type(mapping) == 'string' then
    return { mapping }
  end
  return mapping
end

---Resolve the mappings of the in-view actions. The user configuration takes
---precedence over the defaults, `false` disables a mapping.
---@return table<string, { name: string, keys: string[], desc: string }>
function M.get_view_mappings()
  local mappings = config.get_mappings()
  local defaults = config.defaults.mappings.column_view
  local user = mappings.column_view or {}
  local result = {}

  for name, default_keys in pairs(defaults) do
    local keys = to_keys(user[name] ~= nil and user[name] or default_keys)
    if keys and #keys > 0 then
      result[name] = {
        name = name,
        keys = vim.tbl_map(M.expand_prefix, keys),
        desc = M.descriptions[name] or name,
      }
    end
  end

  return result
end

---Attach the buffer local mappings of the column view.
---@param view OrgColumnView
---@param bufnr number
function M.setup_view_mappings(view, bufnr)
  local attached = {}

  for _, mapping in pairs(M.get_view_mappings()) do
    if mapping.name == 'select_value' then
      M._setup_select_value(view, bufnr, mapping.keys, attached)
    else
      for _, key in ipairs(mapping.keys) do
        table.insert(attached, key)
        vim.keymap.set('n', key, function()
          if view[mapping.name] then
            view[mapping.name](view)
          end
        end, {
          buffer = bufnr,
          nowait = true,
          silent = true,
          desc = mapping.desc,
        })
      end
    end
  end

  M._attached[bufnr] = attached
end

---Remove the buffer local mappings of the column view.
---@param bufnr number
function M.clear_view_mappings(bufnr)
  for _, key in ipairs(M._attached[bufnr] or {}) do
    pcall(vim.keymap.del, 'n', key, { buffer = bufnr })
  end
  M._attached[bufnr] = nil
end

---Bind every configured key to `select_value` with the matching index, so that
---`1`..`9` and `0` select the 1st..10th allowed value like in Emacs.
---@param view OrgColumnView
---@param bufnr number
---@param keys string[]
---@param attached? string[]
function M._setup_select_value(view, bufnr, keys, attached)
  for idx, key in ipairs(keys) do
    if attached then
      table.insert(attached, key)
    end
    vim.keymap.set('n', key, function()
      view:select_value(idx)
    end, {
      buffer = bufnr,
      nowait = true,
      silent = true,
      desc = M.descriptions.select_value,
    })
  end
end

---The entry points of the plugin and the nvim-orgmode mapping group they
---belong to.
M.entry_points = {
  { name = 'org_columns', category = 'org' },
  { name = 'org_agenda_columns', category = 'agenda' },
}

---Whether the current buffer is an agenda buffer.
---@return boolean
local function is_agenda_buffer()
  return vim.bo.filetype == 'orgagenda'
end

---Register the entry points in the mapping groups of nvim-orgmode, so that
---they are attached to the org and agenda buffers and show up in the mapping
---list and in the help of nvim-orgmode.
---@param entry { name: string, category: string }
function M.register_core_mapping(entry)
  local MapEntry = require('orgmode.config.mappings.map_entry')
  local core_mappings = require('orgmode.config.mappings')
  local core_defaults = require('orgmode.config.defaults')
  local core_config = require('orgmode.config')

  core_mappings[entry.category] = core_mappings[entry.category] or {}
  if not core_mappings[entry.category][entry.name] then
    core_mappings[entry.category][entry.name] = MapEntry:new(
      ('<cmd>lua require("org-columnview").%s()<CR>'):format(entry.name),
      { opts = { desc = 'org column view', help_desc = 'Show the column view' } }
    )
  end

  core_defaults.mappings[entry.category] = core_defaults.mappings[entry.category] or {}
  if not core_defaults.mappings[entry.category][entry.name] then
    core_defaults.mappings[entry.category][entry.name] = config.defaults.mappings[entry.name]
  end

  -- A mapping configured for the plugin wins over the default, but a mapping
  -- that is already configured in nvim-orgmode is left alone.
  local user_mappings = core_config.opts.mappings[entry.category]
  local plugin_mapping = config.get_mappings()[entry.name]
  if plugin_mapping and (not user_mappings or user_mappings[entry.name] == nil) then
    core_config.opts.mappings[entry.category] = user_mappings or {}
    core_config.opts.mappings[entry.category][entry.name] = plugin_mapping
  end
end

---Attach the global mappings that open the column view.
function M.setup_entry_points()
  local mappings = config.get_mappings()
  local defaults = config.defaults.mappings

  for _, entry in ipairs(M.entry_points) do
    M.register_core_mapping(entry)

    local keys = to_keys(mappings[entry.name] ~= nil and mappings[entry.name] or defaults[entry.name])
    if keys then
      for _, key in ipairs(keys) do
        vim.keymap.set('n', M.expand_prefix(key), function()
          if entry.name == 'org_columns' and is_agenda_buffer() then
            -- In the agenda the column view of the agenda is opened, like in
            -- Emacs, where the same key opens the view of the current buffer.
            return require('org-columnview').org_agenda_columns()
          end
          require('org-columnview')[entry.name]()
        end, { nowait = true, silent = true, desc = 'org column view' })
      end
    end
  end
end

return M
