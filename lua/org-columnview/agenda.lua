local config = require('orgmode.config')
local columnview_config = require('org-columnview.config')
local AgendaView = require('orgmode.agenda.view.init')
local AgendaLine = require('orgmode.agenda.view.line')
local AgendaLineToken = require('orgmode.agenda.view.token')
local AgendaFilter = require('orgmode.agenda.filter')
local Files = require('orgmode.files')
local Parser = require('org-columnview.parser')
local Cells = require('org-columnview.cells')
local SortingStrategy = require('orgmode.agenda.sorting_strategy')
local Promise = require('orgmode.utils.promise')
local utils = require('orgmode.utils')
local Input = require('orgmode.ui.input')
local link_utils = require('orgmode.org.links.utils')

---Extmarks marking the currently selected cell.
local ns = vim.api.nvim_create_namespace('orgmode_agenda_columns')

---Column view actions exposed in the agenda buffer. Only these keys are bound
---and torn down, so unrelated agenda mappings are left untouched.
local COLUMN_ACTIONS = {
  move_left = true,
  move_right = true,
  move_up = true,
  move_down = true,
  next_value = true,
  prev_value = true,
  select_value = true,
  view_value = true,
  edit_value = true,
  edit_allowed = true,
  toggle_or_quit = true,
  narrow_column = true,
  widen_column = true,
  insert_column = true,
  delete_column = true,
  move_column_left = true,
  move_column_right = true,
  edit_attributes = true,
  refresh = true,
  open_link = true,
  todo = true,
  show_help = true,
}

---Pre-existing buffer-local mappings overridden by the column view, keyed by
---buffer. Used to restore them (e.g. the agenda `g?` help mapping) on teardown.
local overridden_maps = {}

---@param bufnr number
---@param keys string[]
---@return table<string, table>
local function snapshot_keymaps(bufnr, keys)
  local snapshot = {}
  local existing = vim.api.nvim_buf_get_keymap(bufnr, 'n')
  for _, key in ipairs(keys) do
    for _, entry in ipairs(existing) do
      if entry.lhs == key then
        snapshot[key] = entry
        break
      end
    end
  end
  return snapshot
end

---@param bufnr number
---@param snapshot table<string, table>
local function restore_keymaps(bufnr, snapshot)
  for key, entry in pairs(snapshot) do
    local opts = {
      buffer = bufnr,
      noremap = entry.noremap == 1,
      silent = entry.silent == 1,
      expr = entry.expr == 1,
      nowait = entry.nowait == 1,
      replace_keycodes = entry.replace_keycodes == 1,
      desc = entry.desc,
    }
    pcall(vim.keymap.set, 'n', key, entry.callback or entry.rhs, opts)
  end
end

---@class OrgAgendaColumnsTypeOpts
---@field files OrgFiles
---@field highlighter OrgHighlighter
---@field agenda_filter OrgAgendaFilter
---@field filter? string
---@field tag_filter? string
---@field category_filter? string
---@field agenda_files string|string[]|nil
---@field header? string
---@field sorting_strategy? OrgAgendaSortingStrategy[]
---@field remove_tags? boolean
---@field id? string
---@field overriding_columns_format? string
---@field on_edit? fun(headline: OrgHeadline, setter: fun(headline: OrgHeadline))

---@class OrgAgendaColumnsType:OrgAgendaViewType
---@field files OrgFiles
---@field highlighter OrgHighlighter
---@field agenda_filter OrgAgendaFilter
---@field filter? OrgAgendaFilter
---@field tag_filter? OrgAgendaFilter
---@field category_filter? OrgAgendaFilter
---@field agenda_files string|string[]|nil
---@field header? string
---@field sorting_strategy? OrgAgendaSortingStrategy[]
---@field remove_tags? boolean
---@field id? string
---@field overriding_columns_format? string
---@field on_edit? fun(headline: OrgHeadline, setter: fun(headline: OrgHeadline))
---@field valid_filters OrgAgendaFilter[]
---@field cells OrgColumnCells
---@field columns OrgColumnSpec[]
---@field allowed_values table<string, string[]>
---@field headlines OrgHeadline[]
---@field _widths? number[]
---@field _base_format? string
---@field _columns_dirty? boolean
---@field current_row number
---@field current_col number
---@field bufnr? number
---@field view OrgAgendaView
local OrgAgendaColumnsType = {}
OrgAgendaColumnsType.__index = OrgAgendaColumnsType

