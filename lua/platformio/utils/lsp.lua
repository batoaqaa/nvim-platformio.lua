local M = {}

-- stylua: ignore
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
        -- vim.lsp.config(name, configc)
        vim.lsp.config(name, _G.clangd)
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

-- function M.lsp_restarti()
--   local bufnr = nvim_get_current_buf()
--   local clients = lsp.get_clients({ bufnr = bufnr })
--
--   if #clients == 0 then
--     -- I'm using my own implementation of `vim.lsp.enable()`
--     -- To work with default one change group name from `MyLsp` to `nvim.lsp.enable`
--     -- It is not tested with default one, so not sure if it would 100% work.
--     api.nvim_exec_autocmds('FileType', { group = 'MyLsp', buffer = bufnr })
--     return
--   end
--
--   for _, c in ipairs(clients) do
--     local attached_buffers = vim.tbl_keys(c.attached_buffers) ---@type integer[]
--     local config = c.config
--     lsp.stop_client(c.id, true)
--     vim.defer_fn(function()
--       local id = lsp.start(config)
--       if id then
--         for _, b in ipairs(attached_buffers) do
--           lsp.buf_attach_client(b, id)
--         end
--         vim.notify(string.format('Lsp `%s` has been restarted.', config.name))
--       else
--         vim.notify(string.format('Error restarting `%s`.', config.name), vim.log.levels.ERROR)
--       end
--     end, 600)
--   end
-- end

return M
