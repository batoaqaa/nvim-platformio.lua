local M = {}

local lsp_restart = require('platformio.lsp.tools').lsp_restart

-- stylua: ignore
function M.piolsp()
  lsp_restart()
end

return M