---@param opts OrgAgendaColumnsTypeOpts
function OrgAgendaColumnsType:new(opts)
  local this = setmetatable({
    files = opts.files,
    highlighter = opts.highlighter,
    agenda_filter = opts.agenda_filter,
    filter = opts.filter and AgendaFilter:new():parse(opts.filter, true) or nil,
    tag_filter = opts.tag_filter and AgendaFilter:new({ types = { 'tags' } }):parse(opts.tag_filter, true) or nil,
    category_filter = opts.category_filter and AgendaFilter:new({ types = { 'categories' } })
      :parse(opts.category_filter, true) or nil,
    agenda_files = opts.agenda_files,
    header = opts.header,
    sorting_strategy = opts.sorting_strategy or vim.tbl_get(config.org_agenda_sorting_strategy, 'agenda') or {},
    id = opts.id,
    remove_tags = type(opts.remove_tags) == 'boolean' and opts.remove_tags or config.org_agenda_remove_tags,
    overriding_columns_format = opts.overriding_columns_format,
    on_edit = opts.on_edit,
    cells = Cells:new(),
    columns = {},
    allowed_values = {},
    headlines = {},
    _base_format = nil,
    _columns_dirty = false,
    current_row = 1,
    current_col = 1,
    bufnr = nil,
    view = nil,
  }, OrgAgendaColumnsType)
  this.valid_filters = vim.tbl_filter(function(filter)
    return filter and true or false
  end, {
    this.filter,
    this.tag_filter,
    this.category_filter,
    this.agenda_filter,
  })

  this:_setup_agenda_files()
  return this
end

function OrgAgendaColumnsType:prepare()
  return Promise.resolve(self)
end

---Collect the headlines and resolve the column format. Run on every render so
---that redo, filtering and clock updates reflect the current file state.
function OrgAgendaColumnsType:_setup()
  self:_collect_headlines()
  local format = self:_resolve_format()
  -- Preserve in-memory column edits (width, insert, delete, reorder) while the
  -- resolved format is unchanged. A new format (config or directive change)
  -- re-parses and discards the local edits.
  if format ~= self._base_format or not self._columns_dirty then
    self._base_format = format
    self._columns_dirty = false
    if format then
      local columns_def = Parser.parse(format)
      self.columns = columns_def and columns_def.columns or {}
      self.allowed_values = columns_def and columns_def.allowed_values or {}
    else
      self.columns = {}
      self.allowed_values = {}
    end
  end
  self:_resolve_allowed_values()
end

---Resolve property references in allowed values (e.g. `Owner_ALL`) into the
---actual values found on the collected headlines.
function OrgAgendaColumnsType:_resolve_allowed_values()
  local resolved = {}
  for key, vals in pairs(self.allowed_values) do
    if #vals == 1 and not vals[1]:match('^%[') then
      local prop_name = vals[1]:lower()
      local values = {}
      for _, headline in ipairs(self.headlines) do
        local prop_val = headline:get_property(prop_name)
        if not prop_val or prop_val == '' then
          -- Fall back to file-wide `#+PROPERTY: NAME_ALL ...` / `#+NAME_ALL: ...`
          prop_val = headline.file:get_keyword_property(prop_name)
        end
        if prop_val and prop_val ~= '' then
          values = Parser.split_allowed_values(prop_val)
          if #values > 0 then
            break
          end
        end
      end
      resolved[key] = #values > 0 and values or vals
    else
      resolved[key] = vals
    end
  end
  self.allowed_values = resolved
end

function OrgAgendaColumnsType:redo()
  if self.agenda_files then
    self.files:load_sync(true)
  end
end

function OrgAgendaColumnsType:_setup_agenda_files()
  if not self.agenda_files then
    return
  end
  self.files = Files:new({
    paths = self.agenda_files,
    cache = true,
  }):load_sync(true)
end

function OrgAgendaColumnsType:_get_header()
  if self.header then
    return self.header
  end
  return 'Column view:'
end

---Resolve the column format following the Emacs order:
---1. `org_agenda_overriding_columns_format` (custom command, then global)
---2. `org_columns_default_format_for_agenda`
---3. Format of the first agenda item (property, ancestor or file directive)
---4. `org_columns_default_format`
---@return string|nil
function OrgAgendaColumnsType:_resolve_format()
  local overriding = self.overriding_columns_format
  if not overriding or overriding == '' then
    overriding = columnview_config.overriding_columns_format
  end
  if overriding and overriding ~= '' then
    return overriding
  end

  local agenda_default = columnview_config.default_format_for_agenda
  if agenda_default and agenda_default ~= '' then
    return agenda_default
  end

  local first = self.headlines[1]
  if first then
    local format = Parser.get_columns_format_for_headline(first)
    if format then
      return format
    end
  end

  local default_format = columnview_config.default_format
  if default_format and default_format ~= '' then
    return default_format
  end

  return nil
