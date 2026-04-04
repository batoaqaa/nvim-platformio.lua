local M = {}

local utils = require('platformio.utils')
local config = require('platformio').config

local function gitignore_lsp_configs(config_file)
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

function M.piolsp()
  if not utils.pio_install_check() then
    return
  end
  utils.cd_pioini()

  utils.shell_cmd_blocking('pio run -t compiledb')
  gitignore_lsp_configs('compile_commands.json')

  if vim.fn.has('nvim-0.12') then
    -- if #vim.lsp.get_clients() > 0 then
    -- local getClients = vim.lsp.get_clients()
    --
    -- for _, cli in ipairs(getClients) do
    --   if vim.iter(cli.attached_buffers):count() == 0 then
    --     print('client stop')
    --     cli:stop(true)
    --   end
    -- end
    print('piolsp: client restart')
    vim.cmd('lsp restart')
    -- if next(vim.lsp.get_clients()) ~= nil then
    --   if vim.tbl_count(getClients.attached_buffers) == 0 then
    --     print('client stop piolsp')
    --     -- getClients.stop()
    --   else
    --     print('client restart')
    --     vim.cmd('lsp restart')
    --   end
    -- end
  else
    vim.cmd('LspRestart')
  end

  vim.notify('LSP: compile_commands.jsoncon generation/update completed!', vim.log.levels.INFO)
end

return M
