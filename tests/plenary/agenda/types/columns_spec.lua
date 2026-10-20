local helpers = require('tests.plenary.helpers')

describe('Agenda Columns Type', function()
  local OrgAgendaColumnsType = require('org-columnview.agenda')
  local org = require('orgmode')
  local config = require('orgmode.config')

  local function build_view(content, opts)
    opts = opts or {}
    vim.bo.modified = false
    helpers.create_agenda_file(content)
    local bufnr = vim.api.nvim_create_buf(false, true)
    local view
    view = OrgAgendaColumnsType:new({
      files = org.files,
      highlighter = org.highlighter,
      agenda_filter = org.agenda.filters,
      overriding_columns_format = opts.overriding_columns_format or nil,
      remove_tags = opts.remove_tags,
      on_edit = opts.on_edit or function(headline, setter)
        headline.file
          :update(function()
            setter(headline)
          end)
          :wait()
        view:render(bufnr)
      end,
    })
    view:prepare():wait()
    view:render(bufnr)
    return view
  end

  local function headline_index(view, title)
    for i, h in ipairs(view.headlines) do
      if h:get_title() == title then
        return i
      end
    end
  end

  local function column_index(view, name)
    name = name:upper()
    for i, c in ipairs(view.columns) do
      if c.name == name then
        return i
      end
    end
  end

  local function render_lines(view)
    return vim.tbl_map(function(line)
      return line:compile().content
    end, view:get_lines())
  end

  it('renders a column view with header and rows', function()
    local view = build_view({
      '#+COLUMNS: %20ITEM %TODO %TAGS',
      '',
      '* TODO Task One  :work:',
      '* DONE Task Two  :home:',
    })

    assert.is_not_nil(view)
    assert.is_true(#view.columns >= 3)

    local lines = render_lines(view)
    local content = table.concat(lines, '\n')
    assert.is_truthy(content:find('ITEM', 1, true))
    assert.is_truthy(content:find('TODO', 1, true))
    assert.is_truthy(content:find('TAGS', 1, true))
    assert.is_truthy(content:find('Task One', 1, true))
    assert.is_truthy(content:find('Task Two', 1, true))
  end)

  it('renders special columns like TODO and PRIORITY', function()
    local view = build_view({
      '#+COLUMNS: %30ITEM %TODO %PRIORITY',
      '',
      '* TODO Task One [#A]',
      '* DONE Task Two',
    })

    assert.is_not_nil(view)
    assert.is_true(#view.columns >= 3)

    local lines = render_lines(view)
    local content = table.concat(lines, '\n')
    assert.is_truthy(content:find('TODO', 1, true))
    assert.is_truthy(content:find('DONE', 1, true))
    assert.is_truthy(content:find('[#A]', 1, true))
  end)

  it('renders ITEM column with headline titles', function()
    local view = build_view({
      '#+COLUMNS: %ITEM',
      '* First task',
      '* Second task',
    })

    assert.is_not_nil(view)
    local lines = render_lines(view)
    local content = table.concat(lines, '\n')
    assert.is_truthy(content:find('First task', 1, true))
    assert.is_truthy(content:find('Second task', 1, true))
  end)

  it('uses overriding format when provided', function()
    local view = build_view({
      '#+COLUMNS: %ITEM %TODO',
      '* Task',
    }, { overriding_columns_format = '%ITEM %PRIORITY' })

    assert.is_not_nil(view)
    assert.equal('PRIORITY', view.columns[2].name)
  end)

  it('uses the global overriding format when the command does not set one', function()
    local view = build_view({
      '#+COLUMNS: %ITEM %TODO',
      '* Task',
    })

    local columnview_config = require('org-columnview.config')
    columnview_config.opts.overriding_columns_format = '%ITEM %PRIORITY'
    view:render(view.bufnr)
    columnview_config.opts.overriding_columns_format = nil

    assert.equal('PRIORITY', view.columns[2].name)
  end)

  it('hides the TAGS column when remove_tags is set', function()
    local view = build_view({
      '#+COLUMNS: %ITEM %TAGS',
      '* Task  :removetagsprobe:',
    }, { remove_tags = true })

    local content = table.concat(render_lines(view), '\n')
    assert.is_falsy(content:find('removetagsprobe', 1, true))
  end)

  it('falls back to the global default format', function()
    local view = build_view({
      '* Task A',
      '* Task B',
    })

    assert.is_not_nil(view)
    assert.is_true(#view.columns > 0)
  end)

  it('attaches headline refs for navigation', function()
    local view = build_view({
      '#+COLUMNS: %ITEM',
      '* Task One',
      '* Task Two',
    })

    assert.is_not_nil(view)
    local lines = view:get_lines()
    assert.is_not_nil(lines[3].headline_ref)
    assert.is_not_nil(lines[4].headline_ref)
  end)

  it('filters entries through agenda filter', function()
    local view = build_view({
      '#+COLUMNS: %ITEM',
      '* TODO Active',
      '* DONE Done',
    })

    assert.is_not_nil(view)
    local lines = render_lines(view)
    local content = table.concat(lines, '\n')
    assert.is_truthy(content:find('Active', 1, true))
  end)

  it('recomputes rows on render so redo reflects file changes', function()
    local view = build_view({
      '#+COLUMNS: %ITEM',
      '* Redo Probe One',
    })
    local target
    for _, h in ipairs(view.headlines) do
      if h:get_title() == 'Redo Probe One' then
        target = h
        break
      end
    end
    assert.is_not_nil(target)
    local filename = target.file.filename

    vim.api.nvim_buf_set_lines(target.file:bufnr(), 1, 1, false, { '* Redo Probe Two' })
    view.files:load_sync(true)
    view:render(view.bufnr)

    local found = false
    for _, h in ipairs(view.headlines) do
      if h.file.filename == filename and h:get_title() == 'Redo Probe Two' then
        found = true
      end
    end
    assert.is_true(found)
  end)

  it('rerenders a single row in place after an inline edit', function()
    local view = build_view({
      '#+COLUMNS: %ITEM %TODO',
      '* Task One',
    })
    local old_line = view:get_lines()[3]
    old_line.headline:set_todo('TODO')

    view:rerender_agenda_line(old_line, old_line.headline)

    local content = table.concat(render_lines(view), '\n')
    assert.is_truthy(content:find('TODO', 1, true))
  end)

  it('moves between cells with move_left/right/up/down', function()
    local view = build_view({ '* Nav One', '* Nav Two' }, {
      overriding_columns_format = '%ITEM %TODO',
    })
    view.current_row = headline_index(view, 'Nav One')
    view.current_col = column_index(view, 'ITEM')

    view:move_right()
    assert.are.equal(column_index(view, 'TODO'), view.current_col)
    view:move_right()
    assert.are.equal(column_index(view, 'TODO'), view.current_col)
    view:move_left()
    assert.are.equal(column_index(view, 'ITEM'), view.current_col)

    view:move_down()
    assert.are.equal(headline_index(view, 'Nav One') + 1, view.current_row)
    view:move_up()
    assert.are.equal(headline_index(view, 'Nav One'), view.current_row)
  end)

  it('selects a TODO value with select_value', function()
    local view = build_view({ '* Todo Probe' }, {
      overriding_columns_format = '%25ITEM %TODO',
    })
    view.current_row = headline_index(view, 'Todo Probe')
    view.current_col = column_index(view, 'TODO')

    view:select_value(2)
    local updated = view.headlines[headline_index(view, 'Todo Probe')]
    assert.are.equal('DONE', updated:get_todo())
  end)

  it('cycles a TODO value with next_value', function()
    local view = build_view({ '* Cycle Probe' }, {
      overriding_columns_format = '%25ITEM %TODO',
    })
    view.current_row = headline_index(view, 'Cycle Probe')
    view.current_col = column_index(view, 'TODO')

    view:next_value()
    assert.are.equal('TODO', view.headlines[headline_index(view, 'Cycle Probe')]:get_todo())
    view.current_row = headline_index(view, 'Cycle Probe')
    view:next_value()
    assert.are.equal('DONE', view.headlines[headline_index(view, 'Cycle Probe')]:get_todo())
    view.current_row = headline_index(view, 'Cycle Probe')
    view:prev_value()
    assert.are.equal('TODO', view.headlines[headline_index(view, 'Cycle Probe')]:get_todo())
  end)

  it('cycles a property value through its allowed values', function()
    local view = build_view({
      '* Prop Parent',
      ':PROPERTIES:',
      ':Owner_ALL: Alice, Bob',
      ':Owner: Alice',
      ':END:',
    }, {
      overriding_columns_format = '%25ITEM %Owner{Owner_ALL}',
    })
    view.current_row = headline_index(view, 'Prop Parent')
    view.current_col = column_index(view, 'Owner')

    view:next_value()
    local updated = view.headlines[headline_index(view, 'Prop Parent')]
    assert.are.equal('Bob', updated:get_property('owner'))
  end)

  it('resolves allowed values from a file level PROPERTY keyword', function()
    local view = build_view({
      '#+PROPERTY: POINTS_ALL 1 2 3 5 8',
      '',
      '* File Prop Probe',
    }, {
      overriding_columns_format = '%25ITEM %5POINTS{POINTS_ALL}',
    })
    view.current_row = headline_index(view, 'File Prop Probe')
    view.current_col = column_index(view, 'POINTS')

    assert.are.same({ '1', '2', '3', '5', '8' }, view.allowed_values['POINTS_ALL'])

    view:next_value()
    assert.are.equal('2', view.headlines[headline_index(view, 'File Prop Probe')]:get_property('points'))
  end)

  it('toggles a checkbox property', function()
    local view = build_view({
      '* Check Probe',
      ':PROPERTIES:',
      ':status: [ ]',
      ':END:',
    }, {
      overriding_columns_format = '%25ITEM %Status',
    })
    view.current_row = headline_index(view, 'Check Probe')
    view.current_col = column_index(view, 'Status')

    view:toggle_or_quit()
    assert.are.equal('[X]', view.headlines[headline_index(view, 'Check Probe')]:get_property('status'))
    view.current_row = headline_index(view, 'Check Probe')
    view:toggle_or_quit()
    assert.are.equal('[ ]', view.headlines[headline_index(view, 'Check Probe')]:get_property('status'))
  end)

  it('cycles the TODO state with the todo action', function()
    local view = build_view({ '* Todo Action Probe' }, {
      overriding_columns_format = '%25ITEM %Effort',
    })

    view.current_row = headline_index(view, 'Todo Action Probe')
    view.current_col = column_index(view, 'ITEM')
    view:todo()

    assert.are.equal('TODO', view.headlines[headline_index(view, 'Todo Action Probe')]:get_todo())
  end)

  it('follows the link in the current cell', function()
    local view = build_view({ '* [[file:notes.org][Notes]]' }, {
      overriding_columns_format = '%25ITEM',
    })
    local followed = {}
    view._links = {
      follow = function(_, url)
        table.insert(followed, url)
      end,
    }

    local row
    for i, h in ipairs(view.headlines) do
      if h:get_title():find('notes.org', 1, true) then
        row = i
        break
      end
    end
    assert.is_not_nil(row)

    view.current_row = row
    view.current_col = column_index(view, 'ITEM')
    view:open_link()

    assert.are.equal('file:notes.org', followed[1])
  end)

  it('applies the value display function when rendering', function()
    local columnview_config = require('org-columnview.config')
    local original = columnview_config.opts.modify_value_for_display_function
    columnview_config.opts.modify_value_for_display_function = function(column, value)
      if column == 'Owner' and value ~= '' then
        return value:upper()
      end
      return nil
    end

    local view = build_view({
      '* Owner Probe',
      ':PROPERTIES:',
      ':Owner: alice',
      ':END:',
    }, {
      overriding_columns_format = '%25ITEM %Owner(Owner)',
    })
    columnview_config.opts.modify_value_for_display_function = original

    local content = table.concat(render_lines(view), '\n')
    assert.is_truthy(content:find('ALICE', 1, true))
  end)

  it('edits allowed values with edit_allowed', function()
    local view = build_view({
      '* Curator Parent',
      ':PROPERTIES:',
      ':Curator_ALL: Alice,Bob',
      ':Curator: Alice',
      ':END:',
    }, {
      overriding_columns_format = '%25ITEM %Curator{Curator_ALL}',
    })
    view.current_row = headline_index(view, 'Curator Parent')
    view.current_col = column_index(view, 'Curator')

    local original_input = vim.fn.input
    vim.fn.input = function()
      return 'Alice,Carol'
    end
    view:edit_allowed()
    vim.fn.input = original_input

    local updated = view.headlines[headline_index(view, 'Curator Parent')]
    assert.are.equal('Alice,Carol', updated:get_own_properties()['curator_all'])
    assert.are.same({ 'Alice', 'Carol' }, view.allowed_values['CURATOR_ALL'])
  end)

  it('refuses to edit allowed values for special columns', function()
    local view = build_view({ '* TODO Special Probe' }, { overriding_columns_format = '%25ITEM %TODO' })
    view.current_row = headline_index(view, 'Special Probe')
    view.current_col = column_index(view, 'TODO')

    local utils = require('orgmode.utils')
    local original_echo = utils.echo_info
    local messages = {}
    utils.echo_info = function(msg)
      table.insert(messages, msg)
    end
    local original_input = vim.fn.input
    vim.fn.input = function()
      error('input must not be called for special columns')
    end
    local ok, err = pcall(function()
      view:edit_allowed()
    end)
    vim.fn.input = original_input
    utils.echo_info = original_echo

    assert.is_true(ok, err)
    assert.is_truthy(messages[1] and messages[1]:find('TODO', 1, true))
    local updated = view.headlines[headline_index(view, 'Special Probe')]
    assert.is_nil(updated:get_own_properties()['todo_all'])
  end)

  it('changes columns while the agenda buffer is not modifiable', function()
    local view = build_view({ '* Mod Probe' }, { overriding_columns_format = '%10ITEM %TODO' })
    vim.bo[view.bufnr].modifiable = false
    view.current_row = 1
    view.current_col = column_index(view, 'ITEM')

    assert.has_no.errors(function()
      view:narrow_column()
      view:widen_column()
      view:move_column_left()
      view:move_column_right()
      view:delete_column()
    end)

    assert.is_false(vim.bo[view.bufnr].modifiable)
  end)

  it('inserts a column while the agenda buffer is not modifiable', function()
    local view = build_view({ '* Mod Insert Probe' }, { overriding_columns_format = '%10ITEM %TODO' })
    vim.bo[view.bufnr].modifiable = false
    view.current_row = 1
    view.current_col = column_index(view, 'TODO')

    local original_input = vim.fn.input
    local responses = { 'Owner', '' }
    local idx = 0
    vim.fn.input = function()
      idx = idx + 1
      return responses[idx]
    end
    assert.has_no.errors(function()
      view:insert_column()
    end)
    vim.fn.input = original_input

    assert.is_not_nil(column_index(view, 'OWNER'))
    assert.is_false(vim.bo[view.bufnr].modifiable)
  end)

  it('narrows and widens the current column', function()
    local view = build_view({ '* Width Probe' }, { overriding_columns_format = '%10ITEM %8TODO' })
    view.current_row = 1
    view.current_col = column_index(view, 'ITEM')

    view:narrow_column()
    assert.are.equal(9, view.columns[view.current_col].width)
    view:widen_column()
    assert.are.equal(10, view.columns[view.current_col].width)
  end)

  it('inserts a column before the current one and keeps it across renders', function()
    local view = build_view({ '* Insert Probe' }, { overriding_columns_format = '%10ITEM %TODO' })
    view.current_row = 1
    view.current_col = column_index(view, 'TODO')

    local original_input = vim.fn.input
    local responses = { 'Owner', '12' }
    local idx = 0
    vim.fn.input = function()
      idx = idx + 1
      return responses[idx]
    end
    view:insert_column()
    vim.fn.input = original_input

    assert.are.equal('OWNER', view.columns[view.current_col].name)
    assert.are.equal(12, view.columns[column_index(view, 'OWNER')].width)

    view:render(view.bufnr)
    assert.is_not_nil(column_index(view, 'OWNER'))
  end)

  it('edits the current column attributes and keeps them across renders', function()
    local view = build_view({ '* Edit Probe' }, { overriding_columns_format = '%10ITEM %8TODO' })
    view.current_row = 1
    view.current_col = column_index(view, 'TODO')

    local original_input = vim.fn.input
    local responses = { 'Owner', 'Owner?', '12', '+' }
    local idx = 0
    vim.fn.input = function()
      idx = idx + 1
      return responses[idx]
    end
    view:edit_attributes()
    vim.fn.input = original_input

    assert.are.equal('OWNER', view.columns[view.current_col].name)
    assert.are.equal('Owner?', view.columns[view.current_col].title)
    assert.are.equal(12, view.columns[view.current_col].width)
    assert.are.equal('+', view.columns[view.current_col].summary_type)

    view:render(view.bufnr)
    assert.are.equal('OWNER', view.columns[view.current_col].name)
    assert.are.equal(12, view.columns[view.current_col].width)
  end)

  it('refreshes the column display', function()
    local view = build_view({ '* Refresh Probe' }, { overriding_columns_format = '%10ITEM %8TODO' })
    assert.has_no.errors(function()
      view:refresh()
    end)
  end)

  it('deletes the current column', function()
    local view = build_view({ '* Delete Probe' }, { overriding_columns_format = '%10ITEM %TODO' })
    view.current_row = 1
    view.current_col = column_index(view, 'TODO')

    view:delete_column()

    assert.is_nil(column_index(view, 'TODO'))
    assert.is_not_nil(column_index(view, 'ITEM'))
  end)

  it('moves the current column left and right', function()
    local view = build_view({ '* Move Probe' }, { overriding_columns_format = '%10ITEM %TODO' })
    view.current_row = 1
    local todo_col = column_index(view, 'TODO')
    view.current_col = todo_col

    view:move_column_left()
    assert.are.equal(todo_col - 1, column_index(view, 'TODO'))
    assert.are.equal(todo_col - 1, view.current_col)

    view:move_column_right()
    assert.are.equal(todo_col, column_index(view, 'TODO'))
    assert.are.equal(todo_col, view.current_col)
  end)

  it('shows the column view help', function()
    local view = build_view({ '* Help Probe' }, { overriding_columns_format = '%ITEM' })
    local columnview = require('org-columnview')
    local original = columnview.show_help
    local shown = false
    columnview.show_help = function()
      shown = true
    end
    view:show_help()
    columnview.show_help = original

    assert.is_true(shown)
  end)

  it('highlights the current cell', function()
    local view = build_view({ '* Hl Probe' }, { overriding_columns_format = '%10ITEM %8TODO' })
    local win = vim.api.nvim_open_win(view.bufnr, true, {
      relative = 'editor',
      row = 1,
      col = 1,
      width = 40,
      height = 5,
    })
    view.current_row = headline_index(view, 'Hl Probe')
    view.current_col = column_index(view, 'ITEM')
    view:_goto_cell(view.current_row, view.current_col)

    local ns = vim.api.nvim_create_namespace('orgmode_agenda_columns')
    local marks = vim.api.nvim_buf_get_extmarks(view.bufnr, ns, 0, -1, { details = true })
    assert.is_true(#marks >= 1)

    OrgAgendaColumnsType.clear_highlights(view.bufnr)
    marks = vim.api.nvim_buf_get_extmarks(view.bufnr, ns, 0, -1, { details = true })
    assert.are.equal(0, #marks)
    vim.api.nvim_win_close(win, true)
  end)

  it('attaches and clears buffer local column mappings', function()
    local view = build_view({ '* Key Probe' }, { overriding_columns_format = '%ITEM %TODO' })
    local bufnr = view.bufnr
    local function lhs_set()
      local set = {}
      for _, m in ipairs(vim.api.nvim_buf_get_keymap(bufnr, 'n')) do
        set[m.lhs] = true
      end
      return set
    end

    local keys = lhs_set()
    assert.is_true(keys['h'] and keys['l'] and keys['j'] and keys['k'])
    assert.is_true(keys['n'] and keys['p'] and keys['e'] and keys['v'])
    assert.is_true(keys['1'] and keys['0'])
    assert.is_true(keys['a'] and keys['<lt>'] and keys['>'] and keys['g?'])
    assert.is_true(keys['<M-S-Right>'] and keys['<M-S-Left>'])
    assert.is_true(keys['<M-Left>'] and keys['<M-Right>'])
    assert.is_true(keys['s'] and keys['r'])

    OrgAgendaColumnsType.clear_mappings(bufnr)
    keys = lhs_set()
    assert.is_nil(keys['h'])
    assert.is_nil(keys['n'])
    assert.is_nil(keys['1'])
    assert.is_nil(keys['a'])
    assert.is_nil(keys['<lt>'])
    assert.is_nil(keys['g?'])
    assert.is_nil(keys['s'])
  end)

  it('restores pre-existing buffer local mappings on clear', function()
    local view = build_view({ '* Restore Probe' }, { overriding_columns_format = '%ITEM %TODO' })
    local bufnr = view.bufnr
    local calls = 0
    -- Mirror Agenda:render: clear first, then register the agenda mapping so
    -- the column view snapshots and later restores it.
    OrgAgendaColumnsType.clear_mappings(bufnr)
    vim.keymap.set('n', 'g?', function()
      calls = calls + 1
    end, { buffer = bufnr, desc = 'agenda help' })

    view:render(bufnr)
    OrgAgendaColumnsType.clear_mappings(bufnr)

    local restored
    for _, m in ipairs(vim.api.nvim_buf_get_keymap(bufnr, 'n')) do
      if m.lhs == 'g?' then
        restored = m
        break
      end
    end
    assert.is_not_nil(restored)
    assert.are.equal('agenda help', restored.desc)

    restored.callback()
    assert.are.equal(1, calls)
  end)
end)