end

function OrgAgendaColumnsType:_collect_headlines()
  self.headlines = {}
  for _, orgfile in ipairs(self.files:all()) do
    for i, headline in ipairs(orgfile:get_opened_headlines()) do
      if self:_matches_filters(headline) then
        headline.index = i
        table.insert(self.headlines, headline)
      end
    end
  end
  self:_sort(self.headlines)
end

---Cell value shown in the agenda view, honoring `org_agenda_remove_tags` by
---hiding the TAGS column when enabled.
---@param headline OrgHeadline
---@param column OrgColumnSpec
---@return string
function OrgAgendaColumnsType:_cell_value(headline, column)
  if self.remove_tags and column.name == 'TAGS' then
    return ''
  end
  return self.cells:get_value(headline, column)
end

---Value used for display, honoring
---`org_columns_modify_value_for_display_function`. Editing reads `_cell_value`
---so the stored value stays untouched.
---@param headline OrgHeadline
---@param column OrgColumnSpec
---@return string
function OrgAgendaColumnsType:_display_value(headline, column)
  return Cells.modify_value_for_display(column.title, self:_cell_value(headline, column))
end

---@param bufnr? number
function OrgAgendaColumnsType:render(bufnr)
  self.bufnr = bufnr or 0
  -- The agenda buffer is intentionally `nomodifiable`, but rendering writes the
  -- cell lines back. Temporarily unlock it so on-the-fly column edits (width,
  -- insert, delete, reorder) can re-render, then restore the previous state.
  local modifiable = vim.bo[self.bufnr].modifiable
  vim.bo[self.bufnr].modifiable = true
  local ok, result = pcall(self._render, self)
  if vim.api.nvim_buf_is_valid(self.bufnr) then
    vim.bo[self.bufnr].modifiable = modifiable
  end
  if not ok then
    error(result)
  end
  return result
end

function OrgAgendaColumnsType:_render()
  self:_setup()
  self.cells:clear_cache()
  local agendaView = AgendaView:new({ bufnr = self.bufnr, highlighter = self.highlighter })

  -- Custom view with no headlines: render empty block
  if self.id and config.org_agenda_hide_empty_blocks and #self.headlines == 0 then
    self.view = agendaView:render()
    return self.view
  end

  agendaView:add_line(AgendaLine:single_token({
    content = self:_get_header(),
    hl_group = '@org.agenda.header',
  }))

  local widths = Cells.compute_widths(self.columns, function(headline, col)
    return self:_display_value(headline, col)
  end, self.headlines)
  self._widths = widths

  agendaView:add_line(self:_build_header_row(widths))

  for _, headline in ipairs(self.headlines) do
    agendaView:add_line(self:_build_row(headline, widths))
  end

  if self:_has_summary_columns() then
    agendaView:add_line(self:_build_summary_row(widths))
  end

  self.view = agendaView:render()
  self:_setup_mappings()
  self:_highlight_current_cell()
  return self.view
end

---@param widths number[]
---@return OrgAgendaLine
function OrgAgendaColumnsType:_build_header_row(widths)
  local line = AgendaLine:new({ separator = '' })
  for col_idx, col in ipairs(self.columns) do
    line:add_token(AgendaLineToken:new({ content = '│', hl_group = '@org.column.border' }))
    line:add_token(AgendaLineToken:new({
      content = ' ' .. Cells.fit(col.title, widths[col_idx]) .. ' ',
      hl_group = '@org.column.header',
    }))
  end
  line:add_token(AgendaLineToken:new({ content = '│', hl_group = '@org.column.border' }))
  return line
end

---@param headline OrgHeadline
---@param widths number[]
---@return OrgAgendaLine
function OrgAgendaColumnsType:_build_row(headline, widths)
  local line = AgendaLine:new({
    headline = headline,
    separator = '',
    line_hl_group = headline:is_clocked_in() and 'Visual' or nil,
  })
  for col_idx, col in ipairs(self.columns) do
    line:add_token(AgendaLineToken:new({ content = '│', hl_group = '@org.column.border' }))
    local value = self:_display_value(headline, col)
    line:add_token(AgendaLineToken:new({
      content = ' ' .. Cells.fit(value, widths[col_idx]) .. ' ',
      hl_group = '@org.column.value',
    }))
  end
  line:add_token(AgendaLineToken:new({ content = '│', hl_group = '@org.column.border' }))
  return line
end

