local utils = require('orgmode.utils')
local config = require('orgmode.config')
local Summary = require('org-columnview.summary')
local Cells = require('org-columnview.cells')
local Parser = require('org-columnview.parser')
local Input = require('orgmode.ui.input')
local Headline = require('orgmode.files.headline')
local compat = require('org-columnview.compat')

local ColumnView = {}
ColumnView.__index = ColumnView

---@param opts OrgColumnViewOpts
---@return OrgColumnView
function ColumnView:new(opts)
  local ns = vim.api.nvim_create_namespace('orgmode_column_view')
  local track_ns = vim.api.nvim_create_namespace('orgmode_column_view_track')
  local data = {
    files = opts.files,
    links = opts.links,
    headlines = opts.headlines or {},
    file = opts.headlines and opts.headlines[1] and opts.headlines[1].file or nil,
    subtree = opts.subtree or false,
    columns = opts.columns_def.columns or {},
    allowed_values = opts.columns_def.allowed_values or {},
    rows = {},
    bufnr = opts.bufnr or 0,
    winid = opts.winid or 0,
    ns = ns,
    track_ns = track_ns,
    cells = Cells:new(),
    current_row = 1,
    current_col = 1,
    original_winid = vim.api.nvim_get_current_win(),
    original_bufnr = vim.api.nvim_get_current_buf(),
    _headline_to_row = {},
    _widths = nil,
    on_quit = opts.on_quit,
  }
  local this = setmetatable(data, ColumnView)
  this:_build_rows()
  this:_resolve_allowed_values()
  this:_track_view_root()
  return this
end

---Place an extmark at the first line of the viewed subtree so that the view
---root can be recovered after the buffer is reordered by move-row. It follows
---the moved text, which keeps the column view anchored to the same subtree.
---@private
function ColumnView:_track_view_root()
  if not self.subtree or #self.headlines == 0 then
    return
  end
  if not vim.api.nvim_buf_is_valid(self.bufnr) then
    return
  end
  local line = self.headlines[1]:get_range().start_line - 1
  self._root_extmark_id = vim.api.nvim_buf_set_extmark(self.bufnr, self.track_ns, line, 0, {})
end

---@private
function ColumnView:_resolve_allowed_values()
  -- Resolve property references in allowed_values to actual values
  -- e.g., { "Owner_ALL" } -> { "Alice", "Bob", "Carol" }
  local resolved = {}
  for key, vals in pairs(self.allowed_values) do
    if #vals == 1 and not vals[1]:match('^%[') then
      -- This looks like a property reference (e.g., "Owner_ALL")
      local prop_name = vals[1]:lower()
      local values = {}
      for _, hl in ipairs(self.headlines) do
        local prop_val = hl:get_property(prop_name)
        if not prop_val or prop_val == '' then
          -- Fall back to file-wide `#+PROPERTY: NAME_ALL ...` / `#+NAME_ALL: ...`
          prop_val = compat.get_keyword_property(hl.file, prop_name)
        end
        if prop_val and prop_val ~= '' then
          values = Parser.split_allowed_values(prop_val)
          if #values > 0 then
            break
          end
        end
      end
      if #values > 0 then
        resolved[key] = values
      else
        resolved[key] = vals -- fallback to original
      end
    else
      resolved[key] = vals
    end
  end
  self.allowed_values = resolved
end

function ColumnView:_build_rows()
  self.rows = {}
  self._headline_to_row = {}
  self.cells:clear_cache()
  self._widths = nil
  local visited = {}

  local function add_headlines(headlines, level)
    for _, hl in ipairs(headlines) do
      local hl_key = hl.file.filename .. ':' .. hl:get_range().start_line
      if not visited[hl_key] then
        visited[hl_key] = true

        local row = self:_create_row(hl, level)
        table.insert(self.rows, row)
        self._headline_to_row[hl] = #self.rows

        local children = hl:get_child_headlines()
        if #children > 0 then
          add_headlines(children, level + 1)
        end
      end
    end
  end

  add_headlines(self.headlines, 1)
end

