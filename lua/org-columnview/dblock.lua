---Dynamic `#+BEGIN: columnview` blocks.
---
---The block captures the current column view as a static Org table. It mirrors
---Emacs' `org-dblock-write:columnview` and its `:id`, `:format`, `:hlines`,
---`:indent`, `:match`, `:maxlevel`, `:skip-empty-rows`, `:vlines`, `:link`,
---`:exclude-tags` and `:formatter` parameters.
local Cells = require('org-columnview.cells')
local Parser = require('org-columnview.parser')
local Summary = require('org-columnview.summary')
local compat = require('org-columnview.compat')
local columnview_config = require('org-columnview.config')
local utils = require('orgmode.utils')

---@class OrgColumnViewDblockParams
---@field id? string
---@field format? string
---@field hlines? boolean|number
---@field indent? boolean
---@field match? string
---@field maxlevel? number
---@field skip_empty_rows? boolean
---@field vlines? boolean
---@field link? boolean
---@field exclude_tags? string
---@field formatter? string

---@class OrgColumnViewDblockData
---@field columns OrgColumnSpec[]
---@field header string[]
---@field rows (string[]|'hline')[]
---@field entries { headline: OrgHeadline, level: number, cells: string[] }[]

local M = {}

---@param line string
---@return boolean
local function is_begin(line)
  return line:lower():match('^%s*#%+begin:%s*columnview') ~= nil
end

---@param line string
---@return boolean
local function is_end(line)
  return line:lower():match('^%s*#%+end:%s*$') ~= nil
end

---@param value string|number|boolean|nil
---@return boolean
local function as_boolean(value)
  if value == nil or value == false then
    return false
  end
  if type(value) == 'boolean' then
    return value
  end
  local text = tostring(value):lower()
  return text ~= '' and text ~= 'nil' and text ~= 'false' and text ~= 'f' and text ~= '0'
end

---@param value unknown
---@param default? number
---@return number|nil
local function as_number(value, default)
  if type(value) == 'number' then
    return value
  end
  if type(value) == 'string' then
    return tonumber(value) or default
  end
  return default
end

---Parse the parameters of a `#+BEGIN: columnview` line.
---@param line string
---@return OrgColumnViewDblockParams
function M.parse_params(line)
  local _, finish = line:lower():find('^%s*#%+begin:%s*columnview')
  local text = finish and line:sub(finish + 1) or ''
  local params = {}
  local i = 1
  local length = #text

  local function skip_space()
    while i <= length and text:sub(i, i):match('%s') do
      i = i + 1
    end
  end

  while i <= length do
    skip_space()
    if text:sub(i, i) ~= ':' then
      break
    end

    local key_start = i + 1
    local key_end = key_start
    while key_end <= length and not text:sub(key_end, key_end):match('[%s:]') do
      key_end = key_end + 1
    end
    local key = text:sub(key_start, key_end - 1):lower():gsub('%-', '_')
    i = key_end
    skip_space()

    local value
    if text:sub(i, i) == '"' then
      local close = text:find('"', i + 1, true)
      value = text:sub(i + 1, (close or length + 1) - 1)
      i = (close or length) + 1
    else
      local value_start = i
      while i <= length do
        if text:sub(i, i) == ':' and (i == value_start or text:sub(i - 1, i - 1):match('%s')) then
          break
        end
        i = i + 1
      end
      value = text:sub(value_start, i - 1)
    end

    if key ~= '' then
      params[key] = vim.trim(value or '')
    end
  end

  return params
end

---@param params table
---@return string
local function begin_line(params)
  local parts = { '#+BEGIN: columnview' }
  local keys = vim.tbl_keys(params)
  table.sort(keys)
  for _, key in ipairs(keys) do
    local value = params[key]
    if value ~= nil and value ~= false and value ~= '' then
      local name = key:gsub('_', '-')
      if type(value) == 'string' and value:find('%s') then
        value = '"' .. value .. '"'
      end
      table.insert(parts, (':%s %s'):format(name, tostring(value)))
    end
  end
  return table.concat(parts, ' ')
end

