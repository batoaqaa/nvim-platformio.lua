-- pick a temp root
local tmp = vim.loop.os_tmpdir() .. '/nvim-temp'

vim.env.XDG_DATA_HOME = tmp .. '/data'
vim.env.XDG_CACHE_HOME = tmp .. '/cache'
vim.env.XDG_STATE_HOME = tmp .. '/state'

-- disable netrw at the very start of your init.lua
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

-- optionally enable 24-bit colour
vim.opt.termguicolors = true

vim.opt['number'] = true
vim.opt.tabstop = 2 -- Number of spaces tabs count for
vim.opt.softtabstop = 2
vim.opt.shiftround = true -- Round indent
vim.opt.shiftwidth = 2 -- Size of an indent
vim.opt.smartindent = true -- Insert indents automatically
vim.opt.expandtab = true -- Use spaces instead of tabs
vim.opt.clipboard = vim.env.SSH_TTY and '' or 'unnamedplus' -- Sync with system clipboard

vim.g.have_nerd_font = true
vim.g.mapleader = ' '
vim.g.maplocalleader = ' '

local isWindows = jit.os == 'Windows'
if not isWindows then
  vim.opt.shell = '/bin/bash' -- or '/bin/zsh', '/usr/bin/fish', etc.
  vim.g.shellcmdflag = '-c' -- Executes the command passed as a string
  vim.g.shellpipe = '|' -- Pipes output of external commands
  vim.g.shellredir = '> ' -- Redirects output of external commands
else
  vim.g.shell = vim.fn.executable('pwsh') and 'pwsh' or 'powershell'
  vim.g.shellcmdflag =
    '-NoLogo -ExecutionPolicy RemoteSigned -Command [Console]::InputEncoding=[Console]::OutputEncoding=[System.Text.UTF8Encoding]::new();$PSDefaultParameterValues[Out-File:Encoding]=utf8;Remove-Alias -Force -ErrorAction SilentlyContinue tee;'
  vim.g.shellredir = '2>&1 | %%{ "$_" } | Out-File %s; exit $LastExitCode'
  vim.g.shellpipe = '2>&1 | %%{ "$_" } | tee %s; exit $LastExitCode'
  vim.g.shellquote = ''
  vim.g.shellxquote = ''
end

-- Toggle virtual_text off when on the line with the error
vim.diagnostic.config({
  virtual_lines = true,
  update_in_insert = true,
  underline = true,
  severity_sort = true,
  float = {
    focusable = true,
    style = 'minimal',
    border = 'rounded',
    source = true,
    header = '',
    prefix = '',
  },
  signs = {
    text = {
      [vim.diagnostic.severity.ERROR] = ' ',
      [vim.diagnostic.severity.WARN] = ' ',
      [vim.diagnostic.severity.HINT] = ' ',
      [vim.diagnostic.severity.INFO] = ' ',
    },
  },
})

vim.keymap.set('n', '<leader>e', '<cmd>NvimTreeToggle<CR>', { desc = 'NvimTreeToggle' })
vim.keymap.set('n', '\\', '<cmd>NvimTreeToggle<CR>', { desc = 'NvimTreeToggle' })

-- Keybinds to make split navigation easier.
--  Use CTRL+<hjkl> to switch between windows
vim.keymap.set('n', '<C-h>', '<C-w><C-h>', { desc = 'Move focus to the left window' })
vim.keymap.set('n', '<C-l>', '<C-w><C-l>', { desc = 'Move focus to the right window' })
vim.keymap.set('n', '<C-j>', '<C-w><C-j>', { desc = 'Move focus to the lower window' })
vim.keymap.set('n', '<C-k>', '<C-w><C-k>', { desc = 'Move focus to the upper window' })
----------------------------------------------------------------------------------------

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