---@param headline OrgHeadline
---@param level number
---@return OrgColumnViewRow
function ColumnView:_create_row(headline, level)
  local cells = {}
  for _, col in ipairs(self.columns) do
    local value = self:_get_cell_value(headline, col)
    local summary = nil
    if col.summary_type and headline:has_child_headlines() then
      -- Aggregate the children's rendered values so that special columns
      -- (AGE, CLOCKSUM, ...) are summarized just like property columns.
      local values = {}
      for _, child in ipairs(headline:get_child_headlines()) do
        table.insert(values, self:_get_cell_value(child, col))
      end
      summary = Summary.compute(values, col.summary_type)
    end
    table.insert(cells, {
      headline = headline,
      column = col,
      value = value,
      summary = summary,
      -- A value is computed when the column has a summary operator and the
      -- entry has children to aggregate, mirroring Emacs'
      -- `org-columns-check-computed`.
      is_computed = col.summary_type ~= nil and headline:has_child_headlines(),
    })
  end

  return {
    headline = headline,
    cells = cells,
    level = level,
    is_parent = headline:has_child_headlines(),
  }
end

---@param headline OrgHeadline
---@param column OrgColumnSpec
---@return string
function ColumnView:_get_cell_value(headline, column)
  return self.cells:get_value(headline, column)
end

---Run `fn` with the underlying buffer temporarily writable, restoring the
---locked state afterwards. While the column view is open, edits performed
---through the view are the only intended way to modify the buffer.
---@param fn fun()
---@return any
function ColumnView:_write(fn)
  if not self._opened or not self._original_modifiable or not vim.api.nvim_buf_is_valid(self.bufnr) then
    return fn()
  end
  vim.bo[self.bufnr].modifiable = true
  local ok, result = pcall(fn)
  if vim.api.nvim_buf_is_valid(self.bufnr) then
    vim.bo[self.bufnr].modifiable = false
  end
  if not ok then
    error(result)
  end
  return result
end

function ColumnView:open()
  self.bufnr = vim.api.nvim_get_current_buf()
  self.winid = vim.api.nvim_get_current_win()

  self._original_winbar = vim.wo[self.winid].winbar
  self._opened = true
  -- Lock the buffer so the column view is the only way to change it; typing
  -- directly would desync the rendered cells from the underlying text.
  self._original_modifiable = vim.bo[self.bufnr].modifiable
  vim.bo[self.bufnr].modifiable = false
  vim.wo[self.winid].cursorline = true
  self:_setup_mappings()
  self:_render()

  self._leave_autocmd_id = vim.api.nvim_create_autocmd({ 'WinLeave', 'BufLeave' }, {
    buffer = self.bufnr,
    callback = function()
      vim.schedule(function()
        -- Do not quit when a transient floating window (help popup, menu,
        -- completion, etc.) takes focus; keep the column view alive underneath.
        if vim.api.nvim_win_is_valid(self.winid) then
          local win_config = vim.api.nvim_win_get_config(vim.api.nvim_get_current_win())
          if win_config.relative ~= '' then
            return
          end
        end
        self:quit()
      end)
    end,
  })
end

function ColumnView:_setup_mappings()
  require('org-columnview.mappings').setup_view_mappings(self, self.bufnr)
end

---The text a cell displays: its value, plus the computed summary when present.
---@param cell OrgColumnViewCell
---@return string
function ColumnView:_cell_content(cell)
  local value = Cells.modify_value_for_display(cell.column.title, cell.value)
  if not cell.summary then
    return value
  end
  local summary_text = 'Σ=' .. cell.summary
  if value == '' then
    return summary_text
  end
  return value .. ' ' .. summary_text
end

---Compute the display width of every column, fitting both the header title and
---the rendered cell contents. Computed once and reused by the header and all
---rows so that the table stays aligned.
---@return number[]
function ColumnView:_compute_widths()
  local widths = {}
  for col_idx, col in ipairs(self.columns) do
    local width
    if col.width then
      width = col.width
    else
      width = math.max(vim.api.nvim_strwidth(col.title), 10)
      for _, row in ipairs(self.rows) do
        local cell = row.cells[col_idx]
        if cell then
          width = math.max(width, vim.api.nvim_strwidth(self:_cell_content(cell)))
        end
      end
    end
    widths[col_idx] = math.min(width, 50)
  end
  return widths
end

---@param col_idx number
---@return number
function ColumnView:_get_width(col_idx)
  if not self._widths then
    self._widths = self:_compute_widths()
  end
  return self._widths[col_idx]