---@param widths number[]
---@return OrgAgendaLine
function OrgAgendaColumnsType:_build_summary_row(widths)
  local line = AgendaLine:new({ separator = '' })
  for col_idx, col in ipairs(self.columns) do
    line:add_token(AgendaLineToken:new({ content = '│', hl_group = '@org.column.border' }))
    local content = ''
    if col.summary_type then
      local values = {}
      for _, headline in ipairs(self.headlines) do
        table.insert(values, self:_cell_value(headline, col))
      end
      local summary = Cells.compute_summary(values, col.summary_type)
      if summary then
        content = summary
      end
    end
    line:add_token(AgendaLineToken:new({
      content = ' ' .. Cells.fit(content, widths[col_idx]) .. ' ',
      hl_group = '@org.column.summary',
    }))
  end
  line:add_token(AgendaLineToken:new({ content = '│', hl_group = '@org.column.border' }))
  return line
end

function OrgAgendaColumnsType:_has_summary_columns()
  for _, col in ipairs(self.columns) do
    if col.summary_type then
      return true
    end
  end
  return false
end

---@return OrgAgendaLine[]
function OrgAgendaColumnsType:get_lines()
  return self.view.lines
end

---@param row number
---@return OrgAgendaLine | nil
function OrgAgendaColumnsType:get_line(row)
  return utils.find(self.view.lines, function(line)
    return line.line_nr == row
  end)
end

---Rebuild a single row in place after an inline edit (e.g. TODO state change).
---@param agenda_line OrgAgendaLine
---@param headline OrgHeadline
function OrgAgendaColumnsType:rerender_agenda_line(agenda_line, headline)
  if not self._widths then
    return
  end
  local line = self:_build_row(headline, self._widths)
  self.view:replace_line(agenda_line, line)
end

-- ---------------------------------------------------------------------------
-- Cell navigation and editing
-- ---------------------------------------------------------------------------

---@return OrgAgendaLine[]
function OrgAgendaColumnsType:_data_lines()
  local lines = {}
  if self.view then
    for _, line in ipairs(self.view.lines) do
      if line.headline then
        table.insert(lines, line)
      end
    end
  end
  return lines
end

---Compute the buffer byte range (0-based, end exclusive) of a cell so it can be
---highlighted. Mirrors the layout used by `_build_row`: `│` + ` value ` per column.
---@param row number
---@param col number
---@return { line_nr: number, start_col: number, end_col: number }|nil
function OrgAgendaColumnsType:_cell_range(row, col)
  if not self.view or not self._widths or not self.bufnr then
    return nil
  end
  local line = self:_data_lines()[row]
  if not line then
    return nil
  end
  local buf_line = vim.api.nvim_buf_get_lines(self.bufnr, line.line_nr - 1, line.line_nr, false)[1]
  if not buf_line then
    return nil
  end

  local block_start = 1
  for i = 1, col - 1 do
    block_start = block_start + (self._widths[i] or 0) + 3
  end
  local last_vcol = block_start + 2 + (self._widths[col] or 0)
  local line_vcol = vim.fn.virtcol({ line.line_nr, '$' }) --[[@as number]]
  if block_start + 1 > line_vcol then
    return nil
  end

  local ok1, start_byte = pcall(vim.fn.virtcol2col, 0, line.line_nr, block_start + 1)
  if not ok1 or not start_byte or start_byte < 1 then
    return nil
  end

  local next_byte = #buf_line + 1
  if last_vcol < line_vcol then
    local ok2, b = pcall(vim.fn.virtcol2col, 0, line.line_nr, last_vcol + 1)
    if ok2 and b and b >= 1 then
      next_byte = b
    end
  end

  return { line_nr = line.line_nr, start_col = start_byte - 1, end_col = next_byte - 1 }
end

---Highlight the cell under `current_row`/`current_col` like the file column view.
function OrgAgendaColumnsType:_highlight_current_cell()
  if not self.bufnr or not vim.api.nvim_buf_is_valid(self.bufnr) or #self.columns == 0 then
    return
  end
  -- `virtcol`/`virtcol2col` operate on the current window, so only highlight
  -- while the column view buffer is actually displayed.
  if vim.fn.bufnr() ~= self.bufnr then
    return
  end
  vim.api.nvim_buf_clear_namespace(self.bufnr, ns, 0, -1)
  local range = self:_cell_range(self.current_row, self.current_col)
  if not range then
    return
  end
  pcall(vim.api.nvim_buf_set_extmark, self.bufnr, ns, range.line_nr - 1, range.start_col, {
    end_col = range.end_col,
    hl_group = '@org.column.current',
  })
end

---Remove the cell highlight extmarks (used when leaving the column view).
---@param bufnr number
function OrgAgendaColumnsType.clear_highlights(bufnr)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
end

