---Helpers that work on top of the nvim-orgmode API.
---
---The column view needs a few things that nvim-orgmode does not provide (yet):
---reading the file level `#+COLUMNS:` and `#+PROPERTY:` keywords, writing the
---column format back to the buffer, extracting a link from a cell value and
---cycling the TODO state with the fast access menu. They are implemented here
---so that the plugin works with any nvim-orgmode version.
local M = {}

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

return M