end

function ColumnView:_render()
  vim.api.nvim_buf_clear_namespace(self.bufnr, self.ns, 0, -1)

  -- Render the header in the window bar so it stays visible while scrolling.
  if self._opened and self.winid and vim.api.nvim_win_is_valid(self.winid) then
    vim.wo[self.winid].winbar = self:_build_winbar()
  end

  for row_idx, row in ipairs(self.rows) do
    local line_nr = row.headline:get_range().start_line
    local virt_text = self:_build_virt_text(row, row_idx)
    if #virt_text > 0 then
      vim.api.nvim_buf_set_extmark(self.bufnr, self.ns, line_nr - 1, 0, {
        virt_text = virt_text,
        virt_text_pos = 'overlay',
        priority = 10000,
      })
    end
  end

  self:_highlight_current_cell()
end

---@return table[]
function ColumnView:_build_header_virt_text()
  local parts = {}

  for col_idx, col in ipairs(self.columns) do
    local content = Cells.fit(col.title, self:_get_width(col_idx))

    table.insert(parts, { '│', '@org.column.border' })
    table.insert(parts, { ' ' .. content .. ' ', '@org.column.header' })
  end

  table.insert(parts, { '│', '@org.column.border' })

  return parts
end

---Build the window bar string for the header, keeping it always visible while
---the buffer scrolls. Uses the same parts as the buffer header so the columns
---stay aligned.
---@return string
function ColumnView:_build_winbar()
  local chunks = {}
  for _, part in ipairs(self:_build_header_virt_text()) do
    local text = part[1]:gsub('%%', '%%%%')
    if part[2] then
      text = '%#' .. part[2] .. '#' .. text
    end
    table.insert(chunks, text)
  end
  return table.concat(chunks)
end

---@param row OrgColumnViewRow
---@param row_idx number
---@return table[]
function ColumnView:_build_virt_text(row, row_idx)
  local parts = {}
  local is_current_row = row_idx == self.current_row

  for col_idx, cell in ipairs(row.cells) do
    local is_current_col = col_idx == self.current_col
    local content = Cells.fit(self:_cell_content(cell), self:_get_width(col_idx))

    local is_current_cell = is_current_row and is_current_col
    local hl_group = cell.summary and '@org.column.summary' or '@org.column.value'
    if is_current_cell then
      hl_group = '@org.column.current'
    end

    table.insert(parts, { '│', '@org.column.border' })
    table.insert(parts, { ' ' .. content .. ' ', hl_group })
  end

  table.insert(parts, { '│', '@org.column.border' })

  return parts
end

function ColumnView:_highlight_current_cell()
  -- Current cell highlighting is handled in _build_virt_text
end

function ColumnView:move_left()
  if self.current_col > 1 then
    self.current_col = self.current_col - 1
    self:_render()
  end
end

function ColumnView:move_right()
  if self.current_col < #self.columns then
    self.current_col = self.current_col + 1
    self:_render()
  end
end

---Whether the row's headline line is currently visible. A line is visible when
---it is not in a closed fold, or when it is the first (displayed) line of one.
---@param row OrgColumnViewRow
---@return boolean
function ColumnView:_is_row_visible(row)
  local line = row.headline:get_range().start_line
  local closed = vim.fn.foldclosed(line)
  return closed == -1 or closed == line
end

function ColumnView:move_up()
  local idx = self.current_row
  while idx > 1 do
    idx = idx - 1
    if self:_is_row_visible(self.rows[idx]) then
      self.current_row = idx
      local line = self.rows[idx].headline:get_range().start_line
      vim.api.nvim_win_set_cursor(self.winid, { line, 0 })
      self:_render()
      return
    end
  end
end

function ColumnView:move_down()
  local idx = self.current_row
  while idx < #self.rows do
    idx = idx + 1
    if self:_is_row_visible(self.rows[idx]) then
      self.current_row = idx
      local line = self.rows[idx].headline:get_range().start_line
      vim.api.nvim_win_set_cursor(self.winid, { line, 0 })
      self:_render()
      return
    end
  end
end

