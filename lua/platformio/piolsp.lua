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
    local attached_buffers = vim.tbl_keys(c.attached_buffers) ---@type integer[]
    print(vim.inspect(c.attached_buffers))
    local configc = c.config
    vim.lsp.stop_client(c.id, true)
    vim.defer_fn(function()
      local id = vim.lsp.start(configc)
      if id then
        for _, b in ipairs(attached_buffers) do
          vim.lsp.buf_attach_client(b, id)
        end
        vim.notify(string.format('Lsp `%s` has been restarted.', config.name))
      else
        vim.notify(string.format('Error restarting `%s`.', config.name), vim.log.levels.ERROR)
      end
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
  if not utils.pio_install_check() then
    return
  end
  utils.cd_pioini()

  utils.shell_cmd_blocking('pio run -t compiledb')
  vim.notify('LSP: compile_commands.json generation/update completed!', vim.log.levels.INFO)
  M.gitignore_lsp_configs('compile_commands.json')

  -- if vim.fn.has('nvim-0.12') then
  -- local clangd = vim.lsp.get_clients({ name = 'clangd' })[1]
  -- if clangd then
  --   -- print('number of attaced: ' .. #clangd.attached_buffers)
  --   -- print('piolsp: lsp restart ' .. clangd.name)
  -- pcall(vim.cmd.lsp, { args = { 'restart', 'clangd' } })
  M.lsp_restarti('clangd')
  -- vim.cmd('lsp restart clangd')
  -- end
  -- else
  -- vim.cmd('LspRestart')
  -- end
end

return M
