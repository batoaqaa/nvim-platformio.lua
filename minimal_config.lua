-- pick a temp root
local tmp = vim.loop.os_tmpdir() .. '/nvim-temp'

vim.env.XDG_DATA_HOME = tmp .. '/data'
vim.env.XDG_CACHE_HOME = tmp .. '/cache'
vim.env.XDG_STATE_HOME = tmp .. '/state'

local lazypath = vim.env.XDG_DATA_HOME .. '/lazy/lazy.nvim'

if not (vim.uv or vim.loop).fs_stat(lazypath) then
  vim.fn.system({
    'git',
    'clone',
    '--filter=blob:none',
    'https://github.com/folke/lazy.nvim.git',
    '--branch=stable',
    lazypath,

  })
end

vim.opt.rtp:prepend(lazypath)

local plugins ={{
    'anurag3301/nvim-platformio.lua',

    -- Dependencies are lazy-loaded by default unless specified otherwise.
    dependencies = {
      { 'akinsho/toggleterm.nvim' },
      { 'nvim-telescope/telescope.nvim' },
      { 'nvim-telescope/telescope-ui-select.nvim' },
      { 'nvim-lua/plenary.nvim' },
      { 'folke/which-key.nvim' },
      { 'nvim-treesitter/nvim-treesitter' },
    },
  },
}

require('lazy').setup(plugins, {
  install = {
    missing = true,
  },
})

vim.opt['number'] = true

vim.g.pioConfig = {
  lsp = 'clangd', -- value: clangd | ccls
  clangd_source = 'ccls', -- value: ccls | compiledb, For detailed explation check :help platformio-clangd_source
  menu_key = '<leader>\\', -- replace this menu key  to your convenience
  debug = false, -- enable debug messages
}
local pok, platformio = pcall(require, 'platformio')
if pok then
  platformio.setup(vim.g.pioConfig)
end