---Re-derive the viewed headlines from the (possibly reordered) buffer. The
---subtree root is recovered from its tracking extmark; a whole-file view uses
---the file's top level headlines.
---@private
function ColumnView:_reload_headlines()
  if not self.file then
    return
  end
  self.file:parse()
  if self.subtree and self._root_extmark_id then
    local mark = vim.api.nvim_buf_get_extmark_by_id(self.bufnr, self.track_ns, self._root_extmark_id, {})
    if mark and mark[1] then
      local node = self.file:closest_headline_node({ mark[1] + 1, mark[2] })
      if node then
        self.headlines = { Headline:new(node, self.file) }
        return
      end
    end
  end
  self.headlines = self.file:get_top_level_headlines()
end

---Persist the current column format to the buffer, mirroring Emacs'
---`org-columns-store-format`. A subtree view updates the start headline's
---`:COLUMNS:` property when it already has one; otherwise the file's
---`#+COLUMNS:` keyword is created or updated.
---@private
function ColumnView:_store_format()
  if not self.file then
    return
  end
  local format = Parser.unparse(self.columns)
  self:_write(function()
    if self.subtree and self.headlines[1] and self.headlines[1]:get_property('COLUMNS', false) then
      self.headlines[1]:set_property('COLUMNS', format)
      return
    end
    compat.set_file_columns(self.file, format)
  end)
end

---Persist the edited column format and rebuild the view from the updated
---buffer, since editing the format can move the headline lines.
---@private
function ColumnView:_after_columns_changed()
  self:_store_format()
  self:_reload_headlines()
  self:_rebuild_rows()
  self:_render()
end

---Move the current row's subtree up or down among its siblings, like Emacs'
---`org-columns-move-row-up`/`-down`. Reorders the underlying org buffer.
---@param direction integer -1 to move up, 1 to move down
---@private
function ColumnView:_move_row(direction)
  local row = self.rows[self.current_row]
  if not row then
    return
  end
  local headline = row.headline
  local sibling = direction < 0 and headline:get_prev_headline_same_level() or headline:get_next_headline_same_level()
  if not sibling then
    return utils.echo_warning('Cannot move past superior level.')
  end

  local range = headline:get_range()
  local target_line = direction < 0 and sibling:get_range().start_line - 1 or sibling:get_range().end_line

  local mark_id = vim.api.nvim_buf_set_extmark(self.bufnr, self.track_ns, range.start_line - 1, 0, {})
  local win = self.winid
  local win_ok = vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == self.bufnr

  -- `:move` reopens the folds contained in the range it moves (folds at the
  -- destination are left alone). A subtree range never partially overlaps a
  -- closed fold, so `:move` still works; remember which folds were closed and
  -- re-close them at their shifted position afterwards.
  local closed_folds = {}
  if win_ok then
    vim.api.nvim_win_call(win, function()
      for line = range.start_line, range.end_line do
        if vim.fn.foldclosed(line) == line then
          table.insert(closed_folds, line)
        end
      end
    end)
  end

  local function do_move()
    self:_write(function()
      vim.api.nvim_buf_call(self.bufnr, function()
        vim.cmd(string.format(':%d,%dmove %d', range.start_line, range.end_line, target_line))
      end)
    end)
  end
  local changedtick = vim.api.nvim_buf_get_changedtick(self.bufnr)
  do_move()
  -- `:move` does nothing when the range partially overlaps a closed fold. That
  -- cannot happen for a fully visible subtree, but fall back to moving with
  -- folding disabled if it ever does.
  if vim.api.nvim_buf_get_changedtick(self.bufnr) == changedtick and win_ok then
    local restore_foldenable = vim.wo[win].foldenable
    vim.wo[win].foldenable = false
    do_move()
    vim.wo[win].foldenable = restore_foldenable
  end

  self:_reload_headlines()

  -- The folds reopened by `:move` have to be re-closed once the fold structure
  -- has been recomputed for the moved text (for `foldmethod=expr` this happens
  -- on the next redraw); re-closing earlier would target the stale fold.
  local new_start = target_line < range.start_line and target_line + 1
    or target_line - (range.end_line - range.start_line)
  if win_ok and #closed_folds > 0 then
    local delta = new_start - range.start_line
    vim.schedule(function()
      if not vim.api.nvim_win_is_valid(win) or vim.api.nvim_win_get_buf(win) ~= self.bufnr then
        return
      end
      vim.api.nvim_win_call(win, function()
        local cursor = vim.api.nvim_win_get_cursor(win)
        for _, line in ipairs(closed_folds) do
          local target = line + delta
          vim.wait(200, function()
            return vim.fn.foldlevel(target) > 0
          end, 5)
          if vim.fn.foldlevel(target) > 0 and vim.fn.foldclosed(target) == -1 then
            vim.fn.cursor(target, 1)
            vim.cmd('silent! normal! zc')
          end
        end
        vim.fn.cursor(cursor)
      end)
    end)
  end
  self:_rebuild_rows()
  self:_render()

  local mark = vim.api.nvim_buf_get_extmark_by_id(self.bufnr, self.track_ns, mark_id, {})
  if mark and mark[1] then
    for idx, r in ipairs(self.rows) do
      if r.headline:get_range().start_line - 1 == mark[1] then
        self.current_row = idx
        if vim.api.nvim_win_is_valid(self.winid) and vim.api.nvim_win_get_buf(self.winid) == self.bufnr then
          vim.api.nvim_win_set_cursor(self.winid, { r.headline:get_range().start_line, 0 })
        end
        break
      end
    end
  end
  vim.api.nvim_buf_del_extmark(self.bufnr, self.track_ns, mark_id)
