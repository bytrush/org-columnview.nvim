---Completion of the allowed values of a property.
---
---Mirrors the column view: inline values from the resolved `COLUMNS` format
---(`%NAME{1,2,3}`) take precedence, otherwise a `NAME_ALL` property is looked
---up on the current entry, its ancestors and the file-wide
---`#+PROPERTY: NAME_ALL ...` / `#+NAME_ALL: ...` keywords.
local Parser = require('org-columnview.parser')
local compat = require('org-columnview.compat')

---@class OrgColumnViewCompletion:OrgCompletionSource
---@field private completion OrgCompletion
local Completion = {}
Completion.__index = Completion

---@param opts { completion: OrgCompletion }
function Completion:new(opts)
  return setmetatable({
    completion = opts.completion,
  }, Completion)
end

function Completion:get_name()
  return 'columnview_property_values'
end

---Resolve the allowed values of the property `NAME`.
---@private
---@param headline OrgHeadline
---@param name string upper case property name
---@return string[]
function Completion:_allowed_values_for(headline, name)
  local prop_key = name .. '_ALL'
  local columns_def = Parser.get_columns_for_headline(headline)
  local inline = columns_def and columns_def.allowed_values and columns_def.allowed_values[prop_key]
  if inline and not (#inline == 1 and not inline[1]:match('^%[')) then
    return inline
  end

  local prop_name = name:lower() .. '_all'
  local value = headline:get_property(prop_name)
  if not value or value == '' then
    value = compat.get_keyword_property(headline.file, prop_name)
  end
  if value and value ~= '' then
    return Parser.split_allowed_values(value)
  end

  return {}
end

---@private
---@param name string upper case property name
---@return fun(): string[]
function Completion:_name_all_source(name)
  local completion = self.completion
  return function()
    local headline = completion.files:get_closest_headline_or_nil()
    if not headline then
      return {}
    end

    return self:_allowed_values_for(headline, name)
  end
end

---@private
---@param line string
---@return (fun(): string[])|nil
function Completion:_value_source(line)
  local name = line:match('^%s*:([%w_]+):%s')
  if not name then
    return nil
  end

  local upper = name:upper()
  -- `:COLUMNS:` holds a column format, not a property value; it is completed
  -- by the source in `columns_completion.lua`. Claiming it here would make the
  -- shared completion start point before the format, so only the first column
  -- token could be completed.
  if upper == 'PROPERTIES' or upper == 'END' or upper == 'LOGBOOK' or upper == 'STYLE' or upper == 'COLUMNS' then
    return nil
  end

  return self:_name_all_source(upper)
end

---@param context OrgCompletionContext
---@return number | nil
function Completion:get_start(context)
  if not self:_value_source(context.line) then
    return nil
  end

  -- The value is everything after the property name, so complete the whole
  -- tail (values can contain spaces).
  local prefix = context.line:match('^(%s*:[%S]+:%s*)')
  return prefix and #prefix or nil
end

---@param context OrgCompletionContext
---@return string[]
function Completion:get_results(context)
  local value_source = self:_value_source(context.line)
  if not value_source then
    return {}
  end

  return value_source()
end

return Completion
