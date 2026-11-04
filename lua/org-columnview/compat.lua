---Helpers that work on top of the nvim-orgmode API.
---
---The column view needs a few things that nvim-orgmode does not provide (yet):
---reading the file level `#+COLUMNS:` and `#+PROPERTY:` keywords, writing the
---column format back to the buffer, extracting a link from a cell value and
---cycling the TODO state with the fast access menu. They are implemented here
---so that the plugin works with any nvim-orgmode version.
local M = {}

---The priority range of the configuration. The values are always strings, so
---that a priority configured as a number works as well.
---@return { highest: string, default: string, lowest: string }
function M.get_priority_range()
  local range = require('orgmode.config'):get_priority_range()
  return {
    highest = tostring(range.highest),
    default = tostring(range.default),
    lowest = tostring(range.lowest),
  }
end

---The parent headline of an entry, or nil when the entry has no parent
---headline. nvim-orgmode returns a headline without a node in that case, which
---breaks everything that is done with it.
---@param headline OrgHeadline
---@return OrgHeadline|nil
function M.get_parent_headline(headline)
  local parent_section = headline:node():parent():parent()
  if not parent_section then
    return nil
  end
  local node = parent_section:field('headline')[1]
  if not node then
    return nil
  end
  return require('orgmode.files.headline'):new(node, headline.file)
end

---Read a file level keyword, like `#+COLUMNS:`. Uses the un-memoized lookup
---of nvim-orgmode, so that the value is never stale.
---@param file OrgFile
---@param name string keyword name, upper case
---@return string|nil
function M.get_file_directive(file, name)
  local value = file:_get_directive(name)
  if type(value) == 'string' and vim.trim(value) ~= '' then
    return value
  end
  return nil
end

---Read the column format of a file, from the `#+COLUMNS:` keyword.
---@param file OrgFile
---@return string|nil
function M.get_file_columns(file)
  return M.get_file_directive(file, 'COLUMNS')
end

---Read a keyword property, like `#+PROPERTY: OWNER_ALL Alice, Bob` or
---`#+OWNER_ALL: Alice, Bob`. Mirrors Emacs' `org-keyword-properties`.
---@param file OrgFile
---@param name string property name
---@return string|nil
function M.get_keyword_property(file, name)
  local wanted = name:lower()

  local property_directives = file:_get_directive('property', true)
  if type(property_directives) == 'table' then
    for _, directive in ipairs(property_directives) do
      local property_name, value = directive:match('^(%S+)%s+(.*)$')
      if property_name and value and property_name:lower() == wanted and vim.trim(value) ~= '' then
        return vim.trim(value)
      end
    end
  end

  local value = file:_get_directive(name)
  if type(value) == 'string' and vim.trim(value) ~= '' then
    return vim.trim(value)
  end

  return nil
end

---Prompt for a string with completion from a fixed list. Uses a `customlist`
---callback on `vim.fn.input()` so the column editor keeps its synchronous
---prompt flow.
---@param prompt string
---@param default? string
---@param items string[]
---@return string
function M.input_with_completion(prompt, default, items)
  _G.orgmode = _G.orgmode or {}
  _G.orgmode.__columnview_input_completion = function(arg_lead)
    local lead = (arg_lead or ''):lower()
    local matches = {}
    for _, item in ipairs(items) do
      if item:lower():find(lead, 1, true) == 1 then
        table.insert(matches, item)
      end
    end
    return matches
  end

  return vim.fn.input({
    prompt = prompt,
    default = default or '',
    completion = 'customlist,v:lua.orgmode.__columnview_input_completion',
  })
end

---Allowed values supplied by the configured functions, before the
---`PROPERTY_ALL` property is consulted. Mirrors
---`org-property-allowed-value-functions`.
---@param property string
---@return string[]|nil
function M.get_hook_allowed_values(property)
  local functions = require('org-columnview.config').allowed_value_functions
  if type(functions) ~= 'table' then
    return nil
  end

  for _, fn in ipairs(functions) do
    local values = fn(property)
    if type(values) == 'table' then
      local normalized = {}
      for _, value in ipairs(values) do
        if value ~= '' then
          table.insert(normalized, tostring(value))
        end
      end
      if #normalized > 0 then
        return normalized
      end
    end
  end

  return nil
end

---Read a property from a headline, its ancestors, or the file-wide keywords.
---Emacs uses this inheritance chain when it looks up `PROPERTY_ALL` for the
---allowed values of a column.
---@param headline OrgHeadline
---@param name string property name, case insensitive
---@return string|nil
function M.get_inherited_property(headline, name)
  local current = headline
  while current do
    local value = current:get_property(name)
    if type(value) == 'string' and vim.trim(value) ~= '' then
      return vim.trim(value)
    end
    current = M.get_parent_headline(current)
  end
  return M.get_keyword_property(headline.file, name)