end

function ColumnView:move_row_up()
  self:_move_row(-1)
end

function ColumnView:move_row_down()
  self:_move_row(1)
end

---Run `fn` in the column view window so window-local fold operations target it.
---@param fn fun()
---@private
function ColumnView:_fold(fn)
  local win = self.winid
  if win and vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == self.bufnr then
    vim.api.nvim_win_call(win, fn)
  else
    fn()
  end
end

---Fold to overview, showing only headlines, like Emacs `org-overview` (`o`).
function ColumnView:overview()
  self:_fold(function()
    vim.wo.foldenable = true
    vim.cmd('silent! normal! zMzX')
  end)
end

---Show headline contents, like Emacs `org-columns-content` (`c`).
function ColumnView:content()
  self:_fold(function()
    vim.wo.foldenable = true
    vim.wo.foldlevel = 1
    vim.cmd('silent! normal! zx')
  end)
end

---Follow the first link found in the current cell, like Emacs
---`org-columns-open-link` (`C-c C-o`).
function ColumnView:open_link()
  local row = self.rows[self.current_row]
  local cell = row and row.cells[self.current_col]
  if not cell then
    return
  end
  local url = compat.extract_link(cell.value)
  if not url then
    return utils.echo_warning('No link at point')
  end
  local links = self.links or require('orgmode.org.links'):new({ files = self.files })
  links:follow(url)
end

function ColumnView:next_value()
  self:_change_value(1)
end

function ColumnView:prev_value()
  self:_change_value(-1)
end

---Candidate values for a column, used by numbered selection and cycling.
---Returns nil when the column has no selectable values (e.g. ITEM).
---@param col OrgColumnSpec
---@return string[]|nil
function ColumnView:_allowed_values_for(col)
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

---Refuse to edit a cell whose value is computed from children, like Emacs'
---`org-columns-check-computed`.
---@param cell OrgColumnViewCell
---@return boolean can_edit
function ColumnView:_check_computed(cell)
  if cell.is_computed then
    utils.echo_warning("This value is computed from the entry's children")
    return false
  end
  return true
end

function ColumnView:select_value(n)
  -- n is 1-9 or 0 (for 10th)
  if n == 0 then
    n = 10
  end
  local row = self.rows[self.current_row]
  if not row then
    return
  end

  local cell = row.cells[self.current_col]
  if not cell or not self:_check_computed(cell) then
    return
  end

  local allowed = self:_allowed_values_for(cell.column)
  if not allowed then
    return
  end

  if n <= #allowed then
    self:_set_cell_value(cell, allowed[n])
  end
end

