---Completion of the column format in a `#+COLUMNS:` keyword or a `:COLUMNS:`
---property.
---@class OrgColumnViewColumnsCompletion:OrgCompletionSource
---@field private directive_pattern vim.regex
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

function Completion:new()
  return setmetatable({
    directive_pattern = vim.regex([[\c^\s*\(\#+columns:\|:columns:\)\s]]),
    keyword_pattern = vim.regex([[\c^\s*\#+\?\w*$]]),
    property_pattern = vim.regex([[\c^\s*:\w*$]]),
  }, Completion)
end

function Completion:get_name()
  return 'columnview_columns'
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

  return COLUMN_KEYWORDS
end

return Completion
