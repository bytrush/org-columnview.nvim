local helpers = require('tests.plenary.helpers')
local config = require('orgmode.config')
local Parser = require('org-columnview.parser')
local ColumnView = require('org-columnview.view')

describe('ColumnView', function()
  ---@param lines string[]
  ---@return OrgColumnView, OrgFile, OrgHeadline
  local function create_view(lines)
    -- The previous test may have modified its buffer, which would make `:edit`
    -- refuse to open the next fixture.
    vim.bo.modified = false
    local file = helpers.create_file(lines, 'columns.org')
    file:reload_sync()
    local headline = file:get_headlines()[1]
    local columns_def = Parser.get_columns_for_headline(headline, require('orgmode').files)
    local headlines = { headline }
    if headline:has_child_headlines() then
      vim.list_extend(headlines, headline:get_child_headlines())
    end
    local view = ColumnView:new({
      files = require('orgmode').files,
      headlines = headlines,
      subtree = true,
      columns_def = columns_def,
      bufnr = file:bufnr(),
    })
    return view, file, headline
  end

  ---Build a view over all top level headlines of a file.
  ---@param lines string[]
  ---@return OrgColumnView, OrgFile
  local function create_file_view(lines)
    vim.bo.modified = false
    local file = helpers.create_file(lines, 'columns.org')
    file:reload_sync()
    local columns_def = Parser.get_columns_for_file(file)
    local view = ColumnView:new({
      files = require('orgmode').files,
      headlines = file:get_headlines(),
      subtree = false,
      columns_def = columns_def,
      bufnr = file:bufnr(),
    })
    return view, file
  end

  it('builds rows for a headline tree', function()
    local view = create_view({
      '* Parent',
      ':PROPERTIES:',
      ':COLUMNS: %25ITEM %Owner{Owner_ALL}',
      ':Owner_ALL: Alice, Bob',
      ':END:',
      '** Child',
      ':PROPERTIES:',
      ':Owner: Alice',
      ':END:',
    })

    assert.are.equal(2, #view.rows)
    assert.are.equal('Parent', view.rows[1].headline:get_title())
    assert.are.equal('Child', view.rows[2].headline:get_title())
    assert.are.equal('Alice', view.rows[2].cells[2].value)
  end)

  it('looks up property columns case-insensitively', function()
    local view = create_view({
      '* Parent',
      ':PROPERTIES:',
      ':COLUMNS: %10Owner{Owner_ALL}',
      ':Owner_ALL: Alice, Bob',
      ':owner: Bob',
      ':END:',
    })

    assert.are.equal('Bob', view.rows[1].cells[1].value)
  end)

  it('resolves comma separated inline allowed values', function()
    local view = create_file_view({
      '#+COLUMNS: %ITEM %TODO %5POINTS{1,2,3,5,8}',
      '* DONE Ghost of Tsushima',
      '* TODO Baldurs Gate 3',
    })

    assert.are.same({ '1', '2', '3', '5', '8' }, view.allowed_values['POINTS_ALL'])
  end)

  it('resolves allowed values from a file level PROPERTY keyword', function()
    local view = create_file_view({
      '#+COLUMNS: %ITEM %TODO %5POINTS{POINTS_ALL}',
      '#+PROPERTY: POINTS_ALL 1 2 3 5 8',
      '* DONE Ghost of Tsushima',
      '* TODO Baldurs Gate 3',
    })

    assert.are.same({ '1', '2', '3', '5', '8' }, view.allowed_values['POINTS_ALL'])
  end)

  it('resolves allowed values from a file level NAME_ALL keyword', function()
    local view = create_file_view({
      '#+COLUMNS: %ITEM %TODO %5POINTS{POINTS_ALL}',
      '#+POINTS_ALL: 1,2,3,5,8',
      '* DONE Ghost of Tsushima',
    })

    assert.are.same({ '1', '2', '3', '5', '8' }, view.allowed_values['POINTS_ALL'])
  end)

  it('prefers entry allowed values over file level ones', function()
    local view = create_file_view({
      '#+COLUMNS: %ITEM %TODO %5POINTS{POINTS_ALL}',
      '#+PROPERTY: POINTS_ALL 1 2 3',
      '* DONE Ghost of Tsushima',
      ':PROPERTIES:',
      ':POINTS_ALL: 8,13',
      ':END:',
    })

    assert.are.same({ '8', '13' }, view.allowed_values['POINTS_ALL'])
  end)

  it('computes summaries from child values', function()
    local view = create_view({
      '* Parent',
      ':PROPERTIES:',
      ':COLUMNS: %10Effort{+}',
      ':END:',
      '** Child 1',
      ':PROPERTIES:',
      ':Effort: 1:00',
      ':END:',
      '** Child 2',
      ':PROPERTIES:',
      ':Effort: 0:30',
      ':END:',
    })

    assert.are.equal('90', view.rows[1].cells[1].summary)
  end)

  it('summarizes a duration column with "@mean"', function()
    local view = create_view({
      '* Parent',
      ':PROPERTIES:',
      ':COLUMNS: %10Effort{@mean}',
      ':END:',
      '** Child 1',
      ':PROPERTIES:',
      ':Effort: 0:30',
      ':END:',
      '** Child 2',
      ':PROPERTIES:',
      ':Effort: 1:00',
      ':END:',
    })

    assert.are.equal('0:45', view.rows[1].cells[1].summary)
  end)

  it('summarizes a checkbox column with "X%"', function()
    local view = create_view({
      '* Parent',
      ':PROPERTIES:',
      ':COLUMNS: %10Approved{X%}',
      ':END:',
      '** Child 1',
      ':PROPERTIES:',
      ':Approved: [X]',
      ':END:',
      '** Child 2',
      ':PROPERTIES:',
      ':Approved: [ ]',
      ':END:',
    })

    assert.are.equal('[50%]', view.rows[1].cells[1].summary)
  end)

  it('summarizes a duration column with ":min"', function()
    local view = create_view({
      '* Parent',
      ':PROPERTIES:',
      ':COLUMNS: %10Effort{:min}',
      ':END:',
      '** Child 1',
      ':PROPERTIES:',
      ':Effort: 0:30',
      ':END:',
      '** Child 2',
      ':PROPERTIES:',
      ':Effort: 1:00',
      ':END:',
    })

    assert.are.equal('0:30', view.rows[1].cells[1].summary)
  end)

  it('renders the ALLTAGS special column including inherited tags', function()
    local view = create_view({
      '* Parent  :ptag:',
      ':PROPERTIES:',
      ':COLUMNS: %20ALLTAGS',
      ':END:',
      '** Child  :ctag:',
    })

    assert.are.equal(':ptag:', view.rows[1].cells[1].value)
    assert.are.equal(':ctag:ptag:', view.rows[2].cells[1].value)
  end)

  it('renders the CLOSED special column', function()
    local view = create_view({
      '#+COLUMNS: %20CLOSED',
      '* Done task',
      'CLOSED: [2024-01-01 Mon 10:00]',
    })

    assert.are.equal('2024-01-01 Mon', view.rows[1].cells[1].value)
  end)

  it('renders the FILE special column', function()
    local view = create_view({
      '#+COLUMNS: %20FILE',
      '* Task',
    })

    assert.are.equal('columns.org', view.rows[1].cells[1].value)
  end)

  it('renders the TIMESTAMP and TIMESTAMP_IA special columns', function()
    local view = create_view({
      '#+COLUMNS: %20TIMESTAMP %20TIMESTAMP_IA',
      '* Task',
      'Some text <2024-01-01 Mon> and [2024-02-02 Fri]',
    })

    assert.are.equal('2024-01-01 Mon', view.rows[1].cells[1].value)
    assert.are.equal('2024-02-02 Fri', view.rows[1].cells[2].value)
  end)

  it('renders the BLOCKED special column', function()
    local view = create_view({
      '* TODO Parent',
      ':PROPERTIES:',
      ':COLUMNS: %20BLOCKED',
      ':END:',
      '** TODO Child',
    })

    assert.are.equal('t', view.rows[1].cells[1].value)
    assert.are.equal('', view.rows[2].cells[1].value)
  end)

  it('renders the BLOCKED special column as empty when NOBLOCKING is set', function()
    local view = create_view({
      '* TODO Parent',
      ':PROPERTIES:',
      ':NOBLOCKING: t',
      ':COLUMNS: %20BLOCKED',
      ':END:',
      '** TODO Child',
    })

    assert.are.equal('', view.rows[1].cells[1].value)
  end)

  it('toggles checkbox cell values in both directions', function()
    local view = create_view({
      '* Parent',
      ':PROPERTIES:',
      ':COLUMNS: %10Approved(Approved?){[ ],[X]}',
      ':approved: [X]',
      ':END:',
    })

    assert.are.equal('[X]', view.rows[1].cells[1].value)

    view.current_row = 1
    view.current_col = 1
    view:toggle_or_quit()
    assert.are.equal('[ ]', view.rows[1].cells[1].value)
    assert.are.equal('[ ]', view.rows[1].headline:get_property('approved'))

    view:toggle_or_quit()
    assert.are.equal('[X]', view.rows[1].cells[1].value)
    assert.are.equal('[X]', view.rows[1].headline:get_property('approved'))
  end)

  it('quits instead of cycling TODO when toggling on the ITEM column', function()
    local view = create_view({
      '* TODO Parent',
      ':PROPERTIES:',
      ':COLUMNS: %25ITEM',
      ':END:',
    })
    view.current_row = 1
    view.current_col = 1
    view:open()

    assert.are.equal('TODO', view.rows[1].headline:get_todo())
    view:toggle_or_quit()

    assert.are.equal('TODO', view.rows[1].headline:get_todo())
    assert.is_false(view._opened)
  end)

  it('stores edited allowed values in the entry that defines them', function()
    local view = create_view({
      '* Grandparent',
      ':PROPERTIES:',
      ':COLUMNS: %10Status{Status_ALL}',
      ':Status_ALL: ToDo,Done',
      ':END:',
      '** Parent',
      ':PROPERTIES:',
      ':END:',
      '*** Child',
      ':PROPERTIES:',
      ':END:',
    })

    view.current_row = 3
    view.current_col = 1

    local original_input = vim.fn.input
    vim.fn.input = function()
      return 'ToDo,In progress,Done'
    end

    local ok, err = pcall(function()
      view:edit_allowed()
    end)
    vim.fn.input = original_input

    assert.is_true(ok, err)
    assert.are.equal('ToDo,In progress,Done', view.rows[1].headline:get_own_properties()['status_all'])
    assert.is_nil(view.rows[3].headline:get_own_properties()['status_all'])
    assert.are.equal(
      'ToDo,In progress,Done',
      view.allowed_values['STATUS_ALL'] and table.concat(view.allowed_values['STATUS_ALL'], ',') or nil
    )
  end)

  it('stores edited allowed values in the first entry when none is defined', function()
    local view = create_view({
      '* Parent',
      ':PROPERTIES:',
      ':COLUMNS: %10Status{Status_ALL}',
      ':END:',
      '** Child',
      ':PROPERTIES:',
      ':END:',
    })

    view.current_row = 2
    view.current_col = 1

    local original_input = vim.fn.input
    vim.fn.input = function()
      return 'ToDo,Done'
    end
    view:edit_allowed()
    vim.fn.input = original_input

    assert.are.equal('ToDo,Done', view.rows[1].headline:get_own_properties()['status_all'])
    assert.is_nil(view.rows[2].headline:get_own_properties()['status_all'])
  end)

  it('refuses to edit allowed values for special columns', function()
    local view = create_view({
      '* TODO Parent',
      ':PROPERTIES:',
      ':COLUMNS: %25ITEM %TODO',
      ':END:',
    })

    view.current_row = 1
    view.current_col = 2

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
    assert.is_nil(view.rows[1].headline:get_own_properties()['todo_all'])
  end)

  it('narrows columns that do not have an explicit width', function()
    local view = create_view({
      '* Parent',
      ':PROPERTIES:',
      ':COLUMNS: %Owner{Owner_ALL}',
      ':Owner_ALL: Alice',
      ':Owner: Bob',
      ':END:',
    })

    assert.is_nil(view.rows[1].cells[1].column.width)

    view.current_row = 1
    view.current_col = 1
    view:narrow_column()

    assert.are.equal(9, view.rows[1].cells[1].column.width)
  end)

  it('edits the current column attributes', function()
    local view = create_view({
      '* Parent',
      ':PROPERTIES:',
      ':COLUMNS: %10Owner',
      ':END:',
      '** Child',
      ':PROPERTIES:',
      ':Owner: Alice',
      ':END:',
    })

    view.current_row = 1
    view.current_col = 1

    local original_input = vim.fn.input
    local responses = { 'Status', 'Status?', '12', '+' }
    local idx = 0
    vim.fn.input = function()
      idx = idx + 1
      return responses[idx]
    end
    view:edit_attributes()
    vim.fn.input = original_input

    assert.are.equal('STATUS', view.columns[1].name)
    assert.are.equal('Status?', view.columns[1].title)
    assert.are.equal(12, view.columns[1].width)
    assert.are.equal('+', view.columns[1].summary_type)
    assert.is_false(view.columns[1].is_special)
  end)

  it('marks a renamed column as special', function()
    local view = create_view({
      '* Parent',
      ':PROPERTIES:',
      ':COLUMNS: %10Owner',
      ':END:',
    })

    view.current_row = 1
    view.current_col = 1

    local original_input = vim.fn.input
    local responses = { 'CLOCKSUM', 'CLOCKSUM', '', '' }
    local idx = 0
    vim.fn.input = function()
      idx = idx + 1
      return responses[idx]
    end
    view:edit_attributes()
    vim.fn.input = original_input

    assert.are.equal('CLOCKSUM', view.columns[1].name)
    assert.is_true(view.columns[1].is_special)
  end)

  it('persists column edits to the start headline COLUMNS property', function()
    local view, file = create_view({
      '* Parent',
      ':PROPERTIES:',
      ':COLUMNS: %10Owner{Owner_ALL}',
      ':Owner_ALL: Alice, Bob',
      ':END:',
      '** Child',
      ':PROPERTIES:',
      ':Owner: Alice',
      ':END:',
    })

    view.current_row = 1
    view.current_col = 1
    view:widen_column()

    local headline = file:get_headlines()[1]
    assert.are.equal('%11OWNER{Owner_ALL}', headline:get_property('COLUMNS', false))
  end)

  it('persists edited attributes to headline COLUMNS property', function()
    local view, file = create_view({
      '* Parent',
      ':PROPERTIES:',
      ':COLUMNS: %10Owner',
      ':END:',
    })

    view.current_row = 1
    view.current_col = 1

    local original_input = vim.fn.input
    local responses = { 'Status', '', '12', '+' }
    local idx = 0
    vim.fn.input = function()
      idx = idx + 1
      return responses[idx]
    end
    view:edit_attributes()
    vim.fn.input = original_input

    local headline = file:get_headlines()[1]
    assert.are.equal('%12STATUS{+}', headline:get_property('COLUMNS', false))
  end)

  it('moves the current row down among its siblings', function()
    local view, file = create_view({
      '* Parent',
      ':PROPERTIES:',
      ':COLUMNS: %25ITEM',
      ':END:',
      '** Child 1',
      '** Child 2',
    })
    vim.wo.foldmethod = 'manual'
    vim.cmd('normal! zE')

    view.current_row = 2
    view.current_col = 1
    view:move_row_down()

    local lines = vim.api.nvim_buf_get_lines(file:bufnr(), 4, 6, false)
    assert.are.same({ '** Child 2', '** Child 1' }, lines)
    assert.are.equal('Child 2', view.rows[2].headline:get_title())
    assert.are.equal('Child 1', view.rows[3].headline:get_title())
    assert.are.equal(3, view.current_row)
  end)

  it('moves the current row up among its siblings', function()
    local view, file = create_view({
      '* Parent',
      ':PROPERTIES:',
      ':COLUMNS: %25ITEM',
      ':END:',
      '** Child 1',
      '** Child 2',
    })
    vim.wo.foldmethod = 'manual'
    vim.cmd('normal! zE')

    view.current_row = 3
    view.current_col = 1
    view:move_row_up()

    local lines = vim.api.nvim_buf_get_lines(file:bufnr(), 4, 6, false)
    assert.are.same({ '** Child 2', '** Child 1' }, lines)
    assert.are.equal('Child 2', view.rows[2].headline:get_title())
    assert.are.equal(2, view.current_row)
  end)

  it('does not move a row past the superior level', function()
    local view, file = create_view({
      '* Parent',
      ':PROPERTIES:',
      ':COLUMNS: %25ITEM',
      ':END:',
      '** Child 1',
      '** Child 2',
    })
    vim.wo.foldmethod = 'manual'
    vim.cmd('normal! zE')

    view.current_row = 2
    view.current_col = 1
    view:move_row_up()

    local lines = vim.api.nvim_buf_get_lines(file:bufnr(), 4, 6, false)
    assert.are.same({ '** Child 1', '** Child 2' }, lines)
    assert.are.equal(2, view.current_row)
  end)

  it('moves a row whose range is inside a closed fold', function()
    local view, file = create_view({
      '* Parent',
      ':PROPERTIES:',
      ':COLUMNS: %25ITEM',
      ':END:',
      '** Child 1',
      '** Child 2',
    })

    view.current_row = 2
    view.current_col = 1
    view:move_row_down()

    local lines = vim.api.nvim_buf_get_lines(file:bufnr(), 4, 6, false)
    assert.are.same({ '** Child 2', '** Child 1' }, lines)
  end)

  it('keeps closed folds when moving a row', function()
    local view, file = create_view({
      '* Parent',
      ':PROPERTIES:',
      ':COLUMNS: %25ITEM',
      ':END:',
      '** Child 1',
      ':PROPERTIES:',
      ':ID: 1',
      ':END:',
      '** Child 2',
    })

    vim.api.nvim_set_current_buf(file:bufnr())
    view.winid = vim.api.nvim_get_current_win()
    vim.wo.foldmethod = 'expr'
    vim.wo.foldlevel = 99
    vim.cmd('normal! zR')

    -- Close Child 1's drawer, leaving the rest open.
    vim.api.nvim_win_set_cursor(0, { 6, 0 })
    vim.cmd('normal! zc')
    assert.are.equal(6, vim.fn.foldclosed(6))

    view.current_row = 2
    view.current_col = 1
    view:move_row_down()

    -- The fold is restored asynchronously, after the fold structure is
    -- recomputed for the moved text.
    vim.wait(500, function()
      return vim.fn.foldclosed(7) == 7
    end, 10)

    assert.are.equal(7, vim.fn.foldclosed(7))
    assert.are.equal(-1, vim.fn.foldclosed(1))
    assert.are.equal(-1, vim.fn.foldclosed(5))
  end)

  it('refreshes the view from the current file state', function()
    local view = create_view({
      '* Parent',
      ':PROPERTIES:',
      ':COLUMNS: %10Owner',
      ':END:',
      '** Child',
      ':PROPERTIES:',
      ':Owner: Alice',
      ':END:',
    })

    assert.are.equal('Alice', view.rows[2].cells[1].value)

    view.rows[2].headline:set_property('owner', 'Bob')
    view:refresh()

    assert.are.equal('Bob', view.rows[2].cells[1].value)
  end)

  it('defines the highlight groups of the column view', function()
    require('org-columnview.highlights').define()
    for _, group in ipairs({
      '@org.column.border',
      '@org.column.value',
      '@org.column.header',
      '@org.column.current',
      '@org.column.summary',
    }) do
      local hl = vim.api.nvim_get_hl(0, { name = group })
      assert.is_not_nil(hl.link, ('missing highlight group %s'):format(group))
    end
  end)

  it('highlights the cell of the row the cursor is on', function()
    local view = create_file_view({
      '#+COLUMNS: %ITEM %TODO',
      '* First',
      '* Second',
    })
    view:open()

    assert.are.equal(1, view.current_row)

    vim.api.nvim_win_set_cursor(0, { 3, 0 })
    view:_sync_current_cell()

    assert.are.equal(2, view.current_row)

    -- The cell of the current row is highlighted.
    local marks = vim.api.nvim_buf_get_extmarks(view.bufnr, view.ns, 0, -1, { details = true })
    local highlighted = {}
    for _, mark in ipairs(marks) do
      for _, chunk in ipairs(mark[4].virt_text or {}) do
        if chunk[2] == '@org.column.current' then
          highlighted[mark[2]] = true
        end
      end
    end
    assert.is_true(highlighted[2] or false)
    assert.is_nil(highlighted[1])

    view:quit()
  end)

  it('renders a time summary for the ":" summary type', function()
    local view = create_view({
      '* Parent',
      ':PROPERTIES:',
      ':COLUMNS: %10Effort(Effort){:}',
      ':END:',
      '** Child 1',
      ':PROPERTIES:',
      ':Effort: 1:00',
      ':END:',
      '** Child 2',
      ':PROPERTIES:',
      ':Effort: 2:30',
      ':END:',
    })

    assert.are.equal('3:30', view.rows[1].cells[1].summary)
  end)

  it('highlights a summary cell as current when it is selected', function()
    local view = create_view({
      '* Parent',
      ':PROPERTIES:',
      ':COLUMNS: %10ITEM %10Effort(Effort){:}',
      ':END:',
      '** Child',
      ':PROPERTIES:',
      ':Effort: 1:00',
      ':END:',
    })

    -- Effort cell is rendered after the border/item/border parts
    view.current_row = 1
    view.current_col = 1
    local not_current = view:_build_virt_text(view.rows[1], 1)[4]
    assert.are.equal('@org.column.summary', not_current[2])
    assert.is_truthy(not_current[1]:find('Σ='))

    view.current_col = 2
    local current = view:_build_virt_text(view.rows[1], 1)[4]
    assert.are.equal('@org.column.current', current[2])
    assert.is_truthy(current[1]:find('Σ='))
  end)

  it('keeps a summary cell the same width as regular cells', function()
    local view = create_view({
      '* Parent',
      ':PROPERTIES:',
      ':COLUMNS: %10ITEM %10Effort(Effort){:}',
      ':END:',
      '** Child',
      ':PROPERTIES:',
      ':Effort: 1:00',
      ':END:',
    })

    local parent_cell = view:_build_virt_text(view.rows[1], 1)[4][1]
    local child_cell = view:_build_virt_text(view.rows[2], 2)[4][1]

    assert.are.equal(vim.api.nvim_strwidth(child_cell), vim.api.nvim_strwidth(parent_cell))
  end)

  it('updates parent summaries when a child value changes', function()
    local view = create_view({
      '* Parent',
      ':PROPERTIES:',
      ':COLUMNS: %10ITEM %10Effort(Effort){:}',
      ':END:',
      '** Child',
      ':PROPERTIES:',
      ':Effort: 1:00',
      ':END:',
    })

    assert.are.equal('1:00', view.rows[1].cells[2].summary)

    view.current_row = 2
    view.current_col = 2
    view:_set_cell_value(view.rows[2].cells[2], '5:00')

    assert.are.equal('5:00', view.rows[2].cells[2].value)
    assert.are.equal('5:00', view.rows[1].cells[2].summary)
  end)

  it('stays active when a floating popup (help) is opened', function()
    local view = create_view({
      '* Parent',
      ':PROPERTIES:',
      ':COLUMNS: %10Owner{Owner_ALL}',
      ':Owner_ALL: Alice',
      ':Owner: Bob',
      ':END:',
    })

    local quit_called = false
    view.on_quit = function()
      quit_called = true
    end
    view:open()

    local columnview = require('org-columnview')
    columnview.show_help()
    vim.wait(50)

    local help_buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_win_close(vim.api.nvim_get_current_win(), true)
    vim.wait(50)

    assert.is_false(quit_called)
    assert.is_true(vim.api.nvim_buf_is_valid(help_buf))

    view:quit()
  end)

  it('registers default mappings for all column view actions', function()
    local maps = require('org-columnview.mappings').get_view_mappings()
    local prefix = require('orgmode.config').mappings.prefix
    assert.are.same({ '<' }, maps.narrow_column.keys)
    assert.are.same({ '>' }, maps.widen_column.keys)
    assert.are.same({ '<M-Left>' }, maps.move_column_left.keys)
    assert.are.same({ '<M-Right>' }, maps.move_column_right.keys)
    assert.are.same({ '<S-M-Left>' }, maps.delete_column.keys)
    assert.are.same({ '<S-M-Right>' }, maps.insert_column.keys)
    assert.are.same({ '<M-Up>' }, maps.move_row_up.keys)
    assert.are.same({ '<M-Down>' }, maps.move_row_down.keys)
    assert.are.same({ 's' }, maps.edit_attributes.keys)
    assert.are.same({ 'r' }, maps.refresh.keys)
    assert.are.same({ 'c' }, maps.content.keys)
    assert.are.same({ 'o' }, maps.overview.keys)
    assert.are.same({ '<C-c><C-o>', prefix .. 'o' }, maps.open_link.keys)
    assert.are.same({ '<C-c><C-t>', prefix .. 't' }, maps.todo.keys)
    assert.are.same({ 'g?' }, maps.show_help.keys)
    assert.are.same({ '1', '2', '3', '4', '5', '6', '7', '8', '9', '0' }, maps.select_value.keys)
  end)

  it('binds and tears down both open link keys, expanding the prefix', function()
    local view = create_view({
      '* Parent',
      ':PROPERTIES:',
      ':COLUMNS: %ITEM',
      ':END:',
    })
    local original_leader = vim.g.mapleader
    vim.g.mapleader = ' '
    view:open()

    local function has_lhs(target)
      for _, m in ipairs(vim.api.nvim_buf_get_keymap(view.bufnr, 'n')) do
        if m.lhs == target then
          return true
        end
      end
      return false
    end

    assert.is_true(has_lhs('<C-C><C-O>'))
    assert.is_true(has_lhs(' oo'))

    view:quit()
    assert.is_false(has_lhs('<C-C><C-O>'))
    assert.is_false(has_lhs(' oo'))

    vim.g.mapleader = original_leader
  end)

  it('binds and tears down both todo keys, expanding the prefix', function()
    local view = create_view({
      '* Parent',
      ':PROPERTIES:',
      ':COLUMNS: %ITEM',
      ':END:',
    })
    local original_leader = vim.g.mapleader
    vim.g.mapleader = ' '
    view:open()

    local function has_lhs(target)
      for _, m in ipairs(vim.api.nvim_buf_get_keymap(view.bufnr, 'n')) do
        if m.lhs == target then
          return true
        end
      end
      return false
    end

    assert.is_true(has_lhs('<C-C><C-T>'))
    assert.is_true(has_lhs(' ot'))

    view:quit()
    assert.is_false(has_lhs('<C-C><C-T>'))
    assert.is_false(has_lhs(' ot'))

    vim.g.mapleader = original_leader
  end)

  it('has a handler method for every column view action', function()
    local view = create_view({
      '* Parent',
      ':PROPERTIES:',
      ':COLUMNS: %ITEM',
      ':END:',
    })
    local maps = require('org-columnview.mappings').get_view_mappings()
    for name, _ in pairs(maps) do
      if name ~= 'select_value' then
        assert.is_function(view[name], ('missing ColumnView handler for %s'):format(name))
      end
    end
  end)

  it('includes column view mappings in help content', function()
    local columnview = require('org-columnview')
    columnview.show_help()
    local buf = vim.api.nvim_get_current_buf()
    local content = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
    vim.api.nvim_win_close(vim.api.nvim_get_current_win(), true)

    assert.is_truthy(content:find('column view', 1, true))
    assert.is_truthy(content:find('Quit the column view', 1, true))
  end)

  it('sums CLOCK intervals across the subtree for CLOCKSUM', function()
    local view = create_view({
      '* Parent',
      ':PROPERTIES:',
      ':COLUMNS: %10CLOCKSUM',
      ':END:',
      ':LOGBOOK:',
      'CLOCK: [2000-01-03 Mon 08:00]--[2000-01-03 Mon 09:00] => 1:00',
      ':END:',
      '** Child',
      ':LOGBOOK:',
      'CLOCK: [2000-01-03 Mon 10:00]--[2000-01-03 Mon 12:00] => 2:00',
      ':END:',
    })

    assert.are.equal('3:00', view.rows[1].cells[1].value)
    assert.are.equal('2:00', view.rows[2].cells[1].value)
  end)

  it('restricts CLOCKSUM_T to clocks from today', function()
    local view = create_view({
      '* Parent',
      ':PROPERTIES:',
      ':COLUMNS: %10CLOCKSUM_T',
      ':END:',
      '** Past child',
      ':LOGBOOK:',
      'CLOCK: [2000-01-03 Mon 10:00]--[2000-01-03 Mon 12:00] => 2:00',
      ':END:',
    })

    assert.are.equal('', view.rows[1].cells[1].value)
    assert.are.equal('', view.rows[2].cells[1].value)
  end)

  it('renders the age column from the CREATED property', function()
    local view = create_view({
      '* Parent',
      ':PROPERTIES:',
      ':COLUMNS: %10AGE',
      ':CREATED: 2020-01-01 Wed',
      ':END:',
    })

    assert.is_truthy(view.rows[1].cells[1].value:match('%d+%s*[dwmy]'))
  end)

  it('toggles the view off when invoked again while active', function()
    local file = helpers.create_file({
      '* Parent',
      ':PROPERTIES:',
      ':COLUMNS: %10ITEM %Owner',
      ':END:',
      '** Child',
      ':PROPERTIES:',
      ':Owner: Alice',
      ':END:',
    }, 'toggle.org')
    file:reload_sync()
    vim.api.nvim_win_set_cursor(0, { 1, 0 })

    local columnview = require('org-columnview')
    columnview.org_columns()
    assert.is_not_nil(columnview.column_view)

    columnview.org_columns()
    assert.is_nil(columnview.column_view)
  end)

  it('opens a whole-file view when point is before the first headline', function()
    local file = helpers.create_file({
      '#+COLUMNS: %10ITEM %Owner',
      '',
      '* First',
      ':PROPERTIES:',
      ':Owner: Alice',
      ':END:',
      '* Second',
      ':PROPERTIES:',
      ':Owner: Bob',
      ':END:',
    }, 'whole-file.org')
    file:reload_sync()
    vim.api.nvim_win_set_cursor(0, { 1, 0 })

    local columnview = require('org-columnview')
    columnview.org_columns()
    assert.is_not_nil(columnview.column_view)
    assert.are.equal(2, #columnview.column_view.rows)
    assert.are.equal('First', columnview.column_view.rows[1].headline:get_title())
    assert.are.equal('Second', columnview.column_view.rows[2].headline:get_title())

    columnview.org_columns()
    assert.is_nil(columnview.column_view)
  end)

  it('persists whole-file edits to the file COLUMNS keyword', function()
    local file = helpers.create_file({
      '#+COLUMNS: %10Item',
      '',
      '* First',
      '* Second',
    }, 'whole-file-persist.org')
    file:reload_sync()
    vim.api.nvim_win_set_cursor(0, { 1, 0 })

    local columnview = require('org-columnview')
    local view = columnview.org_columns()
    view.current_row = 1
    view.current_col = 1
    view:widen_column()
    columnview.org_columns()

    assert.are.equal('#+COLUMNS: %11ITEM', vim.api.nvim_buf_get_lines(file:bufnr(), 0, 1, false)[1])
  end)

  it('inserts a file COLUMNS keyword when the start headline has none', function()
    vim.bo.modified = false
    local file = helpers.create_file({
      '* Parent',
      '** Child',
      ':PROPERTIES:',
      ':Owner: Alice',
      ':END:',
    }, 'insert-columns.org')
    file:reload_sync()
    local headline = file:get_headlines()[1]
    local view = ColumnView:new({
      files = require('orgmode').files,
      headlines = { headline },
      subtree = true,
      columns_def = Parser.parse('%10Owner'),
      bufnr = file:bufnr(),
    })

    view.current_row = 1
    view.current_col = 1
    view:widen_column()

    assert.are.equal('#+COLUMNS: %11OWNER', vim.api.nvim_buf_get_lines(file:bufnr(), 0, 1, false)[1])
  end)

  it('selects a specific TODO keyword by number', function()
    local view = create_view({
      '* Parent',
      ':PROPERTIES:',
      ':COLUMNS: %25ITEM %TODO',
      ':END:',
    })
    view.current_row = 1
    view.current_col = 2

    view:select_value(2)
    assert.are.equal('DONE', view.rows[1].headline:get_todo())

    view:select_value(1)
    assert.are.equal('TODO', view.rows[1].headline:get_todo())
  end)

  it('selects a specific priority by number', function()
    local view = create_view({
      '* Parent',
      ':PROPERTIES:',
      ':COLUMNS: %25ITEM %PRIORITY',
      ':END:',
    })
    view.current_row = 1
    view.current_col = 2

    view:select_value(3)
    assert.are.equal('C', view.rows[1].headline:get_priority())

    view:select_value(1)
    assert.are.equal('A', view.rows[1].headline:get_priority())
  end)

  it('selects a value using the number key mappings', function()
    local view = create_view({
      '* Parent',
      ':PROPERTIES:',
      ':COLUMNS: %25ITEM %TODO',
      ':END:',
    })
    view.current_row = 1
    view.current_col = 2
    view:open()

    vim.api.nvim_feedkeys('2', 'x', false)
    assert.are.equal('DONE', view.rows[1].headline:get_todo())

    vim.api.nvim_feedkeys('1', 'x', false)
    assert.are.equal('TODO', view.rows[1].headline:get_todo())

    view:quit()
  end)

  it('selects the 10th value with the 0 key', function()
    local view = create_view({
      '* Parent',
      ':PROPERTIES:',
      ':COLUMNS: %10Owner{Owner_ALL}',
      ':Owner_ALL: A,B,C,D,E,F,G,H,I,J',
      ':END:',
    })
    view.current_row = 1
    view.current_col = 1
    view:open()

    vim.api.nvim_feedkeys('0', 'x', false)
    assert.are.equal('J', view.rows[1].headline:get_property('owner'))

    view:quit()
  end)

  it('cycles TODO from the empty state to the first keyword', function()
    local view = create_view({
      '* Parent',
      ':PROPERTIES:',
      ':COLUMNS: %25ITEM %TODO',
      ':END:',
    })
    view.current_row = 1
    view.current_col = 2

    view:next_value()
    assert.are.equal('TODO', view.rows[1].headline:get_todo())

    view:next_value()
    assert.are.equal('DONE', view.rows[1].headline:get_todo())

    view:prev_value()
    assert.are.equal('TODO', view.rows[1].headline:get_todo())
  end)

  it('renders the header in the window bar and restores it on quit', function()
    local view = create_view({
      '* Parent',
      ':PROPERTIES:',
      ':COLUMNS: %10Owner %12Status',
      ':END:',
    })
    vim.wo.winbar = 'ORIGINAL_WINBAR'
    view:open()

    local winbar = vim.wo[view.winid].winbar
    assert.is_truthy(winbar:find('Owner', 1, true))
    assert.is_truthy(winbar:find('Status', 1, true))

    view:quit()
    assert.are.equal('ORIGINAL_WINBAR', vim.wo[view.winid].winbar)
  end)

  it('locks the buffer while the view is open and restores it on quit', function()
    local view = create_view({
      '* Parent',
      ':PROPERTIES:',
      ':COLUMNS: %25ITEM %10Owner{Owner_ALL}',
      ':Owner_ALL: Alice, Bob',
      ':END:',
    })
    view.current_row = 1
    view.current_col = 2

    local bufnr = view.bufnr
    assert.is_true(vim.bo[bufnr].modifiable)

    view:open()
    assert.is_false(vim.bo[bufnr].modifiable)

    view:select_value(2)
    assert.are.equal('Bob', view.rows[1].headline:get_property('owner'))
    assert.is_false(vim.bo[bufnr].modifiable)

    view:quit()
    assert.is_true(vim.bo[bufnr].modifiable)
  end)

  it('skips rows hidden by a closed fold when navigating', function()
    local view = create_view({
      '* Parent',
      ':PROPERTIES:',
      ':COLUMNS: %ITEM',
      ':END:',
      '** One',
      '** Two',
    })
    assert.are.equal(3, #view.rows)

    vim.api.nvim_set_current_buf(view.bufnr)
    vim.cmd('setlocal foldmethod=manual')
    vim.cmd('normal! zE')
    vim.cmd('5,6fold')

    -- The fold's first line (One) stays visible, its content (Two) does not.
    assert.is_true(view:_is_row_visible(view.rows[2]))
    assert.is_false(view:_is_row_visible(view.rows[3]))

    view.current_row = 1
    view:move_down()
    assert.are.equal(2, view.current_row)
    view:move_down()
    assert.are.equal(2, view.current_row)

    vim.cmd('normal! zE')
    vim.cmd('setlocal foldmethod=expr')
  end)

  it('switches between overview and content views', function()
    local view = create_view({
      '* Parent',
      ':PROPERTIES:',
      ':COLUMNS: %ITEM',
      ':END:',
      '** Child',
    })
    vim.api.nvim_set_current_buf(view.bufnr)
    vim.cmd('setlocal foldmethod=manual')
    view.winid = vim.api.nvim_get_current_win()

    view:overview()
    assert.is_true(vim.wo.foldenable)

    view:content()
    assert.is_true(vim.wo.foldenable)
    assert.are.equal(1, vim.wo.foldlevel)

    vim.cmd('setlocal foldmethod=expr')
  end)

  it('opens the bracketed link in the current cell', function()
    local view = create_view({
      '* [[file:notes.org][Notes]]',
      ':PROPERTIES:',
      ':COLUMNS: %ITEM',
      ':END:',
    })
    local followed = {}
    view.links = {
      follow = function(_, url)
        table.insert(followed, url)
      end,
    }

    view.current_row = 1
    view.current_col = 1
    view:open_link()
    assert.are.equal('file:notes.org', followed[1])
  end)

  it('opens the plain link in the current cell', function()
    local view = create_view({
      '* Meeting',
      ':PROPERTIES:',
      ':COLUMNS: %ITEM %10Link',
      ':Link: https://example.com',
      ':END:',
    })
    local followed = {}
    view.links = {
      follow = function(_, url)
        table.insert(followed, url)
      end,
    }

    view.current_row = 1
    view.current_col = 2
    view:open_link()
    assert.are.equal('https://example.com', followed[1])
  end)

  it('refuses to edit cells computed from children', function()
    local view = create_view({
      '* Parent',
      ':PROPERTIES:',
      ':COLUMNS: %ITEM %10Effort{+}',
      ':END:',
      '** Child',
      ':PROPERTIES:',
      ':Effort: 1:00',
      ':END:',
    })

    assert.is_true(view.rows[1].cells[2].is_computed)
    assert.is_false(view.rows[2].cells[2].is_computed)

    view.current_row = 1
    view.current_col = 2
    view:select_value(1)

    assert.is_nil(view.rows[1].headline:get_property('effort'))
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

    local view = create_view({
      '* Parent',
      ':PROPERTIES:',
      ':COLUMNS: %10Owner(Owner)',
      ':Owner: alice',
      ':END:',
    })

    assert.are.equal('ALICE', view:_cell_content(view.rows[1].cells[1]))
    -- The stored value is unchanged.
    assert.are.equal('alice', view.rows[1].cells[1].value)

    columnview_config.opts.modify_value_for_display_function = original
  end)

  it('cycles the TODO state via the todo action without fast access', function()
    local view = create_view({
      '* Parent',
      ':PROPERTIES:',
      ':COLUMNS: %ITEM',
      ':END:',
    })
    local TodoState = require('orgmode.objects.todo_state')
    local original_has = TodoState.has_fast_access
    local original_open = TodoState.open_fast_access
    local prompted = false
    TodoState.has_fast_access = function()
      return false
    end
    TodoState.open_fast_access = function()
      prompted = true
      return { value = 'DONE' }
    end

    view.current_row = 1
    view:todo()

    TodoState.has_fast_access = original_has
    TodoState.open_fast_access = original_open
    assert.is_false(prompted)
    assert.are.equal('TODO', view.rows[1].headline:get_todo())
  end)

  it('prompts with fast access via the todo action when configured', function()
    local view = create_view({
      '* Parent',
      ':PROPERTIES:',
      ':COLUMNS: %ITEM',
      ':END:',
    })
    local TodoState = require('orgmode.objects.todo_state')
    local original_has = TodoState.has_fast_access
    local original_open = TodoState.open_fast_access
    TodoState.has_fast_access = function()
      return true
    end
    TodoState.open_fast_access = function()
      return { value = 'DONE' }
    end

    view.current_row = 1
    view:todo()

    TodoState.has_fast_access = original_has
    TodoState.open_fast_access = original_open
    assert.are.equal('DONE', view.rows[1].headline:get_todo())
  end)

  it('refuses the todo action when the column under the cursor is computed', function()
    local view = create_view({
      '* Parent',
      ':PROPERTIES:',
      ':COLUMNS: %ITEM %10Effort{+}',
      ':END:',
      '** Child',
      ':PROPERTIES:',
      ':Effort: 1:00',
      ':END:',
    })

    view.current_row = 1
    view.current_col = 2
    view:todo()

    assert.is_nil(view.rows[1].headline:get_todo())
  end)

  it('keeps every row rendered when an edit inserts a property drawer', function()
    local view = create_file_view({
      '#+columns: %ITEM %TODO %5POINTS{POINTS_ALL}',
      '#+POINTS_ALL: 1 2 3 4 5',
      '',
      '* DONE Marvel Spider Man',
      '  :PROPERTIES:',
      '  :points: 5',
      '  :END:',
      '* TODO Marvel Spider Man 2',
      '* IN-PROGRESS Cyberpunk 2077',
      '* TODO Baldurs Gate 3',
    })
    view:open()

    for idx, row in ipairs(view.rows) do
      if row.headline:get_title():find('Cyberpunk 2077', 1, true) then
        view.current_row = idx
      end
    end
    view.current_col = 3

    local original_select = vim.ui.select
    vim.ui.select = function(_, _, cb)
      cb('4')
    end
    view:edit_value()
    vim.ui.select = original_select

    assert.are.equal(4, #view.rows)
    assert.are.equal('4', view.rows[3].headline:get_property('POINTS'))

    -- Editing the drawer-less row inserted a property drawer, shifting the
    -- headlines below it. Every row must still be rendered at its new position.
    local marked = {}
    for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(view.bufnr, view.ns, 0, -1, {})) do
      marked[mark[2]] = true
    end
    for _, row in ipairs(view.rows) do
      assert.is_true(marked[row.headline:get_range().start_line - 1] or false)
    end
  end)
end)