---Update `current_row`/`current_col` from the cursor when it is on a data row.
function OrgAgendaColumnsType:_sync_cursor()
  if not self.view or not self._widths or #self.columns == 0 or not self.bufnr then
    return
  end
  if vim.fn.bufnr() ~= self.bufnr then
    return
  end
  local line_nr = vim.fn.line('.')
  local row
  for i, line in ipairs(self:_data_lines()) do
    if line.line_nr == line_nr then
      row = i
      break
    end
  end
  if not row then
    return
  end
  self.current_row = row

  local vcol = vim.fn.virtcol('.')
  local block_start = 1
  local col = #self.columns
  for i, w in ipairs(self._widths) do
    if vcol <= block_start + w + 2 then
      col = i
      break
    end
    block_start = block_start + w + 3
  end
  self.current_col = col
  self:_highlight_current_cell()
end

---Move the cursor to the cell at `row`/`col` (1-based).
function OrgAgendaColumnsType:_goto_cell(row, col)
  if not self.view or not self._widths or not self.bufnr then
    return
  end
  if vim.fn.bufnr() ~= self.bufnr then
    return
  end
  local line = self:_data_lines()[row]
  if not line then
    return
  end
  local block_start = 1
  for i = 1, col - 1 do
    block_start = block_start + (self._widths[i] or 0) + 3
  end
  local line_vcol = vim.fn.virtcol({ line.line_nr, '$' }) --[[@as number]]
  local vcol = math.min(block_start + 2, math.max(1, line_vcol))
  local ok, byte = pcall(vim.fn.virtcol2col, 0, line.line_nr, vcol)
  if not ok or not byte or byte < 1 then
    byte = 1
  end
  pcall(vim.api.nvim_win_set_cursor, 0, { line.line_nr, byte - 1 })
  self:_highlight_current_cell()
end

function OrgAgendaColumnsType:_current_headline()
  return self.headlines[self.current_row]
end

function OrgAgendaColumnsType:_current_column()
  return self.columns[self.current_col]
end

function OrgAgendaColumnsType:move_left()
  if self.current_col > 1 then
    self.current_col = self.current_col - 1
    self:_goto_cell(self.current_row, self.current_col)
  end
end

function OrgAgendaColumnsType:move_right()
  if self.current_col < #self.columns then
    self.current_col = self.current_col + 1
    self:_goto_cell(self.current_row, self.current_col)
  end
end

function OrgAgendaColumnsType:move_up()
  if self.current_row > 1 then
    self.current_row = self.current_row - 1
    self:_goto_cell(self.current_row, self.current_col)
  end
end

function OrgAgendaColumnsType:move_down()
  if self.current_row < #self.headlines then
    self.current_row = self.current_row + 1
    self:_goto_cell(self.current_row, self.current_col)
  end
end

---Candidate values for a column, used by numbered selection and cycling.
---@param col OrgColumnSpec
---@return string[]|nil
function OrgAgendaColumnsType:_allowed_values_for(col)
  if col.name == 'TODO' then
    local values = {}
    for _, todo in ipairs(config:get_todo_keywords():all()) do
      table.insert(values, todo.value)
    end
    return values
  elseif col.name == 'PRIORITY' then
    local range = config:get_priority_range()
    local PriorityState = require('orgmode.objects.priority_state')
    local values = {}
    local current = PriorityState:new(range.highest, range)
    table.insert(values, current.priority)
    while current.priority ~= range.lowest do
      current:decrease()
      table.insert(values, current.priority)
    end
    return values
  end

  local allowed = self.allowed_values[col.name .. '_ALL']
  if allowed and #allowed > 0 then
    return allowed
  end
  if col.name:upper() == 'ITEM' then
    return nil
  end
  return { '[ ]', '[X]' }
end

---Apply a new value to a cell, writing it through the agenda when available.
---@param headline OrgHeadline
---@param col OrgColumnSpec
---@param value string
function OrgAgendaColumnsType:_apply_value(headline, col, value)
  local setter = function(h)
    if col.is_special then
      if col.name == 'TODO' then
        h:set_todo(value)
      elseif col.name == 'PRIORITY' then
        h:set_priority(value:match('%[#(.-)%]') or value)
      elseif col.name == 'TAGS' then
        h:set_tags(value)
      end
    else
      h:set_property(col.name:lower(), value)
    end
  end

  if self.on_edit then
    self.on_edit(headline, setter)
  else
    setter(headline)
    self:_refresh_row(headline)
  end
end

