---------------------------------------------------------------------------------
-- INFO: Mason packages install for lint and formater

local fok, fidget = pcall(require, 'fidget')
if fok then
  fidget.setup({})
end

local tok, trouble = pcall(require, 'trouble')
if tok then
  trouble.setup({})
end

-- mason.setup()
local mason = require('mason')

mason.setup({
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
-- List of packages you want Mason to ensure are installed
local ensure_installed = {
  -- 'clang-format',
}

-- Mason function to install or ensure formatters/linters are installed
local mr = require('mason-registry')
mr.refresh(function()
  for _, tool in ipairs(ensure_installed) do
    local ok, p = pcall(mr.get_package, tool)
    if ok and p then
      if not p:is_installed() then
        if not p:is_installing() then
          p:install({}, function(success, _)
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

require('mason-lspconfig').setup({
  ensure_installed = { 'clangd' },
  -- automatic_enable = true, -- this will automatically enable LSP servers after install
})

local cmd = {
  'clangd',
  '--all-scopes-completion',
  '--background-index',
  '--clang-tidy',
  '--compile_args_from=filesystem',
  '--compile-commands-dir=.', -- so this is in default directory (parent of /src) no need for it.
  '--enable-config',
  '--completion-parse=always',
  '--completion-style=detailed',
  '--header-insertion=iwyu',
  '--header-insertion-decorators',
  '-j=12',
  '--log=verbose', -- for debugging
  --   '--log=error',
  '--offset-encoding=utf-8',
  '--pch-storage=memory',
  '--pretty',
  '--query-driver=**',
  '--ranking-model=decision_forest',
}

local path = vim.fn.getcwd()
local fname = string.format('%s\\.clangd_cmd', path)
if vim.fn.filereadable(fname) == 1 then
  local ok, result = pcall(vim.fn.readfile, fname)
  if ok then
    cmd = result
    -- print(vim.inspect(cmd))
  end
end

local capabilities = vim.lsp.protocol.make_client_capabilities()
local bok, _ = pcall(require, 'blink')
if bok then
  capabilities = vim.tbl_deep_extend('force', capabilities, require('blink.cmp').get_lsp_capabilities({}, false))
end
---@type vim.lsp.Config
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
  capabilities = capabilities,
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

----------------------
local mok, mason_lspconfig = pcall(require, 'mason-lspconfig')
if mok then
  mason_lspconfig.setup({})
  local boilerplate_gen = require('platformio.boilerplate').boilerplate_gen
  boilerplate_gen('.clangd')
end

local config = require('platformio').config
if config.lspClangd.attach.enabled then
  require('platformio.lspAttach')
end
----------------------------------------------------------------------------------
