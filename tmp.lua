local boilerplate_gen = require('platformio.boilerplate').boilerplate_gen
-- 1. Define the template with 3 placeholders
-- =============================================================================
-- DYNAMIC CLANGD CONFIGURATION TEMPLATE
-- =============================================================================
-- Note: %q is used for paths to handle escaping and spaces automatically.
local clangd_template = [[
{
  cmd = {
    "clangd",
    "--all-scopes-completion",
    "--background-index",
    "--clang-tidy",
    "--compile_args_from=filesystem",
    "--enable-config",
    "--completion-parse=always",
    "--completion-style=detailed",
    "--header-insertion=iwyu",
    "--fallback-style=llvm",
    "-j=12",
    "--log=verbose",
    "--offset-encoding=utf-8",
    "--pch-storage=memory",
    "--pretty",
    "--ranking-model=decision_forest",
    "--sync",
    "--offset-encoding=utf-16",
    "--query-driver=%s",
  },
  filetypes = { 'c', 'cpp', 'objc', 'objcpp', 'cuda', 'proto' },
  root_markers = {
    'platformio.ini',
    'CMakeLists.txt',
    '.clangd',
    '.clang-tidy',
    '.clang-format',
    'compile_commands.json',
    'compile_flags.txt',
    'configure.ac',
    '.git',
  },
  workspace_required = true,
  single_file_support = true,
  init_options = {
       usePlaceholders = true,
       completeUnimported = true,
       fallbackFlags = {%s},
       clangdFileStatus = true,
       compilationDatabasePath = %q,
  }
}
]]

-- 2. Prepare the data
-- =============================================================================
-- LSP SETUP (NEOVIM 0.11+)
-- =============================================================================

local clangd_config = {
  -- on_new_config runs every time client started 
  -- stylua: ignore
  on_new_config = function(new_config, new_root_dir)
    -- Safety check for root_dir
    if not new_root_dir then return end

    -- Safe defaults (Standard clangd behavior)
    local f_flags, q_driver = '', '--query-driver=**'

    if _G.metadata.cc_compiler ~= '' then
      if _G.metadata.triplet and _G.metadata.triplet ~= '' then
        q_driver = '--query-driver=' .. (_G.metadata.query_driver or '**')
        f_flags = string.format('"--target=%s", "--sysroot=%s"', _G.metadata.triplet, _G.metadata.sysroot)
      end
    end

    -- Format the clangd_config string
    local clangd_config = boilerplate_gen([[.clangd_config]], vim.g.platformioRootDir)
    local formatted_str = string.format(clangd_config, q_driver, f_flags, new_root_dir)

    -- Load the string as a Lua table safely
    local ok, table_config = pcall(function() return load('return ' .. formatted_str)() end)

    if ok and table_config then
      -- This merges table_config INTO new_config, overwriting existing values
      local merged = vim.tbl_deep_extend('force', new_config, table_config)
      -- Since we can't reassign the reference, we have to copy the keys back
      for k, v in pairs(merged) do new_config[k] = v end
    else
      -- If template loading fails, alert the user but keep default cmd
      vim.notify('LSP Config Table Generation Failed', vim.log.levels.ERROR)
    end
  end,
}

-- Apply and Enable
vim.lsp.config('clangd', clangd_config)
vim.lsp.enable('clangd')
-- local q_driver = '--query-driver=' .. data.query_driver
-- local f_flags = string.format('"--target=%s", "--sysroot=%s"', data.triplet, data.sysroot)
-- local db_path = vim.uv.cwd() -- Using 0.11+ uv alias
--
-- -- 3. Format the string
-- local formatted_str = string.format(clangd_template, q_driver, f_flags, db_path)
--
-- -- 4. Load it into a real Lua table
-- local status, my_table = pcall(function()
--   return load('return ' .. formatted_str)()
-- end)