function OrgAgendaColumnsType:_refresh_row(headline)
  if not self.view then
    return
  end
  for _, line in ipairs(self.view.lines) do
    if line.headline == headline then
      self:rerender_agenda_line(line, headline)
      return
    end
  end
end

function OrgAgendaColumnsType:select_value(n)
  if n == 0 then
    n = 10
  end
  local headline = self:_current_headline()
  local col = self:_current_column()
  if not headline or not col then
    return
  end
  local allowed = self:_allowed_values_for(col)
  if not allowed then
    return
  end
  if n <= #allowed then
    self:_apply_value(headline, col, allowed[n])
  end
end

function OrgAgendaColumnsType:next_value()
  self:_change_value(1)
end

function OrgAgendaColumnsType:prev_value()
  self:_change_value(-1)
end

function OrgAgendaColumnsType:_change_value(direction)
  local headline = self:_current_headline()
  local col = self:_current_column()
  if not headline or not col then
    return
  end

  if col.name == 'TODO' then
    local TodoState = require('orgmode.objects.todo_state')
    local ts = TodoState:new({ current_state = headline:get_todo() })
    local next_state = direction > 0 and ts:get_next() or ts:get_prev()
    if next_state then
      self:_apply_value(headline, col, next_state.value)
    end
    return
  elseif col.name == 'PRIORITY' then
    local PriorityState = require('orgmode.objects.priority_state')
    local ps = PriorityState:new(headline:get_priority(), config:get_priority_range())
    local value = direction > 0 and ps:increase() or ps:decrease()
    self:_apply_value(headline, col, value)
    return
  end

  local allowed = self:_allowed_values_for(col)
  if not allowed or #allowed == 0 then
    return
  end
  local current = self:_cell_value(headline, col)
  local idx = 1
  for i, v in ipairs(allowed) do
    if v == current then
      idx = i
      break
    end
  end
  idx = idx + direction
  if idx < 1 then
    idx = #allowed
  end
  if idx > #allowed then
    idx = 1
  end
  self:_apply_value(headline, col, allowed[idx])
end

function OrgAgendaColumnsType:view_value()
  local headline = self:_current_headline()
  local col = self:_current_column()
  if not headline or not col then
    return
  end
  utils.echo_info(self:_cell_value(headline, col), nil, true)
end

---@private
function OrgAgendaColumnsType:_get_links()
  if not self._links then
    self._links = require('orgmode.org.links'):new({ files = self.files })
  end
  return self._links
end

---Follow the first link found in the current cell, like Emacs'
---`org-columns-open-link` (`C-c C-o`).
function OrgAgendaColumnsType:open_link()
  local headline = self:_current_headline()
  local col = self:_current_column()
  if not headline or not col then
    return
  end
  local url = link_utils.extract_link(self:_cell_value(headline, col))
  if not url then
    return utils.echo_warning('No link at point')
  end
  self:_get_links():follow(url)
end

---Change the TODO state of the current row, like Emacs' `org-columns-todo`
---(`C-c C-t`). Acts on the entry independent of the column under the cursor,
---prompting with fast access when configured and cycling otherwise.
function OrgAgendaColumnsType:todo()
  local headline = self:_current_headline()
  if not headline then
    return
  end
  local TodoState = require('orgmode.objects.todo_state')
  local next_state = TodoState.next_or_fast_access(headline.file:get_todo_keywords(), headline:get_todo())
  if next_state then
    self:_apply_value(headline, { name = 'TODO', is_special = true }, next_state.value)
  end
end

function OrgAgendaColumnsType:toggle_or_quit()
  local headline = self:_current_headline()
  local col = self:_current_column()
  if not headline or not col or col.is_special then
    return
  end
  local value = self:_cell_value(headline, col)
  if not value:match('^%s*%[.%]') then
    return
  end
  local new_val = value:gsub('%[(.)%]', function(inner)
    return inner:upper() == 'X' and '[ ]' or '[X]'
  end, 1)
  self:_apply_value(headline, col, new_val)
end

