local M = {}
local Terminal = require('toggleterm.terminal').Terminal

M.queue = {}
M.is_processing = false

-- 1. Persistent Terminal Instance
-- Using a high ID (99) to avoid clashing with your usual terminals
local pio_terminal = Terminal:new({
  id = 99,
  direction = 'float',
  close_on_exit = false,
  hidden = true, -- Don't show in the standard toggle cycle
})

-- 2. The Optimized Path Fixer
function M.compile_commandsFix()
  local filename = vim.uv.cwd() .. '/compile_commands.json'
  if vim.fn.filereadable(filename) == 0 then
    M.process_queue()
    return
  end

  -- Atomic read using built-in Vim function
  local content = table.concat(vim.fn.readfile(filename), '\n')
  local ok, data = pcall(vim.json.decode, content)
  if not ok or type(data) ~= 'table' then
    M.process_queue()
    return
  end

  -- 1. Build Path Map (Scan toolchain)
  local path_map = {}
  local toolchain_bin = (_G.metadata and _G.metadata.toolchain or '') .. '/bin/*'
  for _, full_path in ipairs(vim.fn.glob(toolchain_bin, false, true)) do
    local name = full_path:match('([^/\\\\]+)$'):gsub('%.exe$', '')
    path_map[name] = full_path
  end

  -- 2. Update Entries efficiently with string matching
  local modified = false
  for _, entry in ipairs(data) do
    local cmd = entry.command or ''
    local first_token = cmd:match('^%S+') -- Grab only the compiler driver

    -- Fix if it's a relative path (doesn't start with / or Drive letter)
    if first_token and not (first_token:sub(1, 1) == '/' or first_token:match('^%a:')) then
      local short_name = first_token:gsub('%.exe$', '')
      if path_map[short_name] then
        -- Replace only the first token to preserve arguments
        entry.command = path_map[short_name] .. cmd:sub(#first_token + 1)
        modified = true
      end
    end
  end

  -- 3. Save with Python formatting
  if modified then
    local json_str = vim.json.encode(data)
    local formatted = vim.fn.system('python -m json.tool', json_str)

    if vim.v.shell_error == 0 then
      -- Atomic write back to disk
      vim.fn.writefile(vim.split(formatted, '\n'), filename)
      vim.notify('compiledb: paths fixed', vim.log.levels.INFO)
    else
      vim.notify('PIO Fix: Python formatting failed', vim.log.levels.ERROR)
    end
  end

  -- Chain to next task
  M.process_queue()
end

-- 3. Shell Runner via ToggleTerm
function M.run_shell_job(cmd, on_exit_callback, is_manual)
  pio_terminal.cmd = cmd

  if is_manual then
    -- Manual mode: No queue logic, just run and stop
    pio_terminal.on_exit = nil
  else
    -- Queue mode: Define sequential behavior
    pio_terminal.on_exit = function(_, _, exit_code)
      if exit_code == 0 then
        if on_exit_callback then
          on_exit_callback()
        end
        -- Always schedule queue moves to avoid terminal-state race conditions
        vim.schedule(function()
          M.process_queue()
        end)
      else
        vim.notify('PIO Queue Stopped: Error in ' .. cmd, vim.log.levels.ERROR)
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

  if not task then
    M.is_processing = false
    return
  end

  M.is_processing = true

  if task.cmd then
    M.run_shell_job(task.cmd, task.cb, false)
  elseif type(task.cb) == 'function' then
    -- For Lua-only tasks, they must eventually call M.process_queue()
    vim.schedule(task.cb)
  end
end

-- 5. Public API
-- Use this for the sequential build/init flow
function M.setup_project(board_id, framework)
  if M.is_processing then
    vim.notify('PIO: Processing already in progress', vim.log.levels.WARN)
    return
  end

  M.queue = {
    {
      cmd = string.format('pio project init --board %s -O "framework=%s"', board_id, framework),
      cb = function()
        vim.notify('Init Complete')
      end,
    },
    {
      cmd = 'pio run -t compiledb',
    },
    {
      cb = M.compile_commandsFix,
    },
  }

  M.process_queue()
end

-- Use this for one-off commands that don't trigger the queue
function M.run_manual(cmd)
  M.run_shell_job(cmd, nil, true)
end

return M
