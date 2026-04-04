local platformio_lsp_attach = vim.api.nvim_create_augroup('platformio-lsp-attach', { clear = false })
-- INFO: LspAttach autocommand start
vim.api.nvim_create_autocmd('LspAttach', {
  -- group = vim.api.nvim_create_augroup('platformio-lsp-attach', { clear = true }),
  group = platformio_lsp_attach,
  --desc = 'LSP actions',
  callback = function(args)
    local client = assert(vim.lsp.get_client_by_id(args.data.client_id))
    local bufnr = args.buf

    if client then
      -- vim.lsp.set_log_level 'trace'
      -- print('Attaching to: ' .. client.name .. ' attached to buffer ' .. bufnr)
      vim.api.nvim_echo({ { 'Attaching to: ' .. client.name .. ' attached to buffer ' .. bufnr, 'Info' } }, true, {})

      -- if client.name == 'lua_ls' then
      --   -- client.server_capabilities.documentFormattingProvider = false
      --   if client:supports_method('textDocument/formatting') then
      --     vim.lsp.buf.format({
      --       bufnr = bufnr,
      --       async = false,
      --       timeout_ms = 10000,
      --       id = client.id,
      --       filter = function(c)
      --         return c.id == client.id
      --       end,
      --     })
      --   end
      -- end
      -- print('lua_ls 0')
      ------------------------------------------------------------------
      if client.name == 'clangd' then
        vim.api.nvim_buf_create_user_command(0, 'LspClangdSwitchSourceHeader', function()
          local method_name = 'textDocument/switchSourceHeader'
          local params = vim.lsp.util.make_text_document_params(bufnr)
          client.request(method_name, params, function(err, result)
            if err then
              error(tostring(err))
            end
            if not result then
              vim.notify('corresponding file cannot be determined')
              return
            end
            vim.cmd.edit(vim.uri_to_fname(result))
          end, bufnr)
        end, { desc = 'Switch between source/header' })
      end

      -- if client and client.server_capabilities.completionProvider then
      -- if client:supports_method('textDocument/completion', { bufnr = bufnr }) then

      local ok, _ = pcall(require, 'blink.cmp')
      if not ok then
        if client:supports_method('textDocument/completion') then
          vim.opt.completeopt = { 'menu', 'menuone', 'noselect', 'noinsert', 'fuzzy', 'popup' }

          -- Enable native completion for this specific client and buffer
          vim.lsp.completion.enable(true, client.id, args.buf, { autotrigger = true })
          vim.keymap.set('i', '<C-Space', function()
            vim.lsp.completion.get()
          end)
        end
      end

      -- Inlay hints
      if client:supports_method('textDocument/inlayHints') then
        vim.lsp.inlay_hint.enable(true, { bufnr = bufnr })
      end

      if client:supports_method('textDocument/documentColor') then
        -- vim.lsp.document_color.enable(true, args.buf, { style = 'background', -- 'background', 'foreground', or 'virtual' })
        vim.lsp.document_color.enable(true, {
          bufnr = bufnr,
          style = 'inline', -- This is the modern 0.11 way to show color icons
        })
      end

      ------------------------------------------------------------------
      if client:supports_method('documentHighlightProvider') then
        local highlight_augroup = vim.api.nvim_create_augroup('platformio-lsp-highlight', { clear = false })
        vim.api.nvim_create_autocmd({ 'CursorHold', 'CursorHoldI' }, {
          buffer = bufnr,
          group = highlight_augroup,
          callback = vim.lsp.buf.document_highlight,
        })
        --
        vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
          buffer = bufnr,
          group = highlight_augroup,
          callback = vim.lsp.buf.clear_references,
        })
        --
        vim.api.nvim_create_autocmd('LspDetach', {
          group = highlight_augroup,
          -- group = vim.api.nvim_create_augroup('platformio-lsp-detach', { clear = true }),
          callback = function(event)
            vim.lsp.buf.clear_references()
            vim.api.nvim_clear_autocmds({ group = 'platformio-lsp-highlight', buffer = event.buf })
          end,
        })
        --
      end

      ------------------------------------------------------------------
      local config = require('platformio').config
      if config.lspClangd.attach.keymaps then
        local lspkeymaps = require('platformio.lspKeymaps')
        lspkeymaps.lspKeymaps(client, bufnr)
      end
    end

    ------------------------------------------------------------------
    vim.cmd([[autocmd FileType * set formatoptions-=ro]])
    --
  end,
})

vim.api.nvim_create_autocmd('LspDetach', {
  -- group = platformio_lsp_attach,
  group = vim.api.nvim_create_augroup('LspCleanup', { clear = true }),
  callback = function(arg)
    local cl = vim.lsp.get_client_by_id(arg.data.client_id)
    if not cl then
      return
    end

    print('client detatch 0')
    if cl.attached_buffers then
      print('detatch0: client stop')
      print(vim.inspect(cl.attached_buffers))

      local count = 0
      for _ in pairs(cl.attached_buffers) do
        count = count + 1
      end

      if count == 1 then
        cl:stop(true)
      end

      -- if vim.iter(cl.attached_buffers):count() == 1 then
      --   cl:stop(true)
      -- end
    end
    -- if cl.attached_buffers and vim.tbl_isempty(cl.attached_buffers) then
    --   print('detatch0: client stop')
    --   cl:stop(true)
    -- end
    --
    -- -- Run this to kill any LSP client not attached to a buffer
    -- for _, client in ipairs(vim.lsp.get_clients()) do
    --   if client.attached_buffers and vim.tbl_isempty(client.attached_buffers) then
    --     -- if vim.iter(client.attached_buffers):count() == 0 then
    --     print('detatch1: client stop')
    --     client:stop(true)
    --   end
    -- end

    -- for _, cli in ipairs(vim.lsp.get_clients()) do
    --   if cli.attached_buffers and vim.tbl_isempty(cli.attached_buffers) then
    --     -- if vim.iter(cli.attached_buffers):count() == 0 then
    --     print('detatch: client stop')
    --     cli:stop(true)
    --   end
    -- end
  end,
})

-- --> End LspAttach autocommand
