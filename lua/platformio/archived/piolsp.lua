local M = {}

local lsp = require('platformio.lsp.tools')

-- stylua: ignore
function M.piolsp()
  lsp.lsp_restart()
  -- local ok, err = pcall(vim.cmd.lsp, { args = { 'restart' } })
  -- if ok then vim.notify('LSP restarted' .. err)
  -- else vim.notify('LSP restart failed: ' .. err) end
  -- M.fix_pio_compile_commands()
end

return M
