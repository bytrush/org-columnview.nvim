-- The minimal init sets up the runtime path, so that nvim-orgmode and the
-- column view plugin can be required.
require('tests.minimal_init')

-- Ensure that the tree-sitter grammar can be correctly installed, exit early on error
local ok, err = pcall(function()
  return require('orgmode.utils.treesitter.install').install()
end)
if not ok then
  print(vim.inspect(err), '\n')
  return os.exit(1)
end

-- Do not run tests on Windows, just ensure that tree-sitter grammar can be installed.
if vim.fn.has('win32') > 0 then
  return os.exit(0)
end

---@type string
local test_file = vim.v.argv[#vim.v.argv]
if test_file == '' or not test_file:find('tests/plenary/', nil, true) then
  test_file = 'tests/plenary'
  print('Running all tests at ' .. test_file)
else
  print('Individual Test File/Directory provided: ' .. test_file)
end

require('plenary.test_harness').test_directory(test_file, {
  minimal_init = 'tests/minimal_init.lua',
  sequential = true,
})
