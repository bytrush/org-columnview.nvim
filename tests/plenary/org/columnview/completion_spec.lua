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

  it('completes the #+columns keyword', function()
    setup_file('#+col')
    local result = org.completion:omnifunc(0, '#+col')
    assert.are.same({
      { menu = '[Org]', word = '#+columns' },
    }, result)
  end)

  it('completes the COLUMNS property', function()
    setup_file(':COL')
    local result = org.completion:omnifunc(0, ':COL')
    assert.are.same({
      { menu = '[Org]', word = ':COLUMNS:' },
    }, result)
  end)

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

  it('completes the column format of a COLUMNS property in a drawer', function()
    helpers.create_agenda_file({
      '* Task',
      '  :PROPERTIES:',
      '  :COLUMNS: %',
      '  :END:',
    })
    setup_plugin()
    vim.api.nvim_win_set_cursor(0, { 3, 0 })
    vim.cmd('normal! A')
    local result = org.completion:omnifunc(0, '%')
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
      -- The property of the drawer is completed as well.
      { menu = '[Org]', word = '%COLUMNS' },
    }, result)
  end)

  it('completes the column format with the properties that are in use', function()
    local fname = vim.fn.tempname() .. '.org'
    vim.fn.writefile({
      '* Task',
      '  :PROPERTIES:',
      '  :EFFORT: 5',
      '  :POINTS: 3',
      '  :END:',
      '* Other',
      '  :PROPERTIES:',
      '  :OWNER: Bob',
      '  :END:',
    }, fname)
    vim.cmd.edit(fname)
    setup_plugin()

    local function complete(line)
      vim.api.nvim_buf_set_lines(0, 5, 5, false, { line })
      vim.api.nvim_win_set_cursor(0, { 6, 0 })
      vim.cmd('normal! A')
      -- Derive the base from the start position, like Vim does, so that a
      -- source claiming an earlier start cannot be hidden by a hand-made base.
      local start = org.completion:omnifunc(1, '')
      return org.completion:omnifunc(0, line:sub(start + 1))
    end

    assert.are.same({ { menu = '[Org]', word = '%EFFORT' } }, complete(':COLUMNS: %ITEM %EFF'))
    assert.are.same({ { menu = '[Org]', word = '%POINTS' } }, complete(':COLUMNS: %ITEM %POI'))
    assert.are.same({ { menu = '[Org]', word = '%OWNER' } }, complete(':COLUMNS: %ITEM %OWN'))
    -- A width in front of the name is preserved in the completion.
    assert.are.same({ { menu = '[Org]', word = '%10EFFORT' } }, complete(':COLUMNS: %ITEM %10EFF'))
  end)

  it('completes a column name after a width', function()
    helpers.create_agenda_file({
      '* Task',
      '  :PROPERTIES:',
      '  :COLUMNS: %24IT',
      '  :END:',
    })
    setup_plugin()
    vim.api.nvim_win_set_cursor(0, { 3, 0 })
    vim.cmd('normal! A')
    local line = vim.api.nvim_get_current_line()
    local start = org.completion:omnifunc(1, '')
    local result = org.completion:omnifunc(0, line:sub(start + 1))
    assert.are.same({ { menu = '[Org]', word = '%24ITEM' } }, result)
  end)

  it('completes a new column token of a drawer COLUMNS property', function()
    helpers.create_agenda_file({
      '* Task',
      '  :PROPERTIES:',
      '  :COLUMNS: %ITEM %',
      '  :END:',
    })
    setup_plugin()
    vim.api.nvim_win_set_cursor(0, { 3, 0 })
    vim.cmd('normal! A')
    local line = vim.api.nvim_get_current_line()
    local start = org.completion:omnifunc(1, '')
    local result = org.completion:omnifunc(0, line:sub(start + 1))
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
      -- The COLUMNS property itself is in use, so it is offered as well.
      { menu = '[Org]', word = '%COLUMNS' },
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
