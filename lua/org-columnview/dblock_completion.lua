---Completion for `#+BEGIN: columnview` dynamic blocks.
---
---Suggests the block name, its parameters, and the common parameter values.
---@class OrgColumnViewDblockCompletion:OrgCompletionSource
---@field private completion OrgCompletion
local Completion = {}
Completion.__index = Completion

local PARAMETERS = {
  ':id',
  ':format',
  ':hlines',
  ':indent',
  ':match',
  ':maxlevel',
  ':skip-empty-rows',
  ':vlines',
  ':link',
  ':exclude-tags',
  ':formatter',
}

---@param opts { completion: OrgCompletion }
function Completion:new(opts)
  return setmetatable({
    completion = opts.completion,
  }, Completion)
end

function Completion:get_name()
  return 'columnview_dblock'
end

---@param value string
---@param prefix string
---@return boolean
local function starts_with(value, prefix)
  return value:sub(1, #prefix):lower() == prefix:lower()
end

---@param context OrgCompletionContext
---@return number|nil
function Completion:get_start(context)
  local lower = context.line:lower()
  if lower:match('^%s*#%+begin:') then
    local prefix = context.line:match('^(.-)%S*$')
    return #prefix
  end

  -- Suggest the whole block header while the user is typing `#+BE...`.
  if lower:match('^%s*#%+b') and not lower:find(':', 1, true) then
    local prefix = context.line:match('^(%s*)#%+') or ''
    return #prefix
  end

  return nil
end

---@return string[]
function Completion:_entry_ids()
  local ids = { 'local', 'global' }
  local ok, file = pcall(function()
    return self.completion.files:get_current_file()
  end)
  if not ok or not file then
    return ids
  end
  for _, headline in ipairs(file:get_headlines()) do
    local id = headline:get_property('ID', false)
    if id and id ~= '' and not vim.tbl_contains(ids, id) then
      table.insert(ids, id)
    end
  end
  return ids
end

---@param line string
---@param base string
---@return string[]
function Completion:_parameter_values(line, base)
  local before = line:sub(1, #line - #base)
  local key = before:match(':(%S+)%s+$')
  if not key then
    return {}
  end
  key = key:lower():gsub('%-', '_')

  local values = {}
  if key == 'id' then
    values = self:_entry_ids()
  elseif key == 'hlines' then
    values = { '1', 't' }
  elseif key == 'indent' or key == 'link' or key == 'vlines' or key == 'skip_empty_rows' then
    values = { 't' }
  elseif key == 'maxlevel' then
    values = { '1', '2', '3', '4', '5' }
  elseif key == 'match' or key == 'exclude_tags' then
    local ok, file = pcall(function()
      return self.completion.files:get_current_file()
    end)
    if ok and file then
      values = file:get_tags()
    end
  end

  return vim.tbl_filter(function(value)
    return starts_with(value, base)
  end, values)
end

---@param context OrgCompletionContext
---@return string[]
function Completion:get_results(context)
  local base = context.base or ''
  local after_begin = context.line:match('^%s*#%+[Bb][Ee][Gg][Ii][Nn]:%s*(.*)$')
  if not after_begin then
    if starts_with('#+BEGIN: columnview', base) then
      return { '#+BEGIN: columnview' }
    end
    return {}
  end

  if not after_begin:lower():match('^columnview') then
    if starts_with('columnview', base) then
      return { 'columnview' }
    end
    return {}
  end

  if base == '' or base:sub(1, 1) == ':' then
    return vim.tbl_filter(function(parameter)
      return starts_with(parameter, base)
    end, PARAMETERS)
  end

  return self:_parameter_values(context.line, base)
end

return Completion