function OrgAgendaColumnsType:edit_value()
  local headline = self:_current_headline()
  local col = self:_current_column()
  if not headline or not col then
    return
  end

  if col.name == 'TODO' then
    local TodoState = require('orgmode.objects.todo_state')
    local ts = TodoState:new({ current_state = headline:get_todo() })
    local next_state = ts:open_fast_access()
    if next_state then
      self:_apply_value(headline, col, next_state.value)
    end
    return
  elseif col.name == 'PRIORITY' then
    local PriorityState = require('orgmode.objects.priority_state')
    local ps = PriorityState:new(headline:get_priority(), config:get_priority_range())
    local new_prio = ps:prompt_user()
    if new_prio then
      self:_apply_value(headline, col, new_prio)
    end
    return
  elseif col.name == 'TAGS' then
    local current_tags = utils.tags_to_string(headline:get_own_tags())
    return Input.open('Tags: ', current_tags, function(arg_lead)
      return utils.prompt_autocomplete(arg_lead, self.files:get_tags())
    end):next(function(tags)
      if tags then
        self:_apply_value(headline, col, tags)
      end
      return tags
    end)
  end

  local current_val = self:_cell_value(headline, col)
  local allowed = self.allowed_values[col.name .. '_ALL']
  if allowed and #allowed > 0 then
    local items = vim.deepcopy(allowed)
    table.insert(items, 1, '')
    vim.ui.select(items, {
      prompt = ('Select %s: '):format(col.title or col.name),
      format_item = function(item)
        return item == '' and '(clear)' or item
      end,
    }, function(choice)
      if choice then
        self:_apply_value(headline, col, choice)
      end
    end)
    return
  end

  local input = vim.fn.input(('Edit %s: '):format(col.title or col.name), current_val)
  if input and vim.trim(input) ~= '' then
    self:_apply_value(headline, col, input)
  end
end

---Edit the allowed values of the current column (`a`). Mirrors the file column
---view: the list is stored on the entry that already defines it, otherwise on
---the first entry of the view.
function OrgAgendaColumnsType:edit_allowed()
  local headline = self:_current_headline()
  local col = self:_current_column()
  if not headline or not col then
    return
  end
  if col.is_special then
    -- TODO, PRIORITY, TAGS, ... derive their values from configuration or the
    -- files, not from a `<NAME>_ALL` property (Org itself does not support this).
    utils.echo_info(("Cannot edit allowed values for the special '%s' column"):format(col.name))
    return
  end

  local prop_name = col.name .. '_ALL'
  local prop_key = prop_name:lower()

  local target = self.headlines[1] or headline
  ---@type OrgHeadline|nil
  local current = headline
  while current do
    local own = current:get_own_properties()
    if own and own[prop_key] then
      target = current
      break
    end
    current = current:get_parent_headline() --[[@as OrgHeadline|nil]]
  end

  local current_allowed = vim.deepcopy(self.allowed_values[prop_name] or {})
  if #current_allowed == 0 then
    local seen = {}
    for _, h in ipairs(self.headlines) do
      local val = self:_cell_value(h, col)
      if val and val ~= '' and not seen[val] then
        seen[val] = true
        table.insert(current_allowed, val)
      end
    end
  end

  local input = vim.fn.input('Allowed values (comma separated): ', table.concat(current_allowed, ','))
  if not input or vim.trim(input) == '' then
    return
  end

  local new_allowed = vim.split(input, ',', { trimempty = true })
  for i, v in ipairs(new_allowed) do
    new_allowed[i] = vim.trim(v)
  end

  self:_apply_value(target, { name = prop_name, is_special = false }, table.concat(new_allowed, ','))
  utils.echo_info(('Allowed values for %s: %s'):format(col.name, table.concat(new_allowed, ', ')))
end

function OrgAgendaColumnsType:narrow_column()
  local col = self:_current_column()
  if not col then
    return
  end
  local width = col.width or (self._widths and self._widths[self.current_col]) or 10
  if width > 5 then
    col.width = width - 1
    self._columns_dirty = true
    self._widths = nil
    self:render(self.bufnr)
  end
end

function OrgAgendaColumnsType:widen_column()
  local col = self:_current_column()
  if not col then
    return
  end
  local width = col.width or (self._widths and self._widths[self.current_col]) or 10
  col.width = math.min(width + 1, 50)
  self._columns_dirty = true
  self._widths = nil
  self:render(self.bufnr)
end

function OrgAgendaColumnsType:insert_column()
  local name = vim.fn.input('Column name: ')
  if not name or vim.trim(name) == '' then
    return
  end

  local width = tonumber(vim.fn.input('Width (optional): '))

  local new_col = {
    name = name:upper(),
    width = width,
    title = name,
    summary_type = nil,
    is_special = false,
  }

  table.insert(self.columns, self.current_col, new_col)
  self._columns_dirty = true
  self._widths = nil
  self:render(self.bufnr)
end

function OrgAgendaColumnsType:delete_column()
  if #self.columns <= 1 then
    return
  end
  table.remove(self.columns, self.current_col)
  if self.current_col > #self.columns then
    self.current_col = #self.columns
  end
  self._columns_dirty = true
  self._widths = nil
  self:render(self.bufnr)
end

