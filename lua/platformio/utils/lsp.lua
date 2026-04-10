local M = {}

--- stylua: ignore
function M.lsp_restart(name)
  if vim.fn.has('nvim-0.12') == 1 then
    -- local clients = vim.lsp.get_clients({ name = name })
    local clangd = vim.lsp.get_clients({ name = name })[1]
    if clangd then
      local ok, err = pcall(vim.cmd.lsp, { args = { 'restart', 'clangd' } })
      if not ok then
        vim.notify('LSP ' .. name .. ' restart failed: ' .. err)
      else
        vim.notify('LSP ' .. name .. ' restarted' .. err)
      end
    end
  else
    local clients = vim.lsp.get_clients({ name = name })
    for _, c in ipairs(clients) do
      local configc = c.config
      c:stop(true)
      vim.defer_fn(function()
        vim.lsp.config(name, configc)
        vim.lsp.enable(name)
        vim.cmd('checktime')
      end, 600)
    end
    -- -- 1. Stop the specific client
    -- for _, client in ipairs(clients) do client:stop() end
    --
    -- -- 2. Reload all loaded buffers to trigger re-attachment for that client
    -- -- (Note: 'checktime' is safer than 'bufdo edit' as it respects unsaved changes)
    -- vim.cmd('checktime')
  end
end

return M
