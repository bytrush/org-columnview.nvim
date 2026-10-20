local columnview_config = require('org-columnview.config')

---@class OrgColumnParser
local Parser = {}

local SPECIAL_COLUMNS = {
  ITEM = true,
  CLOCKSUM = true,
  CLOCKSUM_T = true,
  AGE = true,
  TAGS = true,
  ALLTAGS = true,
  TODO = true,
  PRIORITY = true,
  CATEGORY = true,
  SCHEDULED = true,
  DEADLINE = true,
  CLOSED = true,
  FILE = true,
  BLOCKED = true,
  TIMESTAMP = true,
  TIMESTAMP_IA = true,
}

---@param name string
---@return boolean
function Parser.is_special_column(name)
  return name ~= nil and SPECIAL_COLUMNS[name:upper()] == true
end

---Serialize parsed columns back into a column format string, mirroring Emacs'
---`org-columns-uncompile-format`. The title is omitted when it matches the
---property name, and allowed values are kept as a trailing brace so they
---survive a round trip.
---@param columns OrgColumnSpec[]
---@return string
function Parser.unparse(columns)
  local specs = {}
  for _, col in ipairs(columns) do
    local spec = '%'
    if col.width then
      spec = spec .. tostring(col.width)
    end
    spec = spec .. col.name
    if col.title and col.title:upper() ~= col.name:upper() then
      spec = spec .. '(' .. col.title .. ')'
    end
    if col.summary_type then
      spec = spec .. '{' .. col.summary_type .. '}'
    end
    if col.allowed_values and #col.allowed_values > 0 then
      spec = spec .. '{' .. table.concat(col.allowed_values, ',') .. '}'
    end
    table.insert(specs, spec)
  end
  return table.concat(specs, ' ')
end

---@param format_string string
---@return OrgColumnsDefinition
function Parser.parse(format_string)
  if not format_string or format_string == '' then
    return { columns = {}, allowed_values = {} }
  end

  local columns = {}
  local allowed_values = {}

  local parts = Parser._split_format_string(format_string)

  for _, part in ipairs(parts) do
    local col = Parser._parse_column_spec(part)
    if col then
      table.insert(columns, col)
    end
  end

  for _, col in ipairs(columns) do
    if col.allowed_values then
      allowed_values[col.name .. '_ALL'] = col.allowed_values
    end
  end

  return {
    columns = columns,
    allowed_values = allowed_values,
  }
end

---@param str string
---@return string[]
function Parser._split_format_string(str)
  local parts = {}
  local current = ''
  local brace_depth = 0
  local bracket_depth = 0
  local in_paren = false

  for i = 1, #str do
    local c = str:sub(i, i)

    if c == '{' then
      brace_depth = brace_depth + 1
    elseif c == '}' then
      brace_depth = brace_depth - 1
    elseif c == '[' then
      bracket_depth = bracket_depth + 1
    elseif c == ']' then
      bracket_depth = bracket_depth - 1
    elseif c == '(' then
      in_paren = true
    elseif c == ')' then
      in_paren = false
    end

    if c:match('%s') and brace_depth == 0 and bracket_depth == 0 and not in_paren then
      if current ~= '' then
        table.insert(parts, current)
        current = ''
      end
    else
      current = current .. c
    end
  end

  if current ~= '' then
    table.insert(parts, current)
  end

  return parts
end

---Split a property value into allowed values. Comma separated lists are split
---on commas, otherwise whitespace is used, mirroring Emacs' `NAME_ALL`
---properties. Values are trimmed and empty entries are dropped.
---@param value string
---@return string[]
function Parser.split_allowed_values(value)
  local pattern = value:find(',', 1, true) and '[^,]+' or '%S+'
  local values = {}
  for matched in value:gmatch(pattern) do
    local v = vim.trim(matched)
    if v ~= '' then
      table.insert(values, v)
    end
  end
  return values
end