function OrgAgendaColumnsType:move_column_left()
  if self.current_col > 1 then
    local col = table.remove(self.columns, self.current_col)
    table.insert(self.columns, self.current_col - 1, col)
    self.current_col = self.current_col - 1
    self._columns_dirty = true
    self._widths = nil
    self:render(self.bufnr)
  end
end

function OrgAgendaColumnsType:move_column_right()
  if self.current_col < #self.columns then
    local col = table.remove(self.columns, self.current_col)
    table.insert(self.columns, self.current_col + 1, col)
    self.current_col = self.current_col + 1
    self._columns_dirty = true
    self._widths = nil
    self:render(self.bufnr)
  end
end

---Edit the property, title, width and summary type of the current column.
function OrgAgendaColumnsType:edit_attributes()
  local col = self:_current_column()
  if not col then
    return
  end

  local name = vim.fn.input('Column name: ', col.name)
  if not name or vim.trim(name) == '' then
    return
  end
  name = vim.trim(name):upper()

  local title = vim.trim(vim.fn.input('Column title: ', col.title or '') or '')
  local width_input = vim.fn.input('Width (optional): ', col.width and tostring(col.width) or '') or ''
  local summary = vim.trim(vim.fn.input('Summary type (optional): ', col.summary_type or '') or '')

  col.name = name
  col.title = title ~= '' and title or name
  col.width = tonumber(width_input)
  col.summary_type = summary ~= '' and summary or nil
  col.is_special = Parser.is_special_column(name)

  self._columns_dirty = true
  self._widths = nil
  self:render(self.bufnr)
end

---Recompute the column display from the current file state.
function OrgAgendaColumnsType:refresh()
  self.cells:clear_cache()
  self._widths = nil
  self:render(self.bufnr)
end

function OrgAgendaColumnsType:show_help()
  require('org-columnview').show_help()
end

-- ---------------------------------------------------------------------------
-- Mappings
-- ---------------------------------------------------------------------------

function OrgAgendaColumnsType:_setup_mappings()
  if not self.bufnr then
    return
  end
  local maps = require('org-columnview.mappings').get_view_mappings()
  if not overridden_maps[self.bufnr] then
    local keys = {}
    for name, map in pairs(maps) do
      if COLUMN_ACTIONS[name] then
        vim.list_extend(keys, map.keys)
      end
    end
    overridden_maps[self.bufnr] = snapshot_keymaps(self.bufnr, keys)
  end
  for name, map in pairs(maps) do
    if COLUMN_ACTIONS[name] then
      if name == 'select_value' then
        self:_setup_select_value_mapping(map)
      else
        for _, key in ipairs(map.keys) do
          vim.keymap.set('n', key, function()
            if not self.view or not self.view:is_in_range() then
              return
            end
            self:_sync_cursor()
            return self[name](self)
          end, {
            buffer = self.bufnr,
            nowait = true,
            silent = true,
            desc = map.desc,
          })
        end
      end
    end
  end
end

---@param map table
function OrgAgendaColumnsType:_setup_select_value_mapping(map)
  for idx, key in ipairs(map.keys) do
    vim.keymap.set('n', key, function()
      if not self.view or not self.view:is_in_range() then
        return
      end
      self:_sync_cursor()
      self:select_value(idx)
    end, {
      buffer = self.bufnr,
      nowait = true,
      silent = true,
      desc = map.desc,
    })
  end
end

---Remove the column view mappings from `bufnr` without touching other maps.
---@param bufnr number
function OrgAgendaColumnsType.clear_mappings(bufnr)
  local maps = require('org-columnview.mappings').get_view_mappings()
  local keys = {}
  for name, map in pairs(maps) do
    if COLUMN_ACTIONS[name] then
      vim.list_extend(keys, map.keys)
    end
  end
  for _, key in ipairs(keys) do
    pcall(vim.keymap.del, 'n', key, { buffer = bufnr })
  end
  local snapshot = overridden_maps[bufnr]
  overridden_maps[bufnr] = nil
  if snapshot then
    restore_keymaps(bufnr, snapshot)
  end
end

function OrgAgendaColumnsType:_matches_filters(headline)
  for _, filter in ipairs(self.valid_filters) do
    if filter and not filter:matches(headline) then
      return false
    end
  end
  return true
end

---@private
---@param headlines OrgHeadline[]
function OrgAgendaColumnsType:_sort(headlines)
  local make_entry = function(headline)
    return {
      headline = headline,
      index = headline.index,
      is_day_match = false,
    }
  end
  return SortingStrategy.sort(headlines, self.sorting_strategy, make_entry)
end

return OrgAgendaColumnsType
