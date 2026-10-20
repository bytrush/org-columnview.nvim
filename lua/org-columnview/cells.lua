local Date = require('orgmode.objects.date')
local Duration = require('orgmode.objects.duration')
local Summary = require('org-columnview.summary')
local utils = require('orgmode.utils')
local columnview_config = require('org-columnview.config')

---Compute and render individual column values shared between the overlay
---column view (org buffer) and the agenda column view.
---@class OrgColumnCells
---@field private _clocksum_cache table
---@field private _clocksum_t_cache table
local Cells = {}
Cells.__index = Cells

function Cells:new()
  return setmetatable({
    _clocksum_cache = {},
    _clocksum_t_cache = {},
  }, Cells)
end

---Reset memoized clock sums, e.g. after the underlying data changes.
function Cells:clear_cache()
  self._clocksum_cache = {}
  self._clocksum_t_cache = {}
end

---Display value of a single column for a headline.
---@param headline OrgHeadline
---@param column OrgColumnSpec
---@return string
function Cells:get_value(headline, column)
  if column.is_special then
    return self:get_special_value(headline, column.name)
  end
  local prop = headline:get_property(column.name:lower())
  return prop or ''
end

---@param headline OrgHeadline
---@param name string
---@return string
function Cells:get_special_value(headline, name)
  if name == 'ITEM' then
    local indent = string.rep('  ', headline:get_level() - 1)
    local todo = headline:get_todo() or ''
    local title = headline:get_title()
    if todo ~= '' then
      title = todo .. ' ' .. title
    end
    local priority = headline:get_priority()
    if priority ~= '' then
      title = '[#' .. priority .. '] ' .. title
    end
    return indent .. title
  elseif name == 'CLOCKSUM' then
    return self:get_clocksum(headline, false)
  elseif name == 'CLOCKSUM_T' then
    return self:get_clocksum(headline, true)
  elseif name == 'AGE' then
    local created = headline:get_property('CREATED')
    if created then
      local d = Date.from_string(created)
      if d then
        local minutes = math.max(0, math.floor((os.time() - d.timestamp) / 60))
        return Duration.from_minutes(minutes):to_string()
      end
    end
    return ''
  elseif name == 'TAGS' then
    return headline:tags_to_string()
  elseif name == 'ALLTAGS' then
    return self:get_all_tags(headline)
  elseif name == 'TODO' then
    return headline:get_todo() or ''
  elseif name == 'PRIORITY' then
    local p = headline:get_priority()
    return p ~= '' and ('[#' .. p .. ']') or ''
  elseif name == 'CATEGORY' then
    return headline:get_category()
  elseif name == 'SCHEDULED' then
    local scheduled = headline:get_scheduled_date()
    if scheduled then
      return scheduled:to_date_string()
    end
    return ''
  elseif name == 'DEADLINE' then
    local deadline = headline:get_deadline_date()
    if deadline then
      return deadline:to_date_string()
    end
    return ''
  elseif name == 'CLOSED' then
    local closed = headline:get_closed_date()
    if closed then
      return closed:to_date_string()
    end
    return ''
  elseif name == 'TIMESTAMP' then
    local date = headline:get_non_plan_dates()[1]
    if date then
      return date:to_date_string()
    end
    return ''
  elseif name == 'TIMESTAMP_IA' then
    for _, date in ipairs(headline:get_non_plan_dates()) do
      if date.active == false then
        return date:to_date_string()
      end
    end
    return ''
  elseif name == 'FILE' then
    return vim.fn.fnamemodify(headline.file.filename, ':t')
  elseif name == 'BLOCKED' then
    return self:is_blocked(headline) and 't' or ''
  end
  return ''
end

---All tags of a headline, including inherited and file-level tags.
---Unlike the `TAGS` special column this ignores `org_use_tag_inheritance`.
---@param headline OrgHeadline
---@return string
function Cells:get_all_tags(headline)
  local tags = {}
  local own_tags = headline:get_own_tags()
  local parent = headline:get_parent_headline()
  while parent do
    utils.concat(tags, parent:get_own_tags())
    parent = parent:get_parent_headline()
  end
  utils.concat(tags, headline.file:get_filetags())
  utils.concat(tags, own_tags)
  return vim.tbl_isempty(tags) and '' or utils.tags_to_string(tags, true)
end

