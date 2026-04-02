-- INFO: LspAttach autocommand start
vim.api.nvim_create_autocmd('LspAttach', {
  group = vim.api.nvim_create_augroup('platformio-lsp-attach', { clear = true }),
  --desc = 'LSP actions',
  callback = function(args)
    local client = assert(vim.lsp.get_client_by_id(args.data.client_id))
    local bufnr = args.buf

    if client then
      -- vim.lsp.set_log_level 'trace'
      -- print('Attaching to: ' .. client.name .. ' attached to buffer ' .. bufnr)
      vim.api.nvim_echo({ { 'Attaching to: ' .. client.name .. ' attached to buffer ' .. bufnr, 'Info' } }, true, {})

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

      ------------------------------------------------------------------
      --- Skip this if you are using blink
      local bok, _ = pcall(require, 'blink')
      if not bok then
        if client:supports_method('textDocument/completion', { bufnr = bufnr }) then
          vim.lsp.completion.enable(true, client.id, args.buf, { autotrigger = true })
        end
        -- vim.diagnostic.config({
        --   current_line = true,
        --   virtual_lines = {
        --     current_line = true,
        --   },
        -- })
        vim.cmd([[set completeopt+=noselect]])
      end

      ------------------------------------------------------------------
      if client.server_capabilities.documentHighlightProvider then
        local highlight_augroup = vim.api.nvim_create_augroup('kickstart-lsp-highlight', { clear = false })
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
          group = vim.api.nvim_create_augroup('kickstart-lsp-detach', { clear = true }),
          callback = function(event)
            vim.lsp.buf.clear_references()
            vim.api.nvim_clear_autocmds({ group = 'kickstart-lsp-highlight', buffer = event.buf })
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

-- --> End LspAttach autocommand