---@param content string
---@return string[]
function Parser._parse_allowed_values(content)
  -- Handle inline values like {[ ],[X]} or property references like Owner_ALL.
  -- content may be: "Owner_ALL" (property ref), "[ ],[X]" (inline values) or
  -- "1,2,3" (comma separated inline values).
  if content:match('%[') then
    -- Inline values: extract all [...] patterns
    local values = {}
    for v in content:gmatch('%[([^%]]+)%]') do
      table.insert(values, '[' .. v .. ']')
    end
    if #values > 0 then
      return values
    end
    -- Fallback: split by comma
    return vim.split(content, ',', { trimempty = true })
  end

  if content:find(',', 1, true) then
    return Parser.split_allowed_values(content)
  end

  -- Property reference like Owner_ALL
  return { content }
end

---@param spec string
---@return OrgColumnSpec|nil
function Parser._parse_column_spec(spec)
  local name, width, title, summary_type, allowed_values

  -- Match: %[width]name[(title)]{summary}{values}
  -- %% in Lua pattern = literal %
  local pattern = '^%%(%d*)([^%({}]+)'
  local w, n = spec:match(pattern)
  if not n then
    return nil
  end

  width = w ~= '' and tonumber(w) or nil
  name = n:upper()
  local original_name = n -- Keep original for title

  -- Pattern starts with literal % (matched as %% in pattern), so skip 1 + width digits + name
  local remaining = spec:sub(1 + #w + #n + 1)

  if remaining:match('^%(') then
    local title_match = remaining:match('^%(([^%)]+)%)')
    if title_match then
      title = title_match
      remaining = remaining:sub(#title_match + 3)
    end
  end

  -- Parse braces - can be summary type or allowed values
  local brace_contents = {}
  while remaining:match('^{') do
    local content = remaining:match('^{([^}]+)}')
    if content then
      table.insert(brace_contents, content)
      remaining = remaining:sub(#content + 3)
    else
      break
    end
  end

  -- First brace: summary type if it looks like one, otherwise allowed values
  -- Second brace (if present): allowed values
  if #brace_contents >= 1 then
    local first = brace_contents[1]
    -- Check if it's a summary type (:, +, $, min, max, mean, X, @, est+)
    local is_summary = first:match('^[:+]')
      or first == '$'
      or first:match('^min$')
      or first:match('^max$')
      or first:match('^mean$')
      or first:match('^X[/%%]?$')
      or first:match('^@')
      or first:match('^est%+$')

    if is_summary then
      summary_type = first
      if #brace_contents >= 2 then
        allowed_values = Parser._parse_allowed_values(brace_contents[2])
      end
    else
      -- It's allowed values (reference or inline)
      allowed_values = Parser._parse_allowed_values(first)
    end
  end

  local is_special = SPECIAL_COLUMNS[name:upper()] == true

  if not title then
    title = original_name
  end

  return {
    name = name,
    width = width,
    title = title,
    summary_type = summary_type,
    allowed_values = allowed_values,
    is_special = is_special,
  }
end

---Resolve the raw column format string for a headline, checking only the
---headline's own `:COLUMNS:` property, its ancestors and the file
---directive. Returns nil when the format is not defined locally, so callers
---can fall back to a wider default.
---@param headline OrgHeadline
---@return string|nil
function Parser.get_columns_format_for_headline(headline)
  local columns_prop = headline:get_property('COLUMNS')
  if columns_prop then
    return columns_prop
  end

  local parent_section = headline:node():parent():parent()
  while parent_section do
    local parent_headline_node = parent_section:field('headline')[1]
    if parent_headline_node then
      local parent_headline = require('orgmode.files.headline'):new(parent_headline_node, headline.file)
      local parent_prop = parent_headline:get_property('COLUMNS')
      if parent_prop then
        return parent_prop
      end
    end
    parent_section = parent_section:parent()
  end

  return headline.file:get_file_columns()
end

---@param headline OrgHeadline
---@return OrgColumnsDefinition|nil
function Parser.get_columns_for_headline(headline)
  local format = Parser.get_columns_format_for_headline(headline)
  if format then
    return Parser.parse(format)
  end

  return Parser.get_columns_for_file(headline.file)
end

---Resolve the column definition for a whole file (no headline context).
---@param file OrgFile
---@return OrgColumnsDefinition|nil
function Parser.get_columns_for_file(file)
  local file_columns = file:get_file_columns()
  if file_columns then
    return Parser.parse(file_columns)
  end

  local default_format = columnview_config.default_format
  if default_format and default_format ~= '' then
    return Parser.parse(default_format)
  end

  return nil
end

return Parser