----------------------------------------------------------------------------------------
local plugins = {
  {
    'saghen/blink.cmp',
    dependencies = { 'rafamadriz/friendly-snippets' },
    version = '1.*',
    opts = {
      appearance = {
        use_nvim_cmp_as_default = false,
        nerd_font_variant = 'mono',
      },
      completion = {
        accept = {
          auto_brackets = {
            enabled = true,
          },
        },
        menu = {
          draw = {
            treesitter = { 'lsp' },
          },
        },
        documentation = {
          auto_show = true,
          auto_show_delay_ms = 200,
        },
        ghost_text = {
          enabled = vim.g.ai_cmp,
        },
      },
      sources = {
        default = { 'lsp', 'path', 'snippets', 'buffer' },
      },
      cmdline = {
        enabled = false,
        keymap = {
          preset = 'cmdline',
          ['<Right>'] = false,
          ['<Left>'] = false,
        },
        sources = {
          default = { 'lsp', 'path', 'snippets', 'buffer' },
        },
        completion = {
          menu = {
            auto_show = true,
          },
          ghost_text = {
            enabled = true,
          },
        },
      },
      keymap = {
        preset = 'super-tab',
        ['<Tab>'] = { 'insert_next' },
        ['<S-Tab>'] = { 'insert_prev' },
        ['<CR>'] = { 'select_and_accept' },
        ['<C-e>'] = { 'hide', 'show' },
      },
    },
  },
  --
  {
    'nvim-tree/nvim-tree.lua',
    version = '*',
    lazy = false,
    dependencies = {
      'nvim-tree/nvim-web-devicons',
    },
    config = function()
      require('nvim-tree').setup({})
    end,
  },

  {
    'batoaqaa/nvim-platformio.lua',
    cond = function()
      -- local platformioRootDir = vim.fs.root(vim.fn.getcwd(), { 'platformio.ini' }) -- cwd and parents
      local platformioRootDir = (vim.fn.filereadable('platformio.ini') == 1) and vim.fn.getcwd() or nil
      if platformioRootDir and vim.fs.find('.pio', { path = platformioRootDir, type = 'directory' })[1] then
        -- if platformio.ini file and .pio folder exist in cwd, enable plugin to install plugin (if not istalled) and load it.
        vim.g.platformioRootDir = platformioRootDir
      elseif (vim.uv or vim.loop).fs_stat(vim.env.XDG_DATA_HOME .. '/lazy/nvim-platformio.lua') == nil then
        -- if nvim-platformio not installed, enable plugin to install it first time
        vim.g.platformioRootDir = vim.fn.getcwd()
      else -- if nvim-platformio.lua installed but disabled, create Pioinit command
        vim.api.nvim_create_user_command('Pioinit', function() --available only if no platformio.ini and .pio in cwd
          vim.api.nvim_create_autocmd('User', {
            pattern = { 'LazyRestore', 'LazyLoad' },
            once = true,
            callback = function(args)
              if args.match == 'LazyRestore' then
                require('lazy').load({ plugins = { 'nvim-platformio.lua' } })
              elseif args.match == 'LazyLoad' then
                vim.notify('PlatformIO loaded', vim.log.levels.INFO, { title = 'PlatformIO' })
                vim.cmd('Pioinit')
              end
            end,
          })
          vim.g.platformioRootDir = vim.fn.getcwd()
          require('lazy').restore({ plguins = { 'nvim-platformio.lua' }, show = false })
        end, {})
      end
      return vim.g.platformioRootDir ~= nil
    end,
    dependencies = {
      { 'akinsho/toggleterm.nvim' },
      { 'nvim-telescope/telescope.nvim' },
      { 'nvim-telescope/telescope-ui-select.nvim' },
      { 'nvim-lua/plenary.nvim' },
      { 'folke/which-key.nvim' },
      {
        'mason-org/mason-lspconfig.nvim',
        dependencies = {
          { 'mason-org/mason.nvim' },
          { 'folke/trouble.nvim' },
          { 'j-hui/fidget.nvim' }, -- status bottom right
        },
      },
    },
  },
}
----------------------------------------------------------------------------------------

require('lazy').setup(plugins, {
  install = {
    missing = true,
  },
})
----------------------------------------------------------------------------------------

