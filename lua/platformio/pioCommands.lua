local M = {}

local misc = require('platformio.utils.misc')
local ToggleTerminal = require('platformio.utils.term').ToggleTerminal

-- stylua: ignore
function M.piolsp()
  require('platformio.lsp.tools').lsp_restart('clangd')
  -- local ok, err = pcall(vim.cmd.lsp, { args = { 'restart' } })
  -- if ok then vim.notify('LSP restarted' .. err)
  -- else vim.notify('LSP restart failed: ' .. err) end
  -- M.fix_pio_compile_commands()
end

function M.piocmd(cmd_table, direction)
  if not misc.pio_install_check() then
    return
  end

  misc.cd_pioini()

  if cmd_table[1] == '' then
    ToggleTerminal('', direction)
  else
    local cmd = 'pio '
    for _, v in pairs(cmd_table) do
      cmd = cmd .. ' ' .. v
    end
    ToggleTerminal(cmd, direction)
  end
end

function M.piodebug(args_table)
  if not misc.pio_install_check() then
    return
  end

  misc.cd_pioini()

  local command = 'pio debug --interface=gdb -- -x .pioinit'
  -- local command = string.format('pio debug --interface=gdb -- -x .pioinit %s', utils.extra)
  ToggleTerminal(command, 'float')
end

function M.piomon(args_table)
  if not misc.pio_install_check() then
    return
  end

  misc.cd_pioini()

  local command = nil
  if #args_table == 0 then
    command = 'pio device monitor'
  elseif #args_table == 1 then
    local baud_rate = args_table[1]
    command = string.format('pio device monitor -b %s', baud_rate)
  elseif #args_table == 2 then
    local baud_rate = args_table[1]
    local port = args_table[2]
    command = string.format('pio device monitor -b %s -p %s', baud_rate, port)
  end

  if command == nil then
    vim.notify('Usage: Piomon <baud> <port>', vim.log.levels.ERROR)
  else
    ToggleTerminal(command, 'horizontal')
  end
end

return M