end

---Write the column format to the first `#+COLUMNS:` keyword of the file, or
---create one before the first headline when the file has none. Mirrors Emacs'
---file level branch of `org-columns-store-format`.
---@param file OrgFile
---@param format string
function M.set_file_columns(file, format)
  local bufnr = file:get_valid_bufnr()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local first_headline
  for i, line in ipairs(lines) do
    if not first_headline and line:match('^%*+ ') then
      first_headline = i
    end
    local _, prefix_end = line:lower():find('^%s*#%+columns:')
    if prefix_end then
      vim.api.nvim_buf_set_lines(bufnr, i - 1, i, false, { line:sub(1, prefix_end) .. ' ' .. format })
      return
    end
  end

  local insert_at = (first_headline or 1) - 1
  vim.api.nvim_buf_set_lines(bufnr, insert_at, insert_at, false, { '#+COLUMNS: ' .. format })
end

---Write a file level keyword property, like `#+PROPERTY: NAME VALUE`.
---@param file OrgFile
---@param name string
---@param value string
function M.set_keyword_property(file, name, value)
  local bufnr = file:get_valid_bufnr()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local first_headline
  for i, line in ipairs(lines) do
    if not first_headline and line:match('^%*+ ') then
      first_headline = i
    end
    local prefix, property_name = line:match('^(%s*#%+[Pp][Rr][Oo][Pp][Ee][Rr][Tt][Yy]:%s*)(%S+)')
    if prefix and property_name and property_name:upper() == name:upper() then
      vim.api.nvim_buf_set_lines(bufnr, i - 1, i, false, { prefix .. name .. ' ' .. value })
      return
    end
  end

  local insert_at = (first_headline or 1) - 1
  vim.api.nvim_buf_set_lines(bufnr, insert_at, insert_at, false, { '#+PROPERTY: ' .. name .. ' ' .. value })
end

---Extract the first Org link from a string, mirroring the bracketed and plain
---forms accepted by Emacs' `org-link-open-from-string`.
---@param text string|nil
---@return string|nil
function M.extract_link(text)
  if not text then
    return nil
  end
  local bracketed = text:match('%[%[([^%]]+)%]%]') or text:match('%[%[([^%]]+)%]')
  if bracketed then
    return bracketed
  end
  return text:match('([%a][%w+.-]*:[^%s]+)')
end

---The next TODO state, using the fast access menu when it is configured.
---@param todos OrgTodoKeywords
---@param current_state string|nil
---@return { value: string }|nil
function M.next_todo_state(todos, current_state)
  local TodoState = require('orgmode.objects.todo_state')
  local ts = TodoState:new({ current_state = current_state, todos = todos })
  if ts:has_fast_access() then
    return ts:open_fast_access()
  end
  return ts:get_next()
end

---Rename a headline in place. The stars, TODO keyword, priority and tags are
---kept, only the title part is replaced.
---@param headline OrgHeadline
---@param title string
---@return OrgHeadline
function M.set_headline_title(headline, title)
  local file = headline.file
  local bufnr = file:get_valid_bufnr()
  local line_nr = headline:get_range().start_line
  local line = headline:get_headline_line_content()
  local current_title, offset = headline:get_title()
  title = vim.trim((title or ''):gsub('[\r\n]+', ' '))
  local new_line = line:sub(1, offset) .. title .. line:sub(offset + #current_title + 1)
  vim.api.nvim_buf_set_lines(bufnr, line_nr - 1, line_nr, false, { new_line })
  return headline:refresh()
end

---The scheduled or deadline date of a headline.
---@param headline OrgHeadline
---@param name 'SCHEDULED'|'DEADLINE'
---@return OrgDate|nil
function M.get_headline_date(headline, name)
  if name == 'SCHEDULED' then
    return headline:get_scheduled_date()
  end
  return headline:get_deadline_date()
end

---Set the scheduled or deadline date of a headline.
---@param headline OrgHeadline
---@param name 'SCHEDULED'|'DEADLINE'
---@param date OrgDate
function M.set_headline_date(headline, name, date)
  if name == 'SCHEDULED' then
    return headline:set_scheduled_date(date)
  end
  return headline:set_deadline_date(date)
end

---Remove the scheduled or deadline date of a headline.
---@param headline OrgHeadline
---@param name 'SCHEDULED'|'DEADLINE'
function M.remove_headline_date(headline, name)
  if name == 'SCHEDULED' then
    return headline:remove_scheduled_date()
  end
  return headline:remove_deadline_date()
end

return M
