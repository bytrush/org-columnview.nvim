local helpers = require('tests.plenary.helpers')

describe('Agenda column view scope', function()
  it('limits the columns to the current agenda view and keeps them in sync', function()
    local orgmode = require('orgmode')
    local today = os.date('%Y-%m-%d')
    local orgfile = helpers.create_agenda_file({
      '#+COLUMNS: %ITEM',
      '',
      '* Dated today',
      '  <' .. today .. '>',
      '* Undated',
    })
    require('org-columnview').setup()

    local agenda = orgmode.agenda
    agenda:agenda():wait()

    local agenda_titles = {}
    for _, line in ipairs(agenda.views[1]:get_lines()) do
      if line.headline then
        table.insert(agenda_titles, (line.headline:get_title()))
      end
    end
    assert.are.same({ 'Dated today' }, agenda_titles)

    local promise = require('org-columnview').org_agenda_columns()
    if promise then
      promise:wait()
    end

    local column_titles = {}
    for _, headline in ipairs(agenda.views[1].headlines) do
      table.insert(column_titles, (headline:get_title()))
    end
    assert.are.same({ 'Dated today' }, column_titles)

    vim.api.nvim_buf_set_lines(orgfile:bufnr(), 0, -1, false, {
      '#+COLUMNS: %ITEM',
      '',
      '* Renamed',
      '  <' .. today .. '>',
      '* Undated',
    })
    agenda:redo():wait()

    column_titles = {}
    for _, headline in ipairs(agenda.views[1].headlines) do
      table.insert(column_titles, (headline:get_title()))
    end
    assert.are.same({ 'Renamed' }, column_titles)
  end)

  it('shows per-date summary rows in the column view', function()
    local orgmode = require('orgmode')
    local today = os.date('%Y-%m-%d')
    helpers.create_agenda_file({
      '#+COLUMNS: %20ITEM %10SCORE{+}',
      '',
      '* First dated task',
      '  <' .. today .. '>',
      ':PROPERTIES:',
      ':SCORE: 2',
      ':END:',
      '* Second dated task',
      '  <' .. today .. '>',
      ':PROPERTIES:',
      ':SCORE: 3',
      ':END:',
    })

    local columnview = require('org-columnview')
    columnview.setup({ overriding_columns_format = '%20ITEM %10SCORE{+}' })

    local agenda = orgmode.agenda
    agenda:agenda():wait()
    local promise = columnview.org_agenda_columns()
    if promise then
      promise:wait()
    end

    local rendered = {}
    for _, line in ipairs(agenda.views[1]:get_lines()) do
      table.insert(rendered, line:compile().content)
    end
    local content = table.concat(rendered, '\n')

    assert.is_truthy(content:find(today, 1, true))
    assert.is_truthy(content:find('5', 1, true))
    assert.is_truthy(content:find('First dated task', 1, true))
    assert.is_truthy(content:find('Second dated task', 1, true))
    columnview.setup()
  end)

  it('starts the agenda in columns view when configured', function()
    local orgmode = require('orgmode')
    local today = os.date('%Y-%m-%d')
    helpers.create_agenda_file({
      '#+COLUMNS: %ITEM',
      '',
      '* Initial columns probe',
      '  <' .. today .. '>',
    })

    local columnview = require('org-columnview')
    columnview.setup({ agenda_columns_initially = true })

    local agenda = orgmode.agenda
    agenda:agenda():wait()

    assert.is_not_nil(agenda.views[1].columns)
    assert.is_not_nil(agenda.views[1].headlines)

    local titles = vim.tbl_map(function(headline)
      return (headline:get_title())
    end, agenda.views[1].headlines)
    assert.is_truthy(vim.tbl_contains(titles, 'Initial columns probe'))

    columnview.setup({ agenda_columns_initially = false })
  end)
end)
