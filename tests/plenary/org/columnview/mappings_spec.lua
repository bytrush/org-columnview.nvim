local org = require('orgmode')

describe('Column View Mappings', function()
  before_each(function()
    require('org-columnview').setup()
  end)

  ---The key of the column view mapping, with the prefix expanded.
  ---@return string
  local function column_view_key()
    local prefix = require('org-columnview.config').get_prefix()
    return (prefix:gsub('<Leader>', vim.g.mapleader)) .. 'xc'
  end

  ---The key of the agenda column view mapping, with the prefix expanded.
  ---@return string
  local function agenda_column_view_key()
    local prefix = require('org-columnview.config').get_prefix()
    return (prefix:gsub('<Leader>', vim.g.mapleader)) .. 'ac'
  end

  it('registers the entry points in the nvim-orgmode mapping groups', function()
    local mappings = require('orgmode.config.mappings')
    local defaults = require('orgmode.config.defaults')

    assert.is_not_nil(mappings.org.org_columns)
    assert.is_not_nil(mappings.agenda.org_agenda_columns)
    assert.are.equal('<prefix>xc', defaults.mappings.org.org_columns)
    assert.are.equal('<prefix>ac', defaults.mappings.agenda.org_agenda_columns)
  end)

  it('attaches the column view to the org buffer', function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    require('orgmode.config'):setup_mappings('org', bufnr)

    local found = false
    for _, map in ipairs(vim.api.nvim_buf_get_keymap(bufnr, 'n')) do
      if map.lhs == column_view_key() then
        found = true
      end
    end
    assert.is_true(found)
  end)

  it('attaches the column view to the agenda buffer', function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    require('orgmode.config'):setup_mappings('agenda', bufnr)

    local found = false
    for _, map in ipairs(vim.api.nvim_buf_get_keymap(bufnr, 'n')) do
      if map.lhs == agenda_column_view_key() then
        found = true
      end
    end
    assert.is_true(found)
  end)

  it('sets global mappings for the column view', function()
    local found = {}
    for _, map in ipairs(vim.api.nvim_get_keymap('n')) do
      if map.lhs == column_view_key() then
        found.org = true
      end
      if map.lhs == agenda_column_view_key() then
        found.agenda = true
      end
    end
    assert.is_true(found.org or false)
    assert.is_true(found.agenda or false)
  end)

  it('opens the agenda column view through the agenda view type', function()
    local agenda = require('orgmode').agenda
    local original = agenda.open_view
    local called
    agenda.open_view = function(self, type)
      called = type
      return 'opened'
    end

    local result = require('org-columnview').org_agenda_columns()
    agenda.open_view = original

    assert.are.equal('columns', called)
    assert.are.equal('opened', result)
  end)

  it('adds the column view to the agenda prompt menu', function()
    local agenda = require('orgmode').agenda
    local menu = agenda:_build_menu()
    local entry = menu:get_entry_by_key('c')

    assert.is_not_nil(entry)
    assert.are.equal('Column view of all entries', entry.label)
  end)

  it('keeps a mapping that is configured in nvim-orgmode', function()
    local config = require('orgmode.config')
    local original = config.opts.mappings.org.org_columns
    config.opts.mappings.org.org_columns = '<prefix>xy'

    require('org-columnview').setup({ mappings = { org_columns = '<prefix>xz' } })
    assert.are.equal('<prefix>xy', config.opts.mappings.org.org_columns)

    config.opts.mappings.org.org_columns = original
  end)
end)