---Whether a headline is currently blocked, mirroring `org-entry-blocked-p`.
---A not-done TODO is blocked when it has unfinished children or when it has an
---unfinished sibling and its parent is marked with the `ORDERED` property.
---@param headline OrgHeadline
---@return boolean
function Cells:is_blocked(headline)
  if not headline:is_todo() then
    return false
  end
  if headline:get_property('NOBLOCKING', false) then
    return false
  end
  for _, child in ipairs(headline:get_child_headlines()) do
    if not child:is_done() then
      return true
    end
  end
  local parent = headline:get_parent_headline()
  if parent and parent:get_property('ORDERED', false) ~= nil then
    for _, sibling in ipairs(parent:get_child_headlines()) do
      if not sibling:is_same(headline) and not sibling:is_done() then
        return true
      end
    end
  end
  return false
end

---@param headline OrgHeadline
---@param today_only boolean
---@return string
function Cells:get_clocksum(headline, today_only)
  local total_minutes = self:compute_clocksum(headline, today_only)
  if total_minutes <= 0 then
    return ''
  end
  return Duration.from_minutes(total_minutes):to_string('HH:MM')
end

---@param headline OrgHeadline
---@param today_only boolean
---@return number
function Cells:compute_clocksum(headline, today_only)
  local cache = today_only and self._clocksum_t_cache or self._clocksum_cache
  local cached = cache[headline]
  if cached ~= nil then
    return cached
  end

  local total_minutes = 0
  local logbook = headline:get_logbook()
  if logbook then
    if today_only then
      local from = Date.today():start_of('day')
      local to = Date.today():end_of('day')
      total_minutes = total_minutes + logbook:get_total_minutes(from, to)
      local active = logbook:get_active()
      if active and active.start_time:is_today() then
        total_minutes = total_minutes + math.floor((Date.now().timestamp - active.start_time.timestamp) / 60)
      end
    else
      total_minutes = total_minutes + logbook:get_total_with_active().minutes
    end
  end

  for _, child in ipairs(headline:get_child_headlines()) do
    total_minutes = total_minutes + self:compute_clocksum(child, today_only)
  end

  cache[headline] = total_minutes
  return total_minutes
end

---Pad or truncate `text` to exactly `width` display columns.
---@param text string
---@param width number
---@return string
function Cells.fit(text, width)
  local display_width = vim.api.nvim_strwidth(text)
  if display_width > width then
    local truncated = ''
    local used = 0
    local char_count = vim.fn.strchars(text)
    for i = 0, char_count - 1 do
      local char = vim.fn.strcharpart(text, i, 1)
      local char_width = vim.api.nvim_strwidth(char)
      if used + char_width > width - 1 then
        break
      end
      used = used + char_width
      truncated = truncated .. char
    end
    text = truncated .. '…'
    display_width = vim.api.nvim_strwidth(text)
  end
  return text .. string.rep(' ', width - display_width)
end

---Compute display widths of columns, fitting titles and cell content.
---@param columns OrgColumnSpec[]
---@param content fun(headline: OrgHeadline, column: OrgColumnSpec): string
---@param headlines OrgHeadline[]
---@return number[]
function Cells.compute_widths(columns, content, headlines)
  local widths = {}
  for col_idx, col in ipairs(columns) do
    local width = col.width or math.max(vim.api.nvim_strwidth(col.title or ''), 10)
    if not col.width then
      for _, headline in ipairs(headlines) do
        local value = content(headline, col)
        width = math.max(width, vim.api.nvim_strwidth(type(value) == 'string' and value or ''))
      end
    end
    widths[col_idx] = math.min(width, 50)
  end
  return widths
end

---@param values string[]
---@param summary_type string
---@return string|nil
function Cells.compute_summary(values, summary_type)
  return Summary.compute(values, summary_type)
end

---Apply `org_columns_modify_value_for_display_function` to a value before it is
---rendered, like Emacs' `org-columns-modify-value-for-display-function`. The
---function receives the column title and the value, and should return the text
---to display (or nil to keep the original value).
---@param column string|nil
---@param value string
---@return string
function Cells.modify_value_for_display(column, value)
  local fn = columnview_config.modify_value_for_display_function
  if type(fn) == 'function' then
    local modified = fn(column, value)
    if modified ~= nil then
      return modified
    end
  end
  return value
end

return Cells
