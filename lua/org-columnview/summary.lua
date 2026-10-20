local Duration = require('orgmode.objects.duration')

---@class OrgColumnSummary
local Summary = {}

local SUMMARY_TYPES = {
  ['+'] = 'sum',
  [':'] = 'sum_time',
  [':min'] = 'min_time',
  [':max'] = 'max_time',
  [':mean'] = 'mean_time',
  ['min'] = 'min',
  ['max'] = 'max',
  ['mean'] = 'mean',
  ['X'] = 'checkbox_all',
  ['X/'] = 'checkbox_fraction',
  ['X%'] = 'checkbox_percent',
  ['@min'] = 'min_age',
  ['@max'] = 'max_age',
  ['@mean'] = 'age_mean',
  ['est+'] = 'estimate_sum',
}

---@param summary_type string
---@return string|nil
function Summary.get_summary_function(summary_type)
  if not summary_type then
    return nil
  end
  if summary_type:match('^%+;') then
    return 'sum_format'
  end
  if summary_type == '$' then
    return 'sum_format'
  end
  return SUMMARY_TYPES[summary_type]
end

---@param values string[]
---@param summary_type string
---@return string|nil
function Summary.compute(values, summary_type)
  local func = Summary.get_summary_function(summary_type)
  if not func then
    return nil
  end

  if func == 'sum' then
    return Summary._sum(values)
  elseif func == 'sum_time' then
    return Summary._sum_time(values)
  elseif func == 'min_time' then
    return Summary._extreme_time(values, 'min')
  elseif func == 'max_time' then
    return Summary._extreme_time(values, 'max')
  elseif func == 'mean_time' then
    return Summary._mean_time(values)
  elseif func == 'sum_format' then
    local format = summary_type:match('^%+;(.+)$') or '%.2f'
    return Summary._sum_format(values, format)
  elseif func == 'min' then
    return Summary._min(values)
  elseif func == 'max' then
    return Summary._max(values)
  elseif func == 'mean' then
    return Summary._mean(values)
  elseif func == 'checkbox_all' then
    return Summary._checkbox_all(values)
  elseif func == 'checkbox_fraction' then
    return Summary._checkbox_fraction(values)
  elseif func == 'checkbox_percent' then
    return Summary._checkbox_percent(values)
  elseif func == 'min_age' then
    return Summary._extreme_age(values, 'min')
  elseif func == 'max_age' then
    return Summary._extreme_age(values, 'max')
  elseif func == 'age_mean' then
    return Summary._age_mean(values)
  elseif func == 'estimate_sum' then
    return Summary._estimate_sum(values)
  end

  return nil
end

function Summary._to_number(str)
  if not str or str == '' then
    return nil
  end
  local num = tonumber(str)
  if num then
    return num
  end

  local duration = Duration.parse(str)
  if duration then
    return duration.minutes
  end

  return nil
end

function Summary._sum(values)
  local total = 0
  local has_values = false
  for _, v in ipairs(values) do
    local num = Summary._to_number(v)
    if num then
      total = total + num
      has_values = true
    end
  end
  if not has_values then
    return nil
  end
  return tostring(total)
end

function Summary._sum_time(values)
  local total = 0
  local has_values = false
  for _, v in ipairs(values) do
    local num = Summary._to_number(v)
    if num then
      total = total + num
      has_values = true
    end
  end
  if not has_values then
    return nil
  end
  return Duration.from_minutes(total):to_string('HH:MM')
end

function Summary._extreme_time(values, mode)
  local result = nil
  for _, v in ipairs(values) do
    local num = Summary._to_number(v)
    if num then
      if not result or (mode == 'min' and num < result) or (mode == 'max' and num > result) then
        result = num
      end
    end
  end
  if not result then
    return nil
  end
  return Duration.from_minutes(result):to_string('HH:MM')
end

function Summary._mean_time(values)
  local total = 0
  local count = 0
  for _, v in ipairs(values) do
    local num = Summary._to_number(v)
    if num then
      total = total + num
      count = count + 1
    end
  end
  if count == 0 then
    return nil
  end
  return Duration.from_minutes(math.floor(total / count)):to_string('HH:MM')