function ColumnView:_change_value(direction)
  local row = self.rows[self.current_row]
  if not row then
    return
  end

  local cell = row.cells[self.current_col]
  if not cell or not self:_check_computed(cell) then
    return
  end

  local col = cell.column
  local headline = row.headline

  -- TODO and PRIORITY cycle through their configured sequences, which also
  -- handles the "no keyword/priority" state correctly.
  if col.name == 'TODO' then
    local TodoState = require('orgmode.objects.todo_state')
    local ts = TodoState:new({ current_state = headline:get_todo() })
    local next_state = direction > 0 and ts:get_next() or ts:get_prev()
    if next_state then
      self:_write(function()
        headline:set_todo(next_state.value)
      end)
      self:refresh()
    end
    return
  elseif col.name == 'PRIORITY' then
    local PriorityState = require('orgmode.objects.priority_state')
    local ps = PriorityState:new(headline:get_priority(), config:get_priority_range())
    local value = direction > 0 and ps:increase() or ps:decrease()
    self:_write(function()
      headline:set_priority(value)
    end)
    self:refresh()
    return
  end

  local allowed = self.allowed_values[col.name .. '_ALL']
  if not allowed or #allowed == 0 then
    if col.name:upper() == 'ITEM' then
      return
    end
    allowed = { '[ ]', '[X]' }
  end

  local current = cell.value
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

  local new_value = allowed[idx]
  self:_set_cell_value(cell, new_value)
end

---@param cell OrgColumnViewCell
---@param value string
function ColumnView:_set_cell_value(cell, value)
  local headline = cell.headline
  local col = cell.column

  self:_write(function()
    if col.is_special then
      if col.name == 'TODO' then
        headline:set_todo(value)
      elseif col.name == 'PRIORITY' then
        -- Allowed values carry the display form `[#A]`; strip it for storage.
        headline:set_priority(value:match('%[#(.-)%]') or value)
      end
    else
      headline:set_property(col.name:lower(), value)
    end
  end)

  cell.value = self:_get_cell_value(headline, col)
  self:refresh()
end

function ColumnView:quit()
  -- A scheduled leave callback may fire after the view was already closed;
  -- ignore it so it cannot restore a stale window bar over a newer view.
  if not self._opened then
    return
  end
  if self._leave_autocmd_id then
    pcall(vim.api.nvim_del_autocmd, self._leave_autocmd_id)
    self._leave_autocmd_id = nil
  end
  vim.api.nvim_buf_clear_namespace(self.bufnr, self.ns, 0, -1)
  if self.winid and vim.api.nvim_win_is_valid(self.winid) then
    vim.wo[self.winid].winbar = self._original_winbar or ''
  end
  if vim.api.nvim_buf_is_valid(self.bufnr) and self._original_modifiable ~= nil then
    vim.bo[self.bufnr].modifiable = self._original_modifiable
  end
  self._opened = false
  -- Clean up column view keymaps
  require('org-columnview.mappings').clear_view_mappings(self.bufnr)
  if self.on_quit then
    self.on_quit()
  end
  if vim.api.nvim_win_is_valid(self.original_winid) and vim.api.nvim_get_current_win() == self.winid then
    vim.api.nvim_set_current_win(self.original_winid)
  end
end

function ColumnView:view_value()
  local row = self.rows[self.current_row]
  if not row then
    return
  end
  local cell = row.cells[self.current_col]
  if not cell then
    return
  end

  local full_value = cell.value
  if cell.summary then
    full_value = full_value .. '\n\nSummary: ' .. cell.summary
  end

  utils.echo_info(full_value, nil, true)
end

function ColumnView:edit_allowed()
  local row = self.rows[self.current_row]
  if not row then
    return
  end
  local cell = row.cells[self.current_col]
  if not cell then
    return
  end

  local col = cell.column
  if col.is_special then
    -- TODO, PRIORITY, TAGS, ... derive their values from configuration or the
    -- files, not from a `<NAME>_ALL` property (Org itself does not support this).
    utils.echo_info(("Cannot edit allowed values for the special '%s' column"):format(col.name))
    return
  end

  local prop_name = col.name .. '_ALL'
  local prop_key = prop_name:lower()

  -- Per the Org manual, if the allowed values are defined somewhere in the
  -- hierarchy, the edited list is stored in that entry. Otherwise it is stored
  -- in the first entry that is part of the current column view.
  local target = self.rows[1] and self.rows[1].headline or row.headline
  local current = row.headline
  while current do
    local own = current:get_own_properties()
    if own and own[prop_key] then
      target = current
      break
    end
    current = compat.get_parent_headline(current)
  end

  -- Get current allowed values from property
  local current_allowed = self.allowed_values[prop_name] or {}

  -- If no property values, collect unique values from the column in all rows
  if #current_allowed == 0 then
    local seen = {}
    for _, r in ipairs(self.rows) do
      local val = r.cells[self.current_col].value
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

  self.allowed_values[prop_name] = new_allowed

  self:_write(function()
    target:set_property(prop_name, table.concat(new_allowed, ','))
  end)

  self:refresh()
  utils.echo_info(('Allowed values for %s: %s'):format(col.name, table.concat(new_allowed, ', ')))