vim.api.nvim_create_autocmd('User', {
  pattern = 'LazyVimStarted', -- Triggers after the UI enters and startup time is calculated
  desc = 'Update lazy.nvim plugins in the background',
  callback = function()
    require('lazy').sync({
      wait = false, -- Makes the operation asynchronous
      show = false, -- Prevents the Lazy UI from automatically opening
    })
    -- You can add a notification here if you like
    -- vim.notify("Lazy plugins sync started in background", vim.log.levels.INFO)
  end,
})

-----------------------------------------------------------------------------------------
local isWindows = jit.os == 'Windows'
--
local platformio_core_dir, pynvim_env, pynvim_python, pynvim_lib, pynvim_bin, pynvim_activate
if isWindows then
  platformio_core_dir = vim.env.HOME .. '\\.platformio'
  pynvim_env = platformio_core_dir .. '\\nenv'
  pynvim_bin = pynvim_env .. '\\Scripts'
  pynvim_python = pynvim_bin .. '\\python.exe'
  pynvim_activate = pynvim_bin .. '\\Activate.ps1'
else
  platformio_core_dir = vim.env.HOME .. '/.platformio'
  pynvim_env = platformio_core_dir .. '/nenv'
  pynvim_bin = pynvim_env .. '/bin'
  pynvim_python = pynvim_bin .. '/python3'
  pynvim_activate = pynvim_bin .. '/activate'
  print(pynvim_activate)
end

vim.uv.os_setenv('PLATFORMIO_CORE_DIR', platformio_core_dir)
vim.g.python_host_prog = pynvim_python
vim.g.python3_host_prog = pynvim_python
vim.env.PATH = pynvim_bin .. (isWindows and ';' or ':') .. vim.env.PATH
vim.env.VIRTUAL_ENV = pynvim_env

if vim.fn.isdirectory(platformio_core_dir) == 0 then
  vim.fn.mkdir(platformio_core_dir, 'p')
  -- vim.fn.system({
  --   "wget",
  --   "https://raw.githubusercontent.com/platformio/platformio-core-installer/master/get-platformio.py",
  -- })
  -- vim.fn.system({ "python", "get-platformio.py" })
  -- os.execute((isWindows and "del " or "rm -f ") .. "get-platformio.py*")
end

-- local expand_dir = vim.fn.expand(pynvim_env)
if not vim.uv.fs_stat(pynvim_env) then
  if not isWindows then
    vim.fn.system({ 'python3', '-m', 'venv', pynvim_env })
    vim.fn.system({ 'chmod', '755', '-R', pynvim_bin })
    -- os.execute('chmod 755 -R ' .. pynvim_bin)
    vim.fn.system({ 'source', pynvim_activate })
  else
    vim.fn.system({ 'python', '-m', 'venv', pynvim_env })
    vim.fn.system({ pynvim_activate })
  end
  vim.fn.system({ pynvim_python, '-m', 'pip', 'install', '-U', 'pip' })
  vim.fn.system({ pynvim_python, '-m', 'pip', 'install', 'pynvim' })
  vim.fn.system({ pynvim_python, '-m', 'pip', 'install', 'neovim' })
  vim.fn.system({ pynvim_python, '-m', 'pip', 'install', 'debugpy' })
  vim.fn.system({ pynvim_python, '-m', 'pip', 'install', 'isort' })
  vim.fn.system({ pynvim_python, '-m', 'pip', 'install', 'scons' })
  vim.fn.system({ pynvim_python, '-m', 'pip', 'install', 'yamllint' })
  vim.fn.system({ pynvim_python, '-m', 'pip', 'install', '-U', 'platformio' })
  -- vim.fn.system({ 'pip', 'install', '-U', 'platformio' })
end
------------------------
-----------------------------------------------------------------------------------------
-- platformio config
local pioConfig = {
  lspClangd = {
    enabled = true,
    attach = {
      enabled = true,
      keymaps = true,
    },
  },
  -- menu_key = "<leader>\\", -- replace this menu key  to your convenience
  -- menu_name = "PlatformIO", -- replace this menu name to your convenience
  -- debug = false,
}
local pok, platformio = pcall(require, 'platformio')
if pok then
  -- print("here" .. vim.inspect(pioConfig))
  platformio.setup(pioConfig)
end
