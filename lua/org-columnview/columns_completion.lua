---Completion of the column format in a `#+COLUMNS:` keyword or a `:COLUMNS:`
---property.
---@class OrgColumnViewColumnsCompletion:OrgCompletionSource
---@field private directive_pattern vim.regex
---@field private keyword_pattern vim.regex
---@field private property_pattern vim.regex
---@field private completion OrgCompletion
local Completion = {}
Completion.__index = Completion

local COLUMN_KEYWORDS = {
  '%ITEM',
  '%TODO',
  '%PRIORITY',
  '%TAGS',
  '%ALLTAGS',
  '%CATEGORY',
  '%SCHEDULED',
  '%DEADLINE',
  '%CLOSED',
  '%CLOCKSUM',
  '%CLOCKSUM_T',
  '%AGE',
  '%FILE',
  '%BLOCKED',
  '%TIMESTAMP',
  '%TIMESTAMP_IA',
}

local SUMMARY_TYPES = {
  '+',
  ':',
  ':min',
  ':max',
  ':mean',
  '$',
  'min',
  'max',
  'mean',
  'X',
  'X/',
  'X%',
  '@min',
  '@max',
  '@mean',
  'est+',
  '+;%.2f',
}

function Completion:new(opts)
  return setmetatable({
    completion = opts.completion,
    directive_pattern = vim.regex([[\c^\s*\(\#+columns:\|:columns:\)\s]]),
    keyword_pattern = vim.regex([[\c^\s*\#+\?\w*$]]),
    property_pattern = vim.regex([[\c^\s*:\w*$]]),
  }, Completion)
end

function Completion:get_name()
  return 'columnview_columns'
end

---The property names that are in use, to complete the column format with them.
---The properties of the current file are used, and, in the agenda, the
---properties of the entries that are loaded.
---@return string[]
function Completion:_property_names()
  local names = {}
  local seen = {}

  local function add(name)
    if not name or name == '' then
      return
    end
    local upper = name:upper()
    if not seen[upper] then
      seen[upper] = true
      table.insert(names, '%' .. upper)
    end
  end

  local files = self.completion.files
  -- The current file is not an org file in the agenda, where the assertion of
  -- the lookup would fail.
  local ok, current = pcall(function()
    return files:get_current_file()
  end)
  if not ok then
    current = nil
  end
  local orgfiles = current and { current } or files:all()

  for _, orgfile in ipairs(orgfiles) do
    for name in pairs(orgfile:get_directive_properties() or {}) do
      add(name)
    end
    local headlines = current and orgfile:get_headlines() or orgfile:get_opened_headlines()
    for _, headline in ipairs(headlines or {}) do
      for name in pairs(headline:get_own_properties() or {}) do
        add(name)
      end
    end
  end

  table.sort(names)
  return names
end

---@param context OrgCompletionContext
---@return number | nil
function Completion:get_start(context)
  if not self.directive_pattern:match_str(context.line) then
    -- The keyword itself, e.g. `#+col` or `:COL`.
    if self.keyword_pattern:match_str(context.line) or self.property_pattern:match_str(context.line) then
      local prefix = context.line:match('^(.-)%S*$')
      return #prefix
    end
    return nil
  end

  -- The spec is a list of whitespace separated tokens; complete the last one.
  local prefix = context.line:match('^(.-)%S*$')
  return #prefix
end

---@param context OrgCompletionContext
---@return string[]
function Completion:get_results(context)
  local base = context.base or ''

  -- The `#+columns:` keyword and the `:COLUMNS:` property itself.
  if not self.directive_pattern:match_str(context.line) then
    if base:lower():find('#+col', 1, true) == 1 then
      return { '#+columns' }
    end
    if base:lower():find(':col', 1, true) == 1 and self.property_pattern:match_str(context.line) then
      return { ':COLUMNS:' }
    end
    return {}
  end

  -- When a token is opened with `{`, offer the summary forms for it, e.g.
  -- `%Effort{` -> `%Effort{+}`.
  local name = base:match('^([^{]*){$')
  if name then
    local results = {}
    for _, summary_type in ipairs(SUMMARY_TYPES) do
      table.insert(results, name .. '{' .. summary_type .. '}')
    end
    return results
  end

  -- A token can carry a width before its name (`%24ITEM`); keep it so that
  -- completing the name does not drop the width.
  local width = base:match('^(%%%d*)')
  local function with_width(candidate)
    if not width then
      return candidate
    end
    return width .. candidate:sub(2)
  end

  -- The special columns and the properties that are in use.
  local results = {}
  for _, column in ipairs(COLUMN_KEYWORDS) do
    table.insert(results, with_width(column))
  end
  for _, property in ipairs(self:_property_names()) do
    local candidate = with_width(property)
    if not vim.tbl_contains(results, candidate) then
      table.insert(results, candidate)
    end
  end

  return results
end

return Completion
