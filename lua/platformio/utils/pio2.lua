local M = {}
local Terminal = require('toggleterm.terminal').Terminal

-- State Management
M.queue = {}
M.is_processing = false
M.current_callback = nil

-- 1. Persistent Terminal Configuration
-- Defined once to avoid "cannot assign after loading" errors.
local ToggleTerminal = require('platformio.utils.term2').ToggleTerminal
_G.metadata.isBusy = true
local pio_terminal = ToggleTerminal('', 'float')
-- local pio_terminal = Terminal:new({
--   id = 99,
--   direction = 'float',
--   close_on_exit = false, -- Keep window open so user can see results
--   -- Proxy callback: uses the variable defined in M.run_shell_job
--   on_exit = function(t, job, exit_code)
--     if type(current_callback) == 'function' then
--       current_callback(t, job, exit_code)
--     end
--   end,
--   -- Dynamic focus/scroll handler
--   on_open = function(term)
--     if term.window and vim.api.nvim_win_is_valid(term.window) then
--       vim.api.nvim_set_current_win(term.window)
--       vim.cmd('normal! G') -- Scroll to bottom
--     end
--   end,
-- })

-- 2. The Optimized Path Fixer
function M.compile_commandsFix()
  local filename = vim.uv.cwd() .. '/compile_commands.json'

  -- Nil/Error Check: Ensure file exists
  if vim.fn.filereadable(filename) == 0 then
    M.process_queue()
    return
  end

  -- Atomic Read
  local lines = vim.fn.readfile(filename)
  if not lines or #lines == 0 then
    M.process_queue()
    return
  end

  local content = table.concat(lines, '\n')
  local ok, data = pcall(vim.json.decode, content)

  -- Nil/Error Check: Valid JSON
  if not ok or type(data) ~= 'table' then
    vim.notify('PIO Fix: Invalid JSON', vim.log.levels.ERROR)
    M.process_queue()
    return
  end

  -- Build Path Map from Toolchain Metadata
  local path_map = {}
  local toolchain = _G.metadata and _G.metadata.toolchain or ''
  if toolchain ~= '' then
    local bin_path = toolchain .. '/bin/*'
    for _, full_path in ipairs(vim.fn.glob(bin_path, false, true)) do
      local name = full_path:match('([^/\\\\]+)$'):gsub('%.exe$', '')
      path_map[name] = full_path
    end
  end

  -- Update Entries
  local modified = false
  for _, entry in ipairs(data) do
    local cmd = entry.command or ''
    local first_token = cmd:match('^%S+')
    -- If driver is relative, replace with absolute path from map
    if first_token and not (first_token:sub(1, 1) == '/' or first_token:match('^%a:')) then
      local short_name = first_token:gsub('%.exe$', '')
      if path_map[short_name] then
        entry.command = path_map[short_name] .. cmd:sub(#first_token + 1)
        modified = true
      end
    end
  end

  -- Save if changes made
  if modified then
    local json_str = vim.json.encode(data)
    local formatted = vim.fn.system('python -m json.tool', json_str)
    if vim.v.shell_error == 0 then
      vim.fn.writefile(vim.split(formatted, '\n'), filename)
      vim.notify('PIO: Fixed compile_commands.json', vim.log.levels.INFO)
    end
  end

  -- Proceed to next task (or final shell handoff)
  M.process_queue()
end

-- 3. Shell Runner (Queue and Manual)
function M.run_shell_job(cmd, on_exit_callback, is_manual)
  if not cmd or cmd == '' then
    return
  end

  pio_terminal.cmd = cmd

  if is_manual then
    -- Manual Mode: Clear callback to prevent queue interference
    M.current_callback = nil
  else
    -- Queue Mode: Set logic for the next step
    M.current_callback = function(_, _, exit_code)
      if exit_code == 0 then
        if type(on_exit_callback) == 'function' then
          on_exit_callback()
        end
        -- Use schedule to avoid race conditions with terminal closing/opening
        vim.schedule(function()
          M.process_queue()
        end)
      else
        vim.notify('PIO Queue Failed: ' .. cmd, vim.log.levels.ERROR)
        M.queue = {}
        M.is_processing = false
      end
    end
  end

  pio_terminal:spawn()
end

-- 4. The Queue Controller
function M.process_queue()
  local task = table.remove(M.queue, 1)

  -- Nil Check: End of queue
  if not task then
    M.is_processing = false
    return
  end

  M.is_processing = true

  -- Decide execution path
  if task.cmd then
    M.run_shell_job(task.cmd, task.cb, false)
  elseif type(task.cb) == 'function' then
    -- For Lua tasks (like Fixer), run directly
    vim.schedule(task.cb)
  else
    -- Fallback: Skip invalid tasks
    M.process_queue()
  end
end

-- 5. Main Entry Point
function M.setup_project(board_id, framework)
  if M.is_processing then
    vim.notify('PIO: Queue already running', vim.log.levels.WARN)
    return
  end

  -- Determine OS Shell for the final handoff
  local shell = vim.o.shell or (vim.fn.has('win32') == 1 and 'cmd' or 'bash')

  M.queue = {
    {
      cmd = string.format('pio project init --board %s -O "framework=%s"', board_id, framework),
    },
    {
      cmd = 'pio run -t compiledb',
    },
    {
      cb = M.compile_commandsFix, -- Internal: calls M.process_queue()
    },
    {
      -- FINAL TASK: Spawn an interactive shell
      -- This keeps the terminal alive so the user can type or use :send()
      cmd = shell,
      cb = function()
        vim.notify('PIO: Automation complete. Shell ready.', vim.log.levels.INFO)
      end,
    },
  }

  M.process_queue()
end

return M