---@param bufnr number
---@param lnum number 0-based cursor row
---@return { start_line: number, end_line: number, params: OrgColumnViewDblockParams }|nil
local function find_block(bufnr, lnum)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local start_line
  for i = math.min(lnum + 1, #lines), 1, -1 do
    if is_begin(lines[i]) then
      start_line = i
      break
    end
  end
  if not start_line then
    return nil
  end

  local end_line
  for i = start_line + 1, #lines do
    if is_end(lines[i]) then
      end_line = i
      break
    end
  end
  if not end_line then
    return nil
  end

  return {
    start_line = start_line,
    end_line = end_line,
    params = M.parse_params(lines[start_line]),
  }
end

---@param headline OrgHeadline
---@return OrgHeadline[]
local function subtree_headlines(headline)
  local result = {}
  local function add(item)
    table.insert(result, item)
    for _, child in ipairs(item:get_child_headlines()) do
      add(child)
    end
  end
  add(headline)
  return result
end

---@param file OrgFile
---@return OrgHeadline[]
local function file_headlines(file)
  local result = {}
  for _, headline in ipairs(file:get_top_level_headlines()) do
    vim.list_extend(result, subtree_headlines(headline))
  end
  return result
end

---Resolve the target file and the headline that starts the captured tree.
---@param params OrgColumnViewDblockParams
---@return OrgFile, OrgHeadline|nil
local function resolve_target(params)
  local org = require('orgmode')
  local files = org.files
  local current_file = files:get_current_file()
  local current_headline = files:get_closest_headline_or_nil()
  local id = params.id or 'local'

  if id == 'global' then
    return current_file, nil
  end

  if id:match('^file:(.+)$') then
    local filename = id:match('^file:(.+)$')
    return files:get(filename), nil
  end

  if id ~= 'local' then
    local search_files = { current_file }
    for _, file in ipairs(files:all()) do
      if file ~= current_file then
        table.insert(search_files, file)
      end
    end
    for _, file in ipairs(search_files) do
      for _, headline in ipairs(file:get_headlines()) do
        if headline:get_property('ID', false) == id then
          return file, headline
        end
      end
    end
    error(('Cannot find entry with :ID: %s'):format(id))
  end

  if not current_headline then
    return current_file, nil
  end
  return current_file, Parser.get_columns_owner(current_headline) or current_headline
end

---@param headline OrgHeadline
---@param params OrgColumnViewDblockParams
---@return boolean
local function matches_filters(headline, params)
  if columnview_config.skip_archived_trees ~= false and headline:is_archived() then
    return false
  end

  local maxlevel = as_number(params.maxlevel)
  if maxlevel and headline:get_level() > maxlevel then
    return false
  end

  if params.match and params.match ~= '' then
    local ok, filter = pcall(function()
      return require('orgmode.agenda.filter'):new():parse(params.match, true)
    end)
    if ok and filter and not filter:matches(headline) then
      return false
    end
  end

  if params.exclude_tags and params.exclude_tags ~= '' then
    local excluded = {}
    for tag in params.exclude_tags:gmatch('%S+') do
      excluded[tag] = true
    end
    for _, tag in ipairs(headline:get_tags()) do
      if excluded[tag] then
        return false
      end
    end
  end

  return true
end

---@param params OrgColumnViewDblockParams
---@param headline OrgHeadline
---@param columns OrgColumnSpec[]
---@param cells OrgColumnCells
---@return string[]
local function collect_row_cells(params, headline, columns, cells)
  local values = {}
  local level = headline:get_level()

  for _, col in ipairs(columns) do
    local value = cells:get_value(headline, col)
    local summary = nil
    if col.summary_type and headline:has_child_headlines() then
      local child_values = {}
      for _, child in ipairs(headline:get_child_headlines()) do
        table.insert(child_values, cells:get_value(child, col))
      end
      summary = Summary.compute(child_values, col.summary_type, col.format)
    end

    local display = Cells.display_value(col, value)
    if col.name == 'ITEM' then
      display = display:gsub('^%s+', '')
      if as_boolean(params.indent) and level > 1 then
        display = '\\_' .. string.rep(' ', 2 * (level - 1)) .. display
      end
      if as_boolean(params.link) then
        local title = headline:get_title()
        display = ('[[file:%s::*%s][%s]]'):format(headline.file.filename, title, display)
      end
    elseif summary then
      display = display == '' and ('Σ=' .. summary) or (display .. ' Σ=' .. summary)
    end

    table.insert(values, display)
  end

  return values
end

---@param params OrgColumnViewDblockParams
---@return OrgColumnViewDblockData|nil
function M.collect(params)
  local file, scope = resolve_target(params)
  if not file then
    utils.echo_error('No org file for the column view block')
    return nil
  end

  local columns
  if params.format and params.format ~= '' then
    columns = Parser.parse(params.format)
  elseif scope then
    columns = Parser.get_columns_for_headline(scope)
  else
    columns = Parser.get_columns_for_file(file)
  end

  if not columns or #columns.columns == 0 then
    utils.echo_error('No column view definition found')
    return nil
  end

  local headlines = scope and subtree_headlines(scope) or file_headlines(file)
  local cells = Cells:new()

  local header = {}
  for _, col in ipairs(columns.columns) do
    table.insert(header, col.title or col.name)
  end

  local entries = {}
  local rows = {}
  local has_item = columns.columns[1] and columns.columns[1].name == 'ITEM'

  for _, headline in ipairs(headlines) do
    if matches_filters(headline, params) then
      local values = collect_row_cells(params, headline, columns.columns, cells)
      local empty = true
      for index, value in ipairs(values) do
        if not (has_item and index == 1) and value ~= '' then
          empty = false
          break
        end
      end

      if not (as_boolean(params.skip_empty_rows) and empty) then
        table.insert(entries, { headline = headline, level = headline:get_level(), cells = values })
        table.insert(rows, values)
      end
    end
  end

  return {
    columns = columns.columns,
    header = header,
    rows = rows,
    entries = entries,
  }
end

---Pad a table row to the computed column widths, like `org-table-align`.
---@param rows (string[]|'hline')[]
---@return string[]
local function align_rows(rows)
  local widths = {}
  for _, row in ipairs(rows) do
    if row ~= 'hline' then
      for index, cell in ipairs(row) do
        widths[index] = math.max(widths[index] or 0, vim.api.nvim_strwidth(cell))
      end
    end
  end

  local lines = {}
  for _, row in ipairs(rows) do
    if row == 'hline' then
      local segments = {}
      for index = 1, #widths do
        segments[index] = string.rep('-', widths[index] + 2)
      end
      table.insert(lines, '|' .. table.concat(segments, '+') .. '|')
    else
      local cells = {}
      for index, cell in ipairs(row) do
        local padding = string.rep(' ', (widths[index] or 0) - vim.api.nvim_strwidth(cell))
        cells[index] = ' ' .. cell .. padding .. ' '
      end
      table.insert(lines, '|' .. table.concat(cells, '|') .. '|')
    end
  end
  return lines
end

---@param data OrgColumnViewDblockData
---@param params OrgColumnViewDblockParams
---@return string[]
function M.render(data, params)
  local rows = {}
  local hlines = params.hlines
  local hline_number = tonumber(hlines)
  local all_hlines = as_boolean(hlines) and hline_number == nil

  local function add(row)
    if row == 'hline' and rows[#rows] == 'hline' then
      return
    end
    table.insert(rows, row)
  end

  add(data.header)
  add('hline')

  for index, row in ipairs(data.rows) do
    local entry = data.entries[index]
    if all_hlines or (hline_number and entry.level <= hline_number) then
      add('hline')
    end
    add(row)
  end

  if as_boolean(params.vlines) then
    local width = #data.header + 1
    local vline = { '/' }
    for _ = 1, width - 1 do
      table.insert(vline, '<>')
    end
    table.insert(rows, vline)
  end

  return align_rows(rows)
end

---@param params OrgColumnViewDblockParams
---@param opts? { formatter?: fun(data: OrgColumnViewDblockData, params: OrgColumnViewDblockParams): string|string[]|nil }
---@return string[]|nil
local function build_lines(params, opts)
  local data = M.collect(params)
  if not data then
    return nil
  end

  if as_boolean(params.vlines) then
    for _, row in ipairs(data.rows) do
      table.insert(row, 1, '')
    end
    table.insert(data.header, 1, '')
  end

  local formatter = opts and opts.formatter
  if not formatter and params.formatter and params.formatter ~= '' then
    formatter = _G[params.formatter]
  end
  if type(formatter) == 'function' then
    local result = formatter(data, params)
    if type(result) == 'string' then
      return vim.split(result, '\n', { plain = true })
    elseif type(result) == 'table' then
      return result
    end
  end

  return M.render(data, params)
end

---Update the columnview block at the cursor.
---@param opts? { bufnr?: number, formatter?: fun(data: OrgColumnViewDblockData, params: OrgColumnViewDblockParams): string|string[]|nil }
---@return boolean
function M.update(opts)
  opts = opts or {}
  local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local block = find_block(bufnr, cursor[1] - 1)
  if not block then
    utils.echo_error('No column view dynamic block at point')
    return false
  end

  local lines = build_lines(block.params, opts)
  if not lines then
    return false
  end

  vim.api.nvim_buf_set_lines(bufnr, block.start_line, block.end_line - 1, false, lines)
  return true
end

---Update every columnview block in the buffer.
---@param opts? { bufnr?: number, formatter?: fun(data: OrgColumnViewDblockData, params: OrgColumnViewDblockParams): string|string[]|nil }
---@return number updated
function M.update_all(opts)
  opts = opts or {}
  local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local starts = {}
  for index, line in ipairs(lines) do
    if is_begin(line) then
      table.insert(starts, index)
    end
  end

  local updated = 0
  for index = #starts, 1, -1 do
    vim.api.nvim_win_set_cursor(0, { starts[index], 0 })
    if M.update({ bufnr = bufnr, formatter = opts.formatter }) then
      updated = updated + 1
    end
  end
  return updated
end

---Insert a columnview dynamic block at the cursor and populate it.
---@param opts? { bufnr?: number, params?: OrgColumnViewDblockParams, formatter?: fun(data: OrgColumnViewDblockData, params: OrgColumnViewDblockParams): string|string[]|nil }
---@return boolean false when the scope prompt is canceled
function M.insert(opts)
  opts = opts or {}
  local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()
  local params = vim.deepcopy(opts.params or {})

  if not params.id then
    local id = vim.fn.input({
      prompt = 'Capture columns (local, global, entry ID) [local]: ',
      cancelreturn = vim.NIL,
    })
    if id == nil or id == vim.NIL then
      return false
    end
    id = vim.trim(id)
    if id == '' then
      id = 'local'
    end
    params.id = id
  end
  if params.hlines == nil then
    params.hlines = 1
  end

  local row = vim.api.nvim_win_get_cursor(0)[1]
  vim.api.nvim_buf_set_lines(bufnr, row, row, false, { begin_line(params), '#+END:' })
  vim.api.nvim_win_set_cursor(0, { row + 1, 0 })
  local ok = M.update({ bufnr = bufnr, formatter = opts.formatter })
  return ok
end

return M
