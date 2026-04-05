local M = {}

local utils = require('platformio.utils')
local config = require('platformio').config

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
  if not utils.pio_install_check() then
    return
  end
  utils.cd_pioini()

  utils.shell_cmd_blocking('pio run -t compiledb')
  vim.notify('LSP: compile_commands.jsoncon generation/update completed!', vim.log.levels.INFO)
  M.gitignore_lsp_configs('compile_commands.json')

  -- if vim.fn.has('nvim-0.12') then
  -- local clangd = vim.lsp.get_clients({ name = 'clangd' })[1]
  -- if clangd then
  --   -- print('number of attaced: ' .. #clangd.attached_buffers)
  --   -- print('piolsp: lsp restart ' .. clangd.name)
  -- pcall(vim.cmd.lsp, { args = { 'restart', 'clangd' } })
  M.lsp_restart('clangd')
  -- vim.cmd('lsp restart clangd')
  -- end
  -- else
  -- vim.cmd('LspRestart')
  -- end
end

return M
