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

  it('registers the entry points in the nvim-orgmode mapping groups', function()
    local mappings = require('orgmode.config.mappings')
    local defaults = require('orgmode.config.defaults')

    assert.is_not_nil(mappings.org.org_columns)
    assert.is_not_nil(mappings.agenda.org_agenda_columns)
    assert.are.equal('<prefix>xc', defaults.mappings.org.org_columns)
    assert.are.equal('<prefix>xc', defaults.mappings.agenda.org_agenda_columns)
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
      if map.lhs == column_view_key() then
        found = true
      end
    end
    assert.is_true(found)
  end)

  it('sets a global mapping for the column view', function()
    local found = false
    for _, map in ipairs(vim.api.nvim_get_keymap('n')) do
      if map.lhs == column_view_key() then
        found = true
      end
    end
    assert.is_true(found)
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
