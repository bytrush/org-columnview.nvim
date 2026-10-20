local helpers = require('tests.plenary.helpers')
local org = require('orgmode')

describe('Column View Completion', function()
  -- The plugin registers its completion sources on the current orgmode
  -- instance, so it has to be set up after the org files are created.
  local function setup_plugin()
    require('org-columnview').setup()
  end

  local function setup_file(content)
    -- The trailing space is needed, because the completion only looks at the
    -- text up to the cursor.
    helpers.create_agenda_file({ content .. ' ' })
    setup_plugin()
    vim.cmd('normal! A')
  end

  it('completes the column format of a COLUMNS property', function()
    setup_file(':COLUMNS: ')
    local result = org.completion:omnifunc(0, '')
    assert.are.same({
      { menu = '[Org]', word = '%ITEM' },
      { menu = '[Org]', word = '%TODO' },
      { menu = '[Org]', word = '%PRIORITY' },
      { menu = '[Org]', word = '%TAGS' },
      { menu = '[Org]', word = '%ALLTAGS' },
      { menu = '[Org]', word = '%CATEGORY' },
      { menu = '[Org]', word = '%SCHEDULED' },
      { menu = '[Org]', word = '%DEADLINE' },
      { menu = '[Org]', word = '%CLOSED' },
      { menu = '[Org]', word = '%CLOCKSUM' },
      { menu = '[Org]', word = '%CLOCKSUM_T' },
      { menu = '[Org]', word = '%AGE' },
      { menu = '[Org]', word = '%FILE' },
      { menu = '[Org]', word = '%BLOCKED' },
      { menu = '[Org]', word = '%TIMESTAMP' },
      { menu = '[Org]', word = '%TIMESTAMP_IA' },
    }, result)
  end)

  it('completes the summary types of a column', function()
    setup_file(':COLUMNS: %Effort{')
    local result = org.completion:omnifunc(0, '%Effort{')
    assert.are.same({
      { menu = '[Org]', word = '%Effort{+}' },
      { menu = '[Org]', word = '%Effort{:}' },
      { menu = '[Org]', word = '%Effort{:min}' },
      { menu = '[Org]', word = '%Effort{:max}' },
      { menu = '[Org]', word = '%Effort{:mean}' },
      { menu = '[Org]', word = '%Effort{$}' },
      { menu = '[Org]', word = '%Effort{min}' },
      { menu = '[Org]', word = '%Effort{max}' },
      { menu = '[Org]', word = '%Effort{mean}' },
      { menu = '[Org]', word = '%Effort{X}' },
      { menu = '[Org]', word = '%Effort{X/}' },
      { menu = '[Org]', word = '%Effort{X%}' },
      { menu = '[Org]', word = '%Effort{@min}' },
      { menu = '[Org]', word = '%Effort{@max}' },
      { menu = '[Org]', word = '%Effort{@mean}' },
      { menu = '[Org]', word = '%Effort{est+}' },
      { menu = '[Org]', word = '%Effort{+;%.2f}' },
    }, result)
  end)

  it('completes property values from an entry NAME_ALL property', function()
    helpers.create_agenda_file({
      '* Task',
      ':PROPERTIES:',
      ':OWNER_ALL: Alice, Bob',
      ':OWNER:  ',
      ':END:',
    })
    setup_plugin()
    vim.api.nvim_win_set_cursor(0, { 4, 0 })
    vim.cmd('normal! A')
    local result = org.completion:omnifunc(0, '')
    assert.are.same({
      { menu = '[Org]', word = 'Alice' },
      { menu = '[Org]', word = 'Bob' },
    }, result)
  end)

  it('completes property values from a file level PROPERTY keyword', function()
    helpers.create_agenda_file({
      '#+PROPERTY: POINTS_ALL 1 2 3 5 8',
      '',
      '* Task',
      ':PROPERTIES:',
      ':POINTS:  ',
      ':END:',
    })
    setup_plugin()
    vim.api.nvim_win_set_cursor(0, { 5, 0 })
    vim.cmd('normal! A')
    local result = org.completion:omnifunc(0, '')
    assert.are.same({
      { menu = '[Org]', word = '1' },
      { menu = '[Org]', word = '2' },
      { menu = '[Org]', word = '3' },
      { menu = '[Org]', word = '5' },
      { menu = '[Org]', word = '8' },
    }, result)
  end)

  it('completes property values from inline COLUMNS allowed values', function()
    helpers.create_agenda_file({
      '#+COLUMNS: %25ITEM %5POINTS{1,2,3,4,5}',
      '',
      '* Task',
      ':PROPERTIES:',
      ':POINTS:  ',
      ':END:',
    })
    setup_plugin()
    vim.api.nvim_win_set_cursor(0, { 5, 0 })
    vim.cmd('normal! A')
    local result = org.completion:omnifunc(0, '')
    assert.are.same({
      { menu = '[Org]', word = '1' },
      { menu = '[Org]', word = '2' },
      { menu = '[Org]', word = '3' },
      { menu = '[Org]', word = '4' },
      { menu = '[Org]', word = '5' },
    }, result)
  end)
end)
