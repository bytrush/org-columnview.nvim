---Org column view for Neovim.
---
---A port of the Emacs Org column view (`org-colview.el`). It overlays a
---spreadsheet like table of properties on the headlines of an org buffer and
---renders the agenda as a table of columns.
---
---Requires [nvim-orgmode](https://github.com/nvim-orgmode/orgmode) for the org
---file, headline and agenda handling.
local ColumnView = require('org-columnview.view')
local Parser = require('org-columnview.parser')
local config = require('org-columnview.config')
local mappings = require('org-columnview.mappings')

local M = {}

---The column view that is currently open, if any.
---@type OrgColumnView|nil
M.column_view = nil

---@return OrgFiles
local function get_files()
  return require('orgmode').files
end

---@return OrgLinks
local function get_links()
  return require('orgmode').links
end

---Open the column view for the current buffer, or close it when it is already
---open.
---@return OrgColumnView|nil
function M.org_columns()
  if M.column_view then
    M.org_columns_quit()
    return nil
  end

  local files = get_files()
  local headline = files:get_closest_headline_or_nil()
  local headlines, columns_def

  if headline then
    columns_def = Parser.get_columns_for_headline(headline)
    headlines = { headline }
    if headline:has_child_headlines() then
      vim.list_extend(headlines, headline:get_child_headlines())
    end
  else
    -- Point is before the first headline: show the whole file.
    local file = files:get_current_file()
    if not file then
      return require('orgmode.utils').echo_warning('No column view definition found')
    end
    columns_def = Parser.get_columns_for_file(file)
    headlines = file:get_top_level_headlines()
  end

  if not columns_def or #columns_def.columns == 0 then
    return require('orgmode.utils').echo_warning('No column view definition found')
  end

  local view = ColumnView:new({
    files = files,
    links = get_links(),
    headlines = headlines,
    subtree = headline ~= nil,
    columns_def = columns_def,
    bufnr = files:get_current_file() and files:get_current_file():bufnr() or 0,
  })

  M.column_view = view
  view:open()

  -- Refresh on buffer write
  local augroup = vim.api.nvim_create_augroup('orgmode_column_view', { clear = true })
  local autocmd_id = vim.api.nvim_create_autocmd('BufWritePost', {
    group = augroup,
    buffer = view.bufnr,
    callback = function()
      if M.column_view == view and view.rows then
        view:refresh()
      end
    end,
  })

  view._autocmd_id = autocmd_id

  return view
end

---Close the column view.
function M.org_columns_quit()
  local view = M.column_view
  if not view then
    return
  end
  if view._autocmd_id then
    pcall(vim.api.nvim_del_autocmd, view._autocmd_id)
    view._autocmd_id = nil
  end
  view:quit()
  M.column_view = nil
end

---Open the agenda as a column view.
function M.org_agenda_columns()
  require('orgmode').action('agenda.columns')
end

---Register the agenda view type, so that the agenda can be rendered as a
---column view.
local function register_agenda_type()
  local types = require('orgmode.agenda.types')
  types.columns = require('org-columnview.agenda')
end

---Register the completion source that suggests the allowed values of a
---property. The orgmode instance is recreated on every `orgmode.setup()` call,
---so the source has to be registered again for the new instance.
local function register_completion_source()
  local completion = require('orgmode').completion
  local source = require('org-columnview.completion'):new({ completion = completion })
  local ok, err = pcall(completion.add_source, completion, source)
  if not ok and not tostring(err):find('already exists', 1, true) then
    error(err)
  end
end

---Show the help of the column view.
function M.show_help()
  local lines = { ' **Orgmode column view**', '' }
  local keys = config.get_mappings().column_view or config.defaults.mappings.column_view
  local prefix = config.get_prefix()
  for _, name in ipairs(vim.tbl_keys(config.defaults.mappings.column_view)) do
    local mapping = keys[name] ~= nil and keys[name] or config.defaults.mappings.column_view[name]
    if type(mapping) == 'table' then
      mapping = table.concat(mapping, ', ')
    end
    if type(mapping) == 'string' then
      table.insert(lines, ('  `%-12s` - %s'):format((mapping:gsub('<prefix>', prefix)), mappings.descriptions[name]))
    end
  end
  table.insert(lines, '')
  table.insert(lines, '  `q` - Close this help')

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = math.min(80, vim.o.columns),
    height = math.min(#lines + 1, vim.o.lines - 4),
    row = math.floor((vim.o.lines - math.min(#lines + 1, vim.o.lines - 4)) / 2),
    col = math.floor((vim.o.columns - math.min(80, vim.o.columns)) / 2),
    style = 'minimal',
    border = 'rounded',
  })
  vim.keymap.set('n', 'q', '<Cmd>close<CR>', { buffer = buf, nowait = true, silent = true })
  vim.keymap.set('n', '<Esc>', '<Cmd>close<CR>', { buffer = buf, nowait = true, silent = true })
  vim.bo[buf].filetype = 'orghelp'
  vim.wo[win].wrap = false
end

---Setup the plugin.
---@param opts? OrgColumnViewConfigOpts
function M.setup(opts)
  config.setup(opts)
  register_agenda_type()
  register_completion_source()
  mappings.setup_entry_points()
  return M
end

return M
