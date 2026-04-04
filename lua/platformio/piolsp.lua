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
    if #vim.lsp.get_clients() > 0 then
      vim.cmd('lsp restart')
    end
  else
    vim.cmd('LspRestart')
  end

  vim.notify('LSP: compile_commands.jsoncon generation/update completed!', vim.log.levels.INFO)
end

return M
