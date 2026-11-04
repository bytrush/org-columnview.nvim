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
end)
