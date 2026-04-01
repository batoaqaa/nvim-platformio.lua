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

-----------------------------------------------------------------------------------------
-- INFO: Mason packages install for lint and formater
-- mason.setup()
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
  'clang-format',
  'biome',
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

require('mason-lspconfig').setup({
  ensure_installed = { 'clangd' },
  automatic_enable = true, -- this will automatically enable LSP servers after install
})

-----------------------------------------------------------------------------------------
local boilerplate_gen = require('platformio.boilerplate').boilerplate_gen
boilerplate_gen([[.clangd]])
boilerplate_gen([[.clangd_cmd]])
boilerplate_gen([[.clang_format]])

local cmd = { 'clangd' }

-- local path = vim.fn.getcwd()
local fname = string.format('%s/.clangd_cmd', vim.fn.getcw())
-- local fname = string.format('%s/.clangd_cmd', vim.g.platformioRootDir)
if vim.fn.filereadable(fname) == 1 then
  ok, result = pcall(vim.fn.readfile, fname)
  if ok then
    cmd = result
    print(vim.inspect(cmd))
  end
end

local capabilities = vim.lsp.protocol.make_client_capabilities()
ok, _ = pcall(require, 'blink')
if ok then
  capabilities = vim.tbl_deep_extend('force', capabilities, require('blink.cmp').get_lsp_capabilities({}, false))
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
end

local config = require('platformio').config
if config.lspClangd.attach.enabled then
  require('platformio.lspAttach')
end
----------------------------------------------------------------------------------