end

---Change the TODO state of the current row, like Emacs' `org-columns-todo`
---(`C-c C-t`). Acts on the entry independent of the column under the cursor,
---prompting with fast access when configured and cycling otherwise.
function ColumnView:todo()
  local row = self.rows[self.current_row]
  if not row then
    return
  end
  local cell = row.cells[self.current_col]
  if cell and not self:_check_computed(cell) then
    return
  end
  local headline = row.headline
  local next_state = compat.next_todo_state(headline.file:get_todo_keywords(), headline:get_todo())
  if next_state then
    self:_write(function()
      headline:set_todo(next_state.value)
    end)
    self:refresh()
  end
end

---Edit the value at point using appropriate interface for the column type
function ColumnView:edit_value()
  local row = self.rows[self.current_row]
  if not row then
    return
  end
  local cell = row.cells[self.current_col]
  if not cell or not self:_check_computed(cell) then
    return
  end

  local col = cell.column
  local headline = row.headline

  -- Special column types with custom editors
  if col.name == 'TODO' then
    local todo_state = require('orgmode.objects.todo_state')
    local ts = todo_state:new({ current_state = headline:get_todo() })
    local next_state = ts:open_fast_access()
    if next_state then
      self:_write(function()
        headline:set_todo(next_state.value)
      end)
      cell.value = self:_get_cell_value(headline, col)
      self:refresh()
    end
    return
  elseif col.name == 'PRIORITY' then
    local PriorityState = require('orgmode.objects.priority_state')
    local ps = PriorityState:new(headline:get_priority(), config:get_priority_range())
    local new_prio = ps:prompt_user()
    if new_prio then
      self:_write(function()
        headline:set_priority(new_prio)
      end)
      cell.value = self:_get_cell_value(headline, col)
      self:refresh()
    end
    return
  elseif col.name == 'TAGS' then
    -- Use existing set_tags which has tag completion
    local current_tags = utils.tags_to_string(headline:get_own_tags())
    return Input.open('Tags: ', current_tags, function(arg_lead)
      return utils.prompt_autocomplete(arg_lead, self.files:get_tags())
    end):next(function(tags)
      if tags then
        self:_write(function()
          headline:set_tags(tags)
        end)
        cell.value = self:_get_cell_value(headline, col)
        self:refresh()
      end
      return tags
    end)
  end

  -- For regular property columns, use input with allowed values completion
  local prop_name = col.name
  local current_val = cell.value
  local allowed = self.allowed_values[col.name .. '_ALL']

  if allowed and #allowed > 0 then
    -- Use vim.ui.select for selection from allowed values (Neovim 0.6+)
    local items = vim.deepcopy(allowed)
    table.insert(items, 1, '') -- Allow empty/clear
    if vim.ui.select then
      vim.ui.select(items, {
        prompt = ('Select %s: '):format(col.title or col.name),
        format_item = function(item)
          return item == '' and '(clear)' or item
        end,
      }, function(choice)
        if choice then
          self:_write(function()
            headline:set_property(prop_name, choice)
          end)
          cell.value = self:_get_cell_value(headline, col)
          self:refresh()
        end
      end)
    else
      -- Fallback for older Neovim: use input with number selection
      local prompt = ('Select %s:\n'):format(col.title or col.name)
      for i, item in ipairs(items) do
        local label = item == '' and '(clear)' or item
        prompt = prompt .. string.format('\n  %d. %s', i, label)
      end
      prompt = prompt .. '\nEnter number: '
      local choice = vim.fn.input(prompt)
      local idx = tonumber(choice)
      if idx and idx >= 1 and idx <= #items then
        local selected = items[idx]
        self:_write(function()
          headline:set_property(prop_name, selected)
        end)
        cell.value = self:_get_cell_value(headline, col)
        self:refresh()
      end
    end
    return
  else
    -- Free text input without completion
    local input = vim.fn.input(('Edit %s: '):format(col.title or col.name), current_val)
    if not input or vim.trim(input) == '' then
      return
    end
    self:_write(function()
      headline:set_property(prop_name, input)
    end)
    cell.value = self:_get_cell_value(headline, col)
    self:refresh()
  end
