local M = {}
-- -- Define your dynamic config
-- local clangd_config = {
--   cmd = {
--     'clangd',
--     '--background-index',
--     '--clang-tidy',
--     '--query-driver=**', -- Placeholder index (#cmd)
--   },
-- Important Detail: on_new_config behavior
--
--     If you open a new project in a separate Neovim instance (or a separate tab with a different root), on_new_config runs automatically for that new project.
--     If you edit your config while staying in the same project, you must restart.
--   on_new_config = function(new_config, _)
--     -- 1. Safely run your detection function
--     local status, data = pcall(get_sysroot_triplet, 'C:/Users/batoaqaa/.platformio/packages/toolchain-riscv32-esp/bin')
--
--     if status and data then
--       -- 2. Modify the last item (#) of the cmd table
--       new_config.cmd[#new_config.cmd] = '--query-driver=' .. data.query_driver
--
--       -- 3. Merge fallback flags into init_options
--       new_config.init_options = vim.tbl_deep_extend('force', new_config.init_options or {}, {
--         fallbackFlags = {
--           '--target=' .. data.triplet,
--           '--sysroot=' .. data.sysroot,
--         },
--       })
--     end
--   end,
-- }

-- vim.lsp.config("clangd", {
--   on_new_config = function(config, new_root_dir)
--     -- This is the only place you can safely change this:
--     config.cmd[#config.cmd] = "--query-driver=" .. my_detected_path
--   end,
-- })
-- local function restart_clangd()
--   local clients = vim.lsp.get_clients({ name = "clangd" })
--   for _, client in ipairs(clients) do
--     client.stop() -- Stops the process
--   end
--   -- Neovim 0.11+ will automatically try to restart enabled servers
--   -- if a valid buffer is open, or you can trigger a reload.
--   vim.cmd("edit")
-- end
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
    for _, client in ipairs(clients) do
      local clangd_config = client.config
      client:stop(true)
      -- -- Apply the config using the new 0.11+ API
      local clangConfig = _G.get_clangd_config()
      print(vim.inspect(clangConfig))
      vim.lsp.config('clangd', clangConfig)
      vim.lsp.enable('clangd', false)
      vim.lsp.enable('clangd', true)
      -- vim.lsp.config('clangd', clangd_config)
      -- vim.lsp.enable('clangd')
      vim.cmd('checktime')
      vim.cmd('edit')
      -- vim.schedule_wrap(function()
      --   -- vim.defer_fn(function()
      --   --   -- vim.lsp.config(name, configc)
      --   vim.lsp.config(name, _G.clangd)
      --   vim.lsp.enable(name)
      --   vim.cmd('checktime')
      --   -- end, 600)
      -- end)
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