end

function Summary._sum_format(values, format)
  local total = 0
  local has_values = false
  for _, v in ipairs(values) do
    local num = Summary._to_number(v)
    if num then
      total = total + num
      has_values = true
    end
  end
  if not has_values then
    return nil
  end
  return string.format(format, total)
end

function Summary._min(values)
  local min_val = nil
  for _, v in ipairs(values) do
    local num = Summary._to_number(v)
    if num then
      if not min_val or num < min_val then
        min_val = num
      end
    end
  end
  return min_val and tostring(min_val) or nil
end

function Summary._max(values)
  local max_val = nil
  for _, v in ipairs(values) do
    local num = Summary._to_number(v)
    if num then
      if not max_val or num > max_val then
        max_val = num
      end
    end
  end
  return max_val and tostring(max_val) or nil
end

function Summary._mean(values)
  local sum = 0
  local count = 0
  for _, v in ipairs(values) do
    local num = Summary._to_number(v)
    if num then
      sum = sum + num
      count = count + 1
    end
  end
  if count == 0 then
    return nil
  end
  return tostring(sum / count)
end

function Summary._checkbox_all(values)
  local done = 0
  local total = 0
  for _, v in ipairs(values) do
    local checkbox = v:match('%[(.)%]')
    if checkbox then
      total = total + 1
      if checkbox:upper() == 'X' then
        done = done + 1
      end
    end
  end
  if done == total then
    return '[X]'
  elseif done > 0 then
    return '[-]'
  end
  return '[ ]'
end

function Summary._checkbox_percent(values)
  local done = 0
  local total = 0
  for _, v in ipairs(values) do
    local checkbox = v:match('%[(.)%]')
    if checkbox then
      total = total + 1
      if checkbox:upper() == 'X' then
        done = done + 1
      end
    end
  end
  if total == 0 then
    return nil
  end
  return string.format('[%d%%]', math.floor(100 * done / total + 0.5))
end

function Summary._checkbox_fraction(values)
  local total = 0
  local checked = 0
  for _, v in ipairs(values) do
    local checkbox = v:match('%[(.)%]')
    if checkbox then
      total = total + 1
      if checkbox:upper() == 'X' then
        checked = checked + 1
      end
    end
  end
  if total == 0 then
    return nil
  end
  return string.format('[%d/%d]', checked, total)
end

---Minimum or maximum age of the given age/duration values, formatted as a duration.
---@param values string[]
---@param mode 'min'|'max'
---@return string|nil
function Summary._extreme_age(values, mode)
  local result = nil
  for _, v in ipairs(values) do
    local num = Summary._to_number(v)
    if num then
      if not result or (mode == 'min' and num < result) or (mode == 'max' and num > result) then
        result = num
      end
    end
  end
  if not result then
    return nil
  end
  return Duration.from_minutes(result):to_string()
end

---Mean age of the given age/duration values, formatted as a duration.
---@param values string[]
---@return string|nil
function Summary._age_mean(values)
  local total = 0
  local count = 0
  for _, v in ipairs(values) do
    local num = Summary._to_number(v)
    if num then
      total = total + num
      count = count + 1
    end
  end
  if count == 0 then
    return nil
  end
  return Duration.from_minutes(math.floor(total / count)):to_string()
end

function Summary._estimate_sum(values)
  local min_sum = 0
  local max_sum = 0
  local has_values = false
  for _, v in ipairs(values) do
    local low, high = v:match('(%d+)%s*[-~]%s*(%d+)')
    if low and high then
      min_sum = min_sum + tonumber(low)
      max_sum = max_sum + tonumber(high)
      has_values = true
    else
      local num = tonumber(v)
      if num then
        min_sum = min_sum + num
        max_sum = max_sum + num
        has_values = true
      end
    end
  end
  if not has_values then
    return nil
  end
  return string.format('%d-%d', min_sum, max_sum)
end

return Summary
