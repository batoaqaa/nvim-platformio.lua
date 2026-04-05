---------------------------------------------------------------------------------
local ok, result
ok, result = pcall(require, 'fidget')
if ok then
  result.setup({})
end

-----------------------------------------------------------------------------------------
ok, result = pcall(require, 'trouble')
if ok then
  result.setup({})
end

----------------------------------------------------------------------------------------
-- INFO: setup and install mason packages
-----------------------------------------------------------------------------------------
ok, result = pcall(require, 'mason')
if ok then
  result.setup({
    PATH = 'append',
    ui = {
      border = 'single',
      icons = {
        package_installed = '✓',
        package_pending = '➜',
        package_uninstalled = '✗',
      },
    },
  })
end

-- List of packages you want Mason to ensure are installed
local ensure_installed = {
  -- 'clang-format', embeded in clangd
  -- 'stylua',
}
-- call mason-registry function to install or ensure formatters/linters are installed
local mr = require('mason-registry')
mr.refresh(function()
  for _, tool in ipairs(ensure_installed) do
    ok, result = pcall(mr.get_package, tool)
    if ok and result then
      if not result:is_installed() then
        if not result:is_installing() then
          result:install({}, function(success, _)
            if not success then
              vim.defer_fn(function()
                vim.notify(tool .. ' failed to install', vim.log.levels.ERROR)
              end, 0)
            end
          end)
        else
          vim.defer_fn(function()
            vim.notify(tool .. ' already installed', vim.log.levels.WARN)
          end, 0)
        end
      end
    else
      vim.defer_fn(function()
        vim.notify('Failed to get package: ' .. tool, vim.log.levels.WARN)
      end, 0)
    end
  end
end)

----------------------------------------------------------------------------------------
-- INFO: install clangd using mason-lspconfig
-----------------------------------------------------------------------------------------
local mok, mason_lspconfig = pcall(require, 'mason-lspconfig')
if mok then
  mason_lspconfig.setup({
    -- ensure_installed = { 'clangd', 'pyrefly' },
    ensure_installed = { 'clangd', 'lua_ls', 'pyrefly' },
    automatic_enable = true, -- this will automatically enable LSP servers after lsp.config
  })
end

local capabilities = vim.lsp.protocol.make_client_capabilities({
  textDocument = {
    -- Folding capabilities for nvim-ufo
    foldingRange = {
      dynamicRegistration = false,
      lineFoldingOnly = true,
    },
  },
})
local bok, blink = pcall(require, 'blink.cmp')
if bok then
  -- capabilities = vim.tbl_deep_extend('force', capabilities, blink.get_lsp_capabilities({}, false))
  capabilities = blink.get_lsp_capabilities(capabilities)
end

-- INFO: 1
vim.lsp.config('*', {
  capabilities = capabilities,
  root_markers = { '.git' },
  workspace_required = false,
})
----------------------------------------------------------------------------------------
-- INFO: configure clangd lsp server
-----------------------------------------------------------------------------------------
local cmd = { 'clangd' }
local fname = string.format('%s/.clangd_cmd', vim.fn.getcwd())
if vim.fn.filereadable(fname) == 1 then
  ok, result = pcall(vim.fn.readfile, fname)
  if ok then
    cmd = result
    -- print(vim.inspect(cmd))
  end
end

local clangd = {
  cmd = cmd,
  filetypes = { 'c', 'cpp', 'objc', 'objcpp', 'cuda', 'proto' },
  root_markers = {
    'CMakeLists.txt',
    '.clangd',
    '.clang-tidy',
    '.clang-format',
    'compile_commands.json',
    'compile_flags.txt',
    'configure.ac',
    '.git',
    vim.uv.cwd(),
  },
  workspace_required = true,
  single_file_support = true,
  init_options = {
    usePlaceholders = true,
    completeUnimported = true,
    fallback_flags = { '-std=c++17' },
    clangdFileStatus = true,
    compilationDatabasePath = vim.fn.getcwd(),
  },
}
vim.lsp.config('clangd', clangd)

----------------------------------------------------------------------------------------
-- INFO: configure clangd lsp server
-----------------------------------------------------------------------------------------
local lua_ls = {
  cmd = { 'lua-language-server' },
  filetypes = { 'lua' },
  root_markers = {
    '.luarc.json',
    '.luarc.jsonc',
    '.luacheckrc',
    '.stylua.toml',
    'selene.toml',
    'selene.yml',
    '.git',
  },
  settings = {
    Lua = {
      hint = {
        enable = true,
        arrayIndex = 'Enable',
        await = true,
        paramName = 'All',
        paramType = true,
        semicolon = 'Disable',
        setType = true,
      },
      telemetry = { enable = false },
      diagnostics = { globals = { 'vim' } },
      runtime = {
        -- Specify LuaJIT for Neovim
        version = 'LuaJIT',
        -- Include Neovim runtime files
        path = vim.split(package.path, ';'),
      },
      workspace = {
        checkThirdParty = false,
        library = {
          vim.env.VIMRUNTIME,
          '${3rd}/luv/library',
          './lua',
          vim.api.nvim_get_runtime_file('', true),
          -- Depending on the usage, you might want to add additional paths here.
          -- "${3rd}/busted/library",
        },
      },
    },
  },
}
vim.lsp.config('lua_ls', lua_ls)

-- local stylua = {
--   cmd = { 'stylua', '--search-parent-directories', '--stdin-filepath', '$FILENAME', '-' },
--   filetypes = { 'lua' },
--   root_markers = { 'stylua.toml', '.stylua.toml', '.git' },
-- }
-- vim.lsp.config('stylua', stylua)
-- vim.lsp.enable('stylua')

local pyrefly = {
  name = 'pyrefly',
  cmd = { 'pyrefly', 'lsp' },
  filetypes = { 'python' },
  root_markers = { 'pyrefly.toml', 'pyproject.toml', 'setup.py', 'setup.cfg', 'requirements.txt', 'Pipfile', '.git' },
  settings = {
    python = {
      pythonPath = vim.env.VIRTUAL_ENV,
      -- venvPath = vim.env.VIRTUAL_ENV,
    },
  },
}
vim.lsp.config('pyrefly', pyrefly)

----------------------------------------------------------------------------------------
-- INFO: create clangd required files
-----------------------------------------------------------------------------------------
local boilerplate_gen = require('platformio.boilerplate').boilerplate_gen
boilerplate_gen([[.clangd]], vim.g.platformioRootDir)
boilerplate_gen([[.clangd]], vim.env.PLATFORMIO_CORE_DIR)
boilerplate_gen([[.clangd]], vim.fn.stdpath('data'))
print(vim.env.XDG_CONFIG_HOME)
boilerplate_gen([[.clangd]], vim.env.XDG_CONFIG_HOME .. '/clangd', 'config.yaml')
boilerplate_gen([[.clangd_cmd]], vim.g.platformioRootDir)
boilerplate_gen([[.clang-format]], vim.g.platformioRootDir)
boilerplate_gen([[.stylua.toml]], vim.g.platformioRootDir)

-- require('platformio.piolsp').piolsp()
if vim.fn.has('nvim-0.12') then
  if #vim.lsp.get_clients() > 0 then
    vim.cmd('lsp restart')
  end
else
  vim.cmd('LspRestart')
end

local config = require('platformio').config
if config.lspClangd.attach.enabled then
  require('platformio.lspAttach')
end
----------------------------------------------------------------------------------
