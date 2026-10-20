local M = {}
---@class OrgMinPlugin A plugin to download and register on the package path
---@alias OrgPluginName string The plugin name, will be used as part of the git clone destination
---@alias OrgPluginUrl string The git url at which a plugin is located, can be a path. See https://git-scm.com/book/en/v2/Git-on-the-Server/Protocols for details
---@alias OrgMinPlugins table<OrgPluginName, OrgPluginUrl>

-- Gets the current directory of this file
local base_root_path = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h')
---Gets the root directory of the minimal init and if path is specified appends it to the root allowing for
---subdirectories within the current cwd
---@param path string? The additional path to append to the root, not required
---@return string root The root path suffixed with the path provided or an empty suffix if none is given
function M.root(path)
  return base_root_path .. '/.deps/' .. (path or '')
end

---Downloads a plugin from a given url and registers it on the 'runtimepath'
---@param plugin_name OrgPluginName
---@param plugin_url OrgPluginUrl
function M.load_plugin(plugin_name, plugin_url)
  local package_root = M.root('plugins/')
  local install_destination = package_root .. plugin_name
  vim.opt.runtimepath:append(install_destination)

  if not vim.uv.fs_stat(package_root) then
    vim.fn.mkdir(package_root, 'p')
  end

  -- If the plugin install path already exists, we don't need to clone it again.
  if not vim.uv.fs_stat(install_destination) then
    print(string.format('>> Downloading plugin "%s" to "%s"', plugin_name, install_destination))
    vim.fn.system({
      'git',
      'clone',
      '--depth=1',
      plugin_url,
      install_destination,
    })
    if vim.v.shell_error > 0 then
      error(string.format('>> Failed to clone plugin: "%s" to "%s"!', plugin_name, install_destination), 0)
    end
  end
end

---Use a plugin that is already available on the local filesystem, for example a
---checkout next to this repository.
---@param plugin_name OrgPluginName
---@param plugin_path string
function M.use_local_plugin(plugin_name, plugin_path)
  if not vim.uv.fs_stat(plugin_path) then
    return false
  end
  vim.opt.runtimepath:append(plugin_path)
  return true
end

---Do the initial setup. Downloads plugins, ensures the minimal init does not pollute the filesystem by keeping
---everything self contained to the CWD of the minimal init file. Run prior to running tests, reproducing issues, etc.
---@param plugins? OrgMinPlugins
function M.setup(plugins)
  vim.opt.packpath = {} -- Empty the package path so we use only the plugins specified
  vim.opt.runtimepath:append(M.root('.min')) -- Ensure the runtime detects the root min dir

  -- Install required plugins
  if plugins ~= nil then
    for plugin_name, plugin_url in pairs(plugins) do
      M.load_plugin(plugin_name, plugin_url)
    end
  end

  vim.env.XDG_CONFIG_HOME = M.root('xdg/config')
  vim.env.XDG_DATA_HOME = M.root('xdg/data')
  vim.env.XDG_STATE_HOME = M.root('xdg/state')
  vim.env.XDG_CACHE_HOME = M.root('xdg/cache')

  local std_paths = {
    'cache',
    'data',
    'config',
  }

  for _, std_path in ipairs(std_paths) do
    vim.fn.mkdir(vim.fn.stdpath(std_path), 'p')
  end

  -- NOTE: Cleanup the xdg cache on exit so new runs of the minimal init doesn't share any previous state, e.g. shada
  vim.api.nvim_create_autocmd('VimLeave', {
    callback = function()
      vim.fn.delete(M.root('xdg'), 'rf')
    end,
  })
end

M.setup({
  plenary = 'https://github.com/nvim-lua/plenary.nvim.git',
})
-- WARN: Do all plugin setup, test runs, reproductions, etc. AFTER calling setup with a list of plugins!
-- Basically, do all that stuff AFTER this line.

---Locate nvim-orgmode. A local checkout is preferred, so that the tests run
---against the working copy. `ORGMODE_PATH` overrides the lookup.
---@return string|nil
local function find_orgmode()
  local candidates = {
    base_root_path .. '/../../orgmode',
    base_root_path .. '/../../nvim-orgmode',
  }
  if vim.env.ORGMODE_PATH then
    table.insert(candidates, 1, vim.env.ORGMODE_PATH)
  end
  for _, candidate in ipairs(candidates) do
    if vim.uv.fs_stat(candidate .. '/lua/orgmode/init.lua') then
      return vim.fn.fnamemodify(candidate, ':p:h')
    end
  end
  return nil
end

local orgmode_path = find_orgmode()
if orgmode_path then
  -- Prepend, so that the nvim-orgmode ftplugin is sourced before the one from
  -- the Neovim runtime (`ftplugin/org.vim`), which would otherwise set
  -- `b:did_ftplugin` and prevent it from running.
  vim.opt.runtimepath:prepend(orgmode_path)
else
  M.load_plugin('orgmode', 'https://github.com/nvim-orgmode/orgmode.git')
end

-- Register the column view plugin itself
vim.opt.runtimepath:prepend(vim.fn.fnamemodify(base_root_path, ':h'))

-- Set proper settings --
vim.opt.termguicolors = true
vim.opt.swapfile = false
vim.opt.expandtab = true
vim.cmd.language('en_US.utf-8')
vim.env.TZ = 'Europe/London'
vim.g.mapleader = ','

require('orgmode').setup({
  org_agenda_files = { base_root_path .. '/plenary/fixtures/*' },
  org_default_notes_file = base_root_path .. '/plenary/fixtures/refile.org',
})
