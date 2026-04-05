-- INFO: LspAttach autocommand start
vim.api.nvim_create_autocmd('LspAttach', {
  group = vim.api.nvim_create_augroup('platformio-lsp-attach', { clear = true }),
  callback = function(args)
    local client = assert(vim.lsp.get_client_by_id(args.data.client_id))
    local bufnr = args.buf

    if client then
      vim.api.nvim_echo({ { 'Attaching ' .. client.name .. ' to buffer ' .. bufnr, 'Info' } }, true, {})

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

      -- use lsp completion if no blink
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
  group = vim.api.nvim_create_augroup('LspCleanup', { clear = true }),
  callback = function(arg)
    local bufnr = arg.buf
    local client = vim.lsp.get_client_by_id(arg.data.client_id)
    if client and client.attached_buffers then
      vim.api.nvim_echo({ { 'Detaching ' .. client.name .. ' from buffer ' .. bufnr, 'Info' } }, true, {})
      -- local count = 0
      -- for _ in pairs(client.attached_buffers) do
      --   count = count + 1
      -- end
      --
      -- if count == 1 then
      --   client:stop(true)
      -- end
    end
  end,
})

-- --> End LspAttach autocommand
