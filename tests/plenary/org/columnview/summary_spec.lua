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
