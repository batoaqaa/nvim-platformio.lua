local M = {}

--- stylua: ignore
function M.lsp_restart(name)
  -- vim.schedule_wrap(function()
  local clangConfig = _G.get_clangd_config()
  print(vim.inspect(clangConfig))
  vim.lsp.config(name, clangConfig)
  vim.lsp.enable(name, false)
  vim.lsp.enable(name, true)
  vim.cmd('checktime')
  -- end)
end

return M
