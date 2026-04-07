local M = {}

local utils = require('platformio.utils')
local config = require('platformio').config

function M.fix_pio_compile_commands()
  local json_path = vim.fn.getcwd() .. '/compile_commands.json'
  if vim.fn.filereadable(json_path) == 0 then
    return
  end

  local file = io.open(json_path, 'r')
  local content = file:read('*all')
  file:close()

  local ok, data = pcall(vim.fn.json_decode, content)
  if not ok or type(data) ~= 'table' then
    return
  end

  -- Use vim.fn.glob and vim.split for Neovim compatibility
  local glob_result = vim.fn.glob(vim.env.HOME .. '/.platformio/packages/toolchain-*/bin/')
  if glob_result == '' then
    return
  end

  -- CORRECTED: Use vim.split() instead of :split()
  local toolchain_bin = vim.split(glob_result, '\n')[1]

  local changed = false
  for _, entry in ipairs(data) do
    if entry.command and not entry.command:match('^/') then
      entry.command = toolchain_bin .. entry.command
      changed = true
    end
  end

  if changed then
    local out_file = io.open(json_path, 'w')
    out_file:write(vim.fn.json_encode(data))
    out_file:close()
    print('PIO: Fixed compiler paths in compile_commands.json')
  end
end

function M.gitignore_lsp_configs(config_file)
  local gitignore_path = vim.fs.joinpath(vim.g.platformioRootDir, '.gitignore')
  local file = io.open(gitignore_path, 'r')
  local pattern = '^%s*' .. vim.pesc(config_file) .. '%s*$'

  if file then
    for line in file:lines() do
      if line:match(pattern) then
        file:close()
        return
      end
    end
    file:close()
  end

  file = io.open(gitignore_path, 'a')
  if file then
    file:write(config_file .. '\n')
    file:close()
  end
end

function M.lsp_restarti(name)
  local clients = vim.lsp.get_clients({ name = name })

  -- if #clients == 0 then
  --   -- I'm using my own implementation of `vim.lsp.enable()`
  --   -- To work with default one change group name from `MyLsp` to `nvim.lsp.enable`
  --   -- It is not tested with default one, so not sure if it would 100% work.
  --   vim.api.nvim_exec_autocmds('FileType', { group = 'nvim.lsp.enable', buffer = 0 })
  --   return
  -- end

  for _, c in ipairs(clients) do
    local configc = c.config
    -- print(vim.inspect(configc))
    c:stop(true)

    vim.defer_fn(function()
      vim.lsp.config(name, configc)
      vim.lsp.enable(name)
    end, 600)
  end
end

function M.lsp_restart(name)
  if vim.fn.has('nvim-0.11') == 1 then
    -- local clients = vim.lsp.get_clients({ name = name })
    local clangd = vim.lsp.get_clients({ name = name })[1]

    if clangd then
      -- Client is active, try to restart
      local ok, err = pcall(vim.cmd.lsp, { args = { 'restart', 'clangd' } })
      if not ok then
        vim.notify('LSP ' .. name .. ' restart failed: ' .. err)
      else
        vim.notify('LSP ' .. name .. ' restarted : ' .. err)
      end
    end
  else
    vim.cmd('LspRestart')
  end
end

function M.piolsp()
  M.fix_pio_compile_commands()

  --
  --
  -- if not utils.pio_install_check() then
  --   return
  -- end
  -- utils.cd_pioini()
  --
  -- utils.shell_cmd_blocking('pio run -t compiledb')
  -- vim.notify('LSP: compile_commands.json generation/update completed!', vim.log.levels.INFO)
  -- M.gitignore_lsp_configs('compile_commands.json')
  --
  -- -- if vim.fn.has('nvim-0.12') then
  -- -- local clangd = vim.lsp.get_clients({ name = 'clangd' })[1]
  -- -- if clangd then
  -- --   -- print('number of attaced: ' .. #clangd.attached_buffers)
  -- --   -- print('piolsp: lsp restart ' .. clangd.name)
  -- -- pcall(vim.cmd.lsp, { args = { 'restart', 'clangd' } })
  -- M.lsp_restart('clangd')
  -- -- vim.cmd('lsp restart clangd')
  -- -- end
  -- -- else
  -- -- vim.cmd('LspRestart')
  -- -- end
end

return M
