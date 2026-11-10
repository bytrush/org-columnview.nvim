local helpers = require('tests.plenary.helpers')

describe('Column view dynamic block', function()
  local dblock = require('org-columnview.dblock')

  local function create(lines, filename)
    vim.bo.modified = false
    local file = helpers.create_file(lines, filename)
    file:reload_sync()
    vim.bo[file:bufnr()].modifiable = true
    return file
  end

  local function lines(file)
    return vim.api.nvim_buf_get_lines(file:bufnr(), 0, -1, false)
  end

  local function content(file)
    return table.concat(lines(file), '\n')
  end

  local function block_content(file)
    local result = {}
    local inside = false
    for _, line in ipairs(lines(file)) do
      if line:find('#+BEGIN: columnview', 1, true) then
        inside = true
      elseif inside then
        if line:find('#+END:', 1, true) then
          break
        end
        table.insert(result, line)
      end
    end
    return table.concat(result, '\n')
  end

  ---The block table with padding and hlines removed, easier to compare.
  local function trimmed_table(file)
    local result = {}
    for line in block_content(file):gmatch('[^\n]+') do
      if not line:match('^|%-') then
        local cells = {}
        local parts = vim.split(line, '|', { plain = true })
        for index = 2, #parts - 1 do
          table.insert(cells, vim.trim(parts[index]))
        end
        table.insert(result, table.concat(cells, '|'))
      end
    end
    return table.concat(result, '\n')
  end

  local function line_index(file, needle)
    for index, line in ipairs(lines(file)) do
      if line:find(needle, 1, true) then
        return index
      end
    end
  end

  local function sample_file(filename)
    return create({
      '#+COLUMNS: %20ITEM %10OWNER %8SCORE{+}',
      '',
      '* Project',
      ':PROPERTIES:',
      ':COLUMNS: %20ITEM %10OWNER %8SCORE{+}',
      ':END:',
      'Body',
      '** Alice task',
      ':PROPERTIES:',
      ':OWNER: Alice',
      ':SCORE: 2',
      ':END:',
      '** Bob task  :work:',
      ':PROPERTIES:',
      ':OWNER: Bob',
      ':SCORE: 3',
      ':END:',
      '** Empty task',
      ':PROPERTIES:',
      ':SCORE:',
      ':END:',
      '* Other',
      ':PROPERTIES:',
      ':OWNER: Carol',
      ':SCORE: 9',
      ':END:',
    }, filename)
  end

  it('inserts and updates a local table', function()
    local file = sample_file('dblock-local.org')
    vim.api.nvim_win_set_cursor(0, { 7, 0 })

    assert.is_true(dblock.insert({ params = { id = 'local', hlines = 1 } }))
    local text = content(file)
    assert.is_truthy(text:find('#+BEGIN: columnview', 1, true))
    local table_text = trimmed_table(file)
    assert.is_truthy(table_text:find('ITEM|OWNER|SCORE', 1, true))
    assert.is_truthy(table_text:find('Project||Σ=5', 1, true))
    assert.is_truthy(table_text:find('Alice task|Alice|2', 1, true))
    assert.is_truthy(table_text:find('Bob task|Bob|3', 1, true))

    local begin_line = assert(line_index(file, '#+BEGIN: columnview'))
    local headline
    for _, candidate in ipairs(file:get_headlines()) do
      if (candidate:get_title()) == 'Bob task' then
        headline = candidate
      end
    end
    assert.is_not_nil(headline)
    headline:set_property('SCORE', '4')
    vim.api.nvim_win_set_cursor(0, { begin_line, 0 })
    assert.is_true(dblock.update())

    table_text = trimmed_table(file)
    assert.is_truthy(table_text:find('Bob task|Bob|4', 1, true))
    assert.is_truthy(table_text:find('Project||Σ=6', 1, true))
  end)

  it('aligns the generated table like org-table-align', function()
    local file = sample_file('dblock-align.org')
    vim.api.nvim_win_set_cursor(0, { 7, 0 })
    assert.is_true(dblock.insert({ params = { id = 'local', hlines = 1 } }))

    local text = block_content(file)
    assert.is_truthy(text:find('| ITEM', 1, true))
    assert.is_truthy(text:find('|---', 1, true))
    assert.is_truthy(text:find('+', 1, true))

    local widths = {}
    for line in text:gmatch('[^\n]+') do
      if not line:match('^|%-') then
        table.insert(widths, vim.api.nvim_strwidth(line))
      end
    end
    for _, width in ipairs(widths) do
      assert.are.equal(widths[1], width)
    end
  end)

  it('makes the injected table visible to nvim-orgmode table tools', function()
    require('org-columnview').setup()
    local file = sample_file('dblock-ts.org')
    vim.api.nvim_win_set_cursor(0, { 7, 0 })
    assert.is_true(dblock.insert({ params = { id = 'local', hlines = 1 } }))

    local header_line = assert(line_index(file, '| ITEM'))
    vim.api.nvim_win_set_cursor(0, { header_line, 8 })

    local Table = require('orgmode.files.elements.table')
    local table = Table.from_current_node()
    assert.is_not_nil(table)
    assert.is_true(#table.rows >= 5)
    assert.is_true(table:reformat())
  end)

  it('treats f as false for boolean parameters', function()
    local file = sample_file('dblock-false.org')
    vim.api.nvim_win_set_cursor(0, { 7, 0 })

    assert.is_true(dblock.insert({
      params = { id = 'global', hlines = 'f', format = '%10ITEM %10OWNER' },
    }))

    local hlines = 0
    for line in block_content(file):gmatch('[^\n]+') do
      if line:match('^|%-') then
        hlines = hlines + 1
      end
    end
    assert.are.equal(1, hlines)
  end)

  it('captures the whole file and honours :format and :maxlevel', function()
    local file = sample_file('dblock-global.org')
    vim.api.nvim_win_set_cursor(0, { 7, 0 })

    assert.is_true(dblock.insert({
      params = {
        id = 'global',
        maxlevel = 1,
        hlines = 1,
        format = '%10ITEM %10OWNER',
      },
    }))

    local text = trimmed_table(file)
    assert.is_truthy(text:find('ITEM|OWNER', 1, true))
    assert.is_truthy(text:find('Project|', 1, true))
    assert.is_truthy(text:find('Other|Carol', 1, true))
    assert.is_falsy(text:find('Alice task', 1, true))
    assert.is_falsy(text:find('SCORE', 1, true))
  end)

  it('skips empty rows and excluded tags', function()
    local file = sample_file('dblock-filter.org')
    vim.api.nvim_win_set_cursor(0, { 7, 0 })

    assert.is_true(dblock.insert({
      params = {
        id = 'local',
        hlines = 1,
        skip_empty_rows = true,
        exclude_tags = 'work',
      },
    }))

    local text = trimmed_table(file)
    assert.is_falsy(text:find('Empty task', 1, true))
    assert.is_falsy(text:find('Bob task', 1, true))
    assert.is_truthy(text:find('Alice task', 1, true))
  end)

  it('filters entries with :match', function()
    local file = sample_file('dblock-match.org')
    vim.api.nvim_win_set_cursor(0, { 7, 0 })

    assert.is_true(dblock.insert({
      params = {
        id = 'global',
        hlines = 1,
        match = 'work',
        format = '%10ITEM %10OWNER',
      },
    }))

    local text = trimmed_table(file)
    assert.is_truthy(text:find('Bob task|Bob', 1, true))
    assert.is_falsy(text:find('Alice task', 1, true))
    assert.is_falsy(text:find('Project', 1, true))
  end)

  it('indents and links the ITEM column', function()
    local file = sample_file('dblock-indent.org')
    vim.api.nvim_win_set_cursor(0, { 7, 0 })

    assert.is_true(dblock.insert({
      params = {
        id = 'local',
        hlines = 1,
        indent = true,
        link = true,
        format = '%20ITEM %10OWNER',
      },
    }))

    local text = block_content(file)
    assert.is_truthy(text:find('[[file:', 1, true))
    assert.is_truthy(text:find('::*Alice task][\\_  Alice task]]', 1, true))
  end)

  it('adds vertical line markers', function()
    local file = sample_file('dblock-vlines.org')
    vim.api.nvim_win_set_cursor(0, { 7, 0 })

    assert.is_true(dblock.insert({ params = { id = 'local', hlines = 1, vlines = true } }))

    local text = block_content(file)
    local table_text = trimmed_table(file)
    assert.is_truthy(text:find('| ITEM', 1, true))
    assert.is_truthy(table_text:find('|ITEM|OWNER|SCORE', 1, true))
    assert.is_truthy(table_text:find('/|<>|<>|<>', 1, true))
  end)

  it('uses a custom formatter', function()
    local file = sample_file('dblock-formatter.org')
    vim.api.nvim_win_set_cursor(0, { 7, 0 })

    assert.is_true(dblock.insert({
      params = { id = 'local' },
      formatter = function(data)
        return { 'CUSTOM', data.header[1] }
      end,
    }))

    local text = content(file)
    assert.is_truthy(text:find('CUSTOM', 1, true))
    assert.is_truthy(text:find('ITEM', 1, true))
  end)

  it('captures an entry selected by :id', function()
    local file = sample_file('dblock-id.org')
    local alice = file:get_headlines()[2]
    alice:set_property('ID', 'alice-entry')
    vim.api.nvim_win_set_cursor(0, { 7, 0 })

    assert.is_true(dblock.insert({ params = { id = 'alice-entry', hlines = 1 } }))

    local text = trimmed_table(file)
    assert.is_truthy(text:find('Alice task|Alice|2', 1, true))
    assert.is_falsy(text:find('Project', 1, true))
  end)

  it('cancels insertion when the scope prompt is canceled', function()
    local file = sample_file('dblock-cancel.org')
    local before = lines(file)
    vim.api.nvim_win_set_cursor(0, { 7, 0 })

    local original_input = vim.fn.input
    vim.fn.input = function()
      return vim.NIL
    end
    local inserted = dblock.insert()
    vim.fn.input = original_input

    assert.is_false(inserted)
    assert.are.same(before, lines(file))
  end)

  it('skips archived trees', function()
    local file = create({
      '#+COLUMNS: %20ITEM',
      '',
      '* Live probe',
      '* Archived probe  :ARCHIVE:',
      '** Archived child probe',
    }, 'dblock-archive.org')
    vim.api.nvim_win_set_cursor(0, { 2, 0 })

    local data = dblock.collect({ id = 'global' })
    local titles = {}
    for _, entry in ipairs(data.entries) do
      table.insert(titles, (entry.headline:get_title()))
    end
    assert.is_truthy(vim.tbl_contains(titles, 'Live probe'))
    assert.is_falsy(vim.tbl_contains(titles, 'Archived probe'))
    assert.is_falsy(vim.tbl_contains(titles, 'Archived child probe'))
  end)

  it('updates every block in the buffer', function()
    local file = sample_file('dblock-all.org')
    vim.api.nvim_win_set_cursor(0, { 7, 0 })
    assert.is_true(dblock.insert({ params = { id = 'local' } }))

    vim.api.nvim_buf_set_lines(file:bufnr(), 7, 7, false, {
      '#+BEGIN: columnview :id global :hlines 1',
      '|stale|',
      '#+END:',
    })

    assert.are.equal(2, dblock.update_all({ bufnr = file:bufnr() }))
    assert.is_truthy(trimmed_table(file):find('Other|Carol|9', 1, true))
  end)
end)