end

---Toggle checkbox or quit column view (C-c C-c)
function ColumnView:toggle_or_quit()
  local row = self.rows[self.current_row]
  if not row then
    return
  end
  local cell = row.cells[self.current_col]
  if not cell then
    return
  end

  local col = cell.column
  local headline = row.headline

  -- Toggle a checkbox value. Only property columns can hold checkboxes; the
  -- ITEM column is the headline title and must not cycle the TODO state here.
  if not col.is_special and cell.value:match('^%s*%[.%]') then
    if not self:_check_computed(cell) then
      return
    end
    local new_val = cell.value:gsub('%[(.)%]', function(inner)
      return inner:upper() == 'X' and '[ ]' or '[X]'
    end, 1)
    self:_write(function()
      headline:set_property(col.name:lower(), new_val)
    end)
    cell.value = new_val
    self:refresh()
    return
  end

  -- Otherwise quit the column view.
  self:quit()
end

function ColumnView:narrow_column()
  local row = self.rows[self.current_row]
  if not row then
    return
  end
  local cell = row.cells[self.current_col]
  if not cell then
    return
  end

  local col = cell.column
  local width = col.width or self:_get_width(self.current_col)
  if width > 5 then
    col.width = width - 1
    self._widths = nil
    self:_after_columns_changed()
  end
end

function ColumnView:widen_column()
  local row = self.rows[self.current_row]
  if not row then
    return
  end
  local cell = row.cells[self.current_col]
  if not cell then
    return
  end

  local col = cell.column
  local width = col.width or self:_get_width(self.current_col)
  col.width = math.min(width + 1, 50)
  self._widths = nil
  self:_after_columns_changed()
end

function ColumnView:insert_column()
  local name = vim.fn.input('Column name: ')
  if not name or vim.trim(name) == '' then
    return
  end

  local width_input = vim.fn.input('Width (optional): ')
  local width = tonumber(width_input)

  local new_col = {
    name = name:upper(),
    width = width,
    title = name,
    summary_type = nil,
    allowed_values = nil,
    is_special = false,
  }

  table.insert(self.columns, self.current_col, new_col)
  self:_after_columns_changed()
end

---Edit the property, title, width and summary type of the current column.
function ColumnView:edit_attributes()
  local row = self.rows[self.current_row]
  if not row then
    return
  end
  local cell = row.cells[self.current_col]
  if not cell then
    return
  end
  local col = cell.column

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

  self._widths = nil
  self:_after_columns_changed()
end

function ColumnView:delete_column()
  if #self.columns <= 1 then
    return
  end
  table.remove(self.columns, self.current_col)
  if self.current_col > #self.columns then
    self.current_col = #self.columns
  end
  self:_after_columns_changed()
end

function ColumnView:move_column_left()
  if self.current_col > 1 then
    local col = table.remove(self.columns, self.current_col)
    table.insert(self.columns, self.current_col - 1, col)
    self.current_col = self.current_col - 1
    self:_after_columns_changed()
  end
end

function ColumnView:move_column_right()
  if self.current_col < #self.columns then
    local col = table.remove(self.columns, self.current_col)
    table.insert(self.columns, self.current_col + 1, col)
    self.current_col = self.current_col + 1
    self:_after_columns_changed()
  end
end

function ColumnView:_rebuild_rows()
  self:_build_rows()
end

---Show help for column view
function ColumnView:show_help()
  require('org-columnview').show_help()
end

---@param headline OrgHeadline
---@return OrgColumnViewRow|nil
function ColumnView:get_row_for_headline(headline)
  local row_idx = self._headline_to_row[headline]
  return row_idx and self.rows[row_idx] or nil
end

function ColumnView:refresh()
  -- Editing a cell can insert or remove lines (e.g. adding a property drawer),
  -- which invalidates the cached headline nodes. Re-derive them from the buffer
  -- so that every row keeps rendering at its new position.
  self:_reload_headlines()
  self:_build_rows()
  self:_render()
end

return ColumnView
