local Summary = require('org-columnview.summary')

describe('Column Summary', function()
  it('sums plain numbers', function()
    assert.are.equal('6', Summary.compute({ '1', '2', '3' }, '+'))
  end)

  it('sums duration values in HH:MM format', function()
    assert.are.equal('90', Summary.compute({ '0:30', '1:00' }, '+'))
  end)

  it('sums mixed numbers and durations', function()
    assert.are.equal('90', Summary.compute({ '30', '1:00' }, '+'))
  end)

  it('sums duration values with a custom format', function()
    assert.are.equal('90.00', Summary.compute({ '0:30', '1:00' }, '+;%.2f'))
  end)

  it('sums values with the "$" currency shorthand', function()
    assert.are.equal('90.00', Summary.compute({ '0:30', '1:00' }, '$'))
    assert.are.equal('12.50', Summary.compute({ '10', '2.5' }, '$'))
  end)

  it('sums duration values and formats them as time with ":"', function()
    assert.are.equal('1:30', Summary.compute({ '0:30', '1:00' }, ':'))
    assert.are.equal('4:52', Summary.compute({ '2:00', '2:30', '0:01', '0:01', '0:20' }, ':'))
  end)

  it('returns nil for ":" when there are no numeric values', function()
    assert.is_nil(Summary.compute({ 'foo' }, ':'))
  end)

  it('computes min and max in minutes', function()
    assert.are.equal('30', Summary.compute({ '0:30', '1:00', '2:00' }, 'min'))
    assert.are.equal('120', Summary.compute({ '0:30', '1:00', '2:00' }, 'max'))
  end)

  it('computes mean in minutes', function()
    assert.are.equal('60', Summary.compute({ '0:00', '1:00', '2:00' }, 'mean'))
  end)

  it('formats min, max and mean summaries', function()
    assert.are.equal('30.0', Summary.compute({ '0:30', '1:00' }, 'min', '%.1f'))
    assert.are.equal('120.00', Summary.compute({ '0:30', '1:00', '2:00' }, 'max', '%.2f'))
    assert.are.equal('60.00', Summary.compute({ '0:00', '1:00', '2:00' }, 'mean', '%.2f'))
  end)

  it('formats a sum when the format is passed separately', function()
    assert.are.equal('90.00', Summary.compute({ '0:30', '1:00' }, '+', '%.2f'))
  end)

  it('uses a configured custom summary operator', function()
    local columnview_config = require('org-columnview.config')
    local original = columnview_config.opts.summary_types
    columnview_config.opts.summary_types = {
      join = function(values, format)
        return table.concat(values, format or ',')
      end,
    }

    assert.are.equal('A|B', Summary.compute({ 'A', 'B' }, 'join', '|'))
    assert.are.equal('A,B', Summary.compute({ 'A', 'B' }, 'join'))
    assert.is_true(Summary.is_summary_type('join'))
    assert.is_truthy(vim.tbl_contains(Summary.get_summary_types(), 'join'))

    columnview_config.opts.summary_types = original
  end)

  it('returns nil when there are no numeric values', function()
    assert.is_nil(Summary.compute({ 'foo', 'bar' }, '+'))
  end)

  it('computes checkbox summaries', function()
    assert.are.equal('[X]', Summary.compute({ '[X]', '[X]' }, 'X'))
    assert.are.equal('[-]', Summary.compute({ '[X]', '[ ]' }, 'X'))
    assert.are.equal('[ ]', Summary.compute({ '[ ]', '[ ]' }, 'X'))
    assert.are.equal('[1/2]', Summary.compute({ '[X]', '[ ]' }, 'X/'))
  end)

  it('computes checkbox percentage summaries', function()
    assert.are.equal('[100%]', Summary.compute({ '[X]', '[X]' }, 'X%'))
    assert.are.equal('[50%]', Summary.compute({ '[X]', '[ ]' }, 'X%'))
    assert.are.equal('[0%]', Summary.compute({ '[ ]', '[ ]' }, 'X%'))
    assert.is_nil(Summary.compute({ 'foo' }, 'X%'))
  end)

  it('computes min, max and mean time summaries', function()
    assert.are.equal('0:30', Summary.compute({ '0:30', '1:00', '2:00' }, ':min'))
    assert.are.equal('2:00', Summary.compute({ '0:30', '1:00', '2:00' }, ':max'))
    assert.are.equal('1:00', Summary.compute({ '0:30', '1:30' }, ':mean'))
    assert.is_nil(Summary.compute({ 'foo' }, ':min'))
    assert.is_nil(Summary.compute({ 'foo' }, ':mean'))
  end)

  it('counts checkbox cookies in X/ and X% summaries', function()
    assert.are.equal('[2/2]', Summary.compute({ '[X]', '[1/1]' }, 'X/'))
    assert.are.equal('[1/2]', Summary.compute({ '[ ]', '[2/2]' }, 'X/'))
    assert.are.equal('[50%]', Summary.compute({ '[100%]', '[ ]' }, 'X%'))
    -- A fraction cookie is not done for X% and vice versa.
    assert.are.equal('[0/1]', Summary.compute({ '[100%]' }, 'X/'))
    assert.are.equal('[0%]', Summary.compute({ '[1/1]' }, 'X%'))
  end)

  it('converts timestamps to age in minutes', function()
    local now = os.time({ year = 2026, month = 11, day = 1, hour = 10, min = 0 })
    assert.are.equal(600, Summary.age_to_minutes('<2026-11-01 Sun>', now))
    assert.are.equal(120, Summary.age_to_minutes('[2026-11-01 Sun 08:00]', now))
    assert.are.equal(120, Summary.age_to_minutes('2:00', now))
    assert.is_nil(Summary.age_to_minutes('not an age', now))
  end)

  it('computes @min and @max ages from timestamps', function()
    local now = os.time()
    local one_hour_ago = os.date('%Y-%m-%d %a %H:%M', now - 3600)
    local two_hours_ago = os.date('%Y-%m-%d %a %H:%M', now - 7200)
    local values = { ('<%s>'):format(one_hour_ago), ('<%s>'):format(two_hours_ago) }
    assert.are.equal('1:00', Summary.compute(values, '@min'))
    assert.are.equal('2:00', Summary.compute(values, '@max'))
  end)

  it('computes min and max age summaries', function()
    assert.are.equal('0:30', Summary.compute({ '0:30', '1:00', '2:00' }, '@min'))
    assert.are.equal('2:00', Summary.compute({ '0:30', '1:00', '2:00' }, '@max'))
    assert.is_nil(Summary.compute({ 'foo' }, '@min'))
  end)

  it('computes estimate sums', function()
    assert.are.equal('3-5', Summary.compute({ '1-2', '2-3' }, 'est+'))
  end)

  it('computes the mean age as a duration for "@mean"', function()
    assert.are.equal('0:45', Summary.compute({ '0:30', '1:00' }, '@mean'))
    assert.are.equal('1:00', Summary.compute({ '0:30', '1:30' }, '@mean'))
  end)
end)
