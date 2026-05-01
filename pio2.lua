local M = {}

M.selected_framework = ''

local misc = require('platformio.utils.misc')
local lsp_restart = require('platformio.lspConfig.tools').lsp_restart

local term = require('platformio.utils.term')
-- term.on_stdout_handler = nil

M.is_processing = false
------------------------------------------------------
-- stylua: ignore
function M.compile_commandsFix()
  local filename = vim.uv.cwd() .. '/compile_commands.json'
  if vim.fn.filereadable(filename) == 0 then return end

  -- Atomic read using built-in Vim function
  local content = table.concat(vim.fn.readfile(filename), "\n")
  local ok, data = pcall(vim.json.decode, content)
  if not ok or type(data) ~= 'table' then return end

  -- 1. Build Path Map (Scan toolchain)
  local path_map = {}
  local toolchain_bin = (_G.metadata and _G.metadata.toolchain or "") .. '/bin/*'
  for _, full_path in ipairs(vim.fn.glob(toolchain_bin, false, true)) do
    local name = full_path:match('([^/\\\\]+)$'):gsub('%.exe$', '')
    path_map[name] = full_path
  end

  -- 2. Update Entries efficiently with string matching
  local modified = false
  for _, entry in ipairs(data) do
    local cmd = entry.command or ""
    local first_token = cmd:match("^%S+") -- Grab only the compiler driver

    -- Fix if it's a relative path (doesn't start with / or Drive letter)
    if first_token and not (first_token:sub(1,1) == '/' or first_token:match('^%a:')) then
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
      vim.fn.writefile(vim.split(formatted, "\n"), filename)
      vim.notify('compiledb: paths fixed', vim.log.levels.INFO)
    else
      vim.notify('PIO Fix: Python formatting failed', vim.log.levels.ERROR)
    end
  end
end

-- function M.compile_commandsFix()
--   local filename = vim.uv.cwd() .. '/compile_commands.json'
--   local content = vim.fn.readfile(filename)
--   if #content == 0 then return end
--
--   local ok, data = pcall(vim.json.decode, table.concat(content, "\n"))
--   if not ok or type(data) ~= 'table' then return end
--
--   -- 1. Build Path Map (Scan toolchain)
--   local path_map = {}
--
--   local pio_binaries = _G.metadata.query_driver or "/bin/*"
--   -- local pio_binaries = (_G.metadata.toolchain or "") .. '/bin/*'
--   for _, full_path in ipairs(vim.fn.glob(pio_binaries, false, true)) do
--     local name = full_path:match('([^/\\\\]+)$'):gsub('%.exe$', '')
--     path_map[name] = full_path
--   end
--
--   -- 2. Update Entries
--   local modified = false
--   for _, entry in ipairs(data) do
--     local cmd = entry.command or ""
--     local first_token = cmd:match("^%S+") -- Get first word before space
--
--     if first_token and not (first_token:sub(1,1) == '/' or first_token:match('^%a:')) then
--       local short_name = first_token:gsub('%.exe$', '')
--       if path_map[short_name] then
--         -- Swap first token with full path safely
--         entry.command = path_map[short_name] .. cmd:sub(#first_token + 1)
--         modified = true
--       end
--     end
--   end
--
--   -- 3. Save with Formatting
--   if modified then
--     local json_str = vim.json.encode(data)
--     -- Use python to format, then write file
--     local formatted = vim.fn.system('python -m json.tool', json_str)
--     if vim.v.shell_error == 0 then
--       vim.fn.writefile(vim.split(formatted, "\n"), filename)
--       vim.notify('compiledb: paths fixed', vim.log.levels.INFO)
--     end
--   end
-- end

-- function M.compile_commandsFix()
--   local filename = vim.uv.cwd() .. '/compile_commands.json'
--   local file = io.open(filename, 'r')
--   if not file then return end
--
--   -- read compile_commands.json file to content
--   local content = file:read('*a')
--   file:close()
--   if not content or content == '' then return end
--
--   -- JSON decoding content to data
--   local ok, data = pcall(vim.json.decode, content)
--   if not ok or type(data) ~= 'table' then
--     vim.notify('PIO Fix: Invalid JSON in ' .. filename, vim.log.levels.ERROR)
--     return
--   end
--
--   -- print('PioFix0')
--   -- PHASE 1: Scan Disk to build a Map of Name -> Absolute Path
--   local path_map = {}
--   local pio_home = _G.metadata.core_dir --os.getenv('PLATFORMIO_CORE_DIR') --or os.getenv('USERPROFILE')
--   if pio_home then
--     -- Recursively find all binaries in PIO packages
--     local pio_packages = _G.metadata.toolchain .. '/bin/*' --M.get_pio_dir('packages') .. '/*/bin/*'
--     local found_binaries = vim.fn.glob(pio_packages, false, true)
--
--     for _, full_path in ipairs(found_binaries) do
--       -- Extract filename (e.g., riscv32-esp-elf-gcc)
--       local name = full_path:match('([^/\\\\]+)$'):gsub('%.exe$', '')
--       path_map[name] = full_path
--       -- print('PioFix1: driver_path=' .. full_path .. ' name=' .. name)
--     end
--   end
--
--   -- PHASE 2: Update JSON using the Map
--   local modified = 0
--   for _, entry in ipairs(data) do
--     if type(entry.command) == 'string' then
--       local cmd_parts = vim.split(entry.command, ' ')
--       local first_token = cmd_parts[1]
--       if first_token then
--         -- Check if it's already a short name (not an absolute path)
--         local is_abs = first_token:sub(1, 1) == '/' or first_token:match('^%a:[/\\]')
--         if not is_abs then
--           local short_name = first_token:gsub('%.exe$', '')
--           -- print('PioFix2: short_name=' .. short_name)
--           -- Direct Query: Does this name exist in our discovered list?
--           if path_map[short_name] then
--             cmd_parts[1] = path_map[short_name]
--             -- print('PioFix3: full_name=' .. cmd_parts[1])
--             entry.command = table.concat(cmd_parts, ' ')
--             modified = modified + 1
--           end
--         end
--       end
--     end
--   end
--
--   -- PHASE 3: Save and Refresh
--   -- Safe JSON encoding
--   if modified > 0 then
--     local out_file = io.open(filename, 'w')
--     if out_file then
--       local encode_ok, json_str = pcall(vim.json.encode, data, { indent = '  ' })
--       if encode_ok and json_str then
--         -- 1. Format the string using python's json.tool
--         -- The second argument to vim.fn.system() is the "stdin" passed to the command
--         local formatted_json = vim.fn.system('python -m json.tool', json_str)
--
--         -- out_file:write(json_str)
--         out_file:write(formatted_json)
--         out_file:close()
--         vim.notify('compiledb: fixed', vim.log.levels.INFO)
--         -- lsp_restart('clangd')
--       end
--     end
--   end
-- end

------------------------------------------------------
-- INFO: ToggleTerminal commands sequencer

M.queue = {}
local pio_buffer = '' -- Persistent stream buffer

------------------------------------------------------
-- INFO: ToggleTerminal commands stdout filter
-- stylua: ignore
function M.stdoutFilter(_, _, data)
  if #M.queue == 0 then return end

  -- 1. attach partial buffer from previous data last line to 1st line
  pio_buffer = pio_buffer .. data[1]
  -- 2. If the chunk has more than one element, we've encountered newlines
  if #data > 1 then
    -- 3. Process any "middle" lines which are guaranteed to be complete
    for i = 2, #data - 1 do pio_buffer = pio_buffer .. data[i] end

    for status in pio_buffer:gmatch('_DONE_:(%a+)') do
      if status then
        if status == 'PASS' then
          -- 4. Store the last element as the new partial buffer for the next call
          pio_buffer = data[#data]
          M.process_queue()
          -- local task = table.remove(M.queue, 1)
          -- if task then vim.schedule(task) end
        -- elseif status == 'LAST' then
        --   _G.metadata.isBusy = false
        --   M.queue = {} -- Clear queue on any other status
        --   pio_buffer = ''
        --   vim.schedule(function() vim.notify('PIO Sequence: Finished', 4) end)
        elseif status == 'FAIL' then
          M.queue = {} -- Clear queue on any other status (failure)
          pio_buffer = ''
          vim.schedule(function() vim.notify('PIO Sequence: Aborted', 4) end)
        end
        break
      end
    end
  end
  if #pio_buffer > 10000 then pio_buffer = pio_buffer:sub(-5000) end
end

-- _G.metadata.isBusy = true
term.on_stdout_handler = M.stdoutFilter
local pio_terminal = term.ToggleTerminal('', 'float')
------------------------------------------------------
-- INFO: ToggleTerminal commands Sequencer
--- stylua: ignore
M.run_sequence = function(tasks)
  -- Reset local state for new run
  M.queue = {}
  pio_buffer = ''
  local full_cmd = ''

  local pass = 'echo _DONE_":"PASS'
  -- local last = 'echo _DONE_":"LAST'
  local fail = 'echo _DONE_":"FAIL'

  for _, row in ipairs(tasks) do
    -- Build the wrapped command string
    local wrapped_cmd = string.format('%s && %s || %s', row.cmd, pass, fail)
    table.insert(M.queue, {
      cmd = wrapped_cmd,
      cb = row.cb,
    })
  end

  -- for _, task in ipairs(tasks) do
  --   table.insert(M.queue, task.cb)
  --   local part = string.format('%s && %s', task.cmd, pass)
  --   if full_cmd == '' then
  --     full_cmd = part
  --   else
  --     full_cmd = full_cmd .. ' && ' .. part
  --   end -- Chain multiple commands
  -- end
  -- full_cmd = full_cmd .. ' && ' .. last .. ' || ' .. failure
  -- local term = require('platformio.utils.term').ToggleTerminal
  -- _G.metadata.isBusy = true
  -- term(full_cmd, 'float')
end

-- 2. Shell Runner: Sends text to the live shell
function M.run_shell_job(cmd, on_exit_callback)
  -- Ensure terminal is open and process is alive
  if not pio_terminal then
    return
  end
  if not pio_terminal:is_open() then
    pio_terminal:open()
  end

  -- Wrap the command:
  -- 1. Run the actual command
  -- 2. Run the callback logic (optional)
  -- 3. Print the sentinel so the Lua listener knows we're done
  -- local full_cmd = string.format('%s && echo %s', cmd, sentinel)

  -- Store callback for the listener if needed
  M.current_cb = on_exit_callback

  -- Send the text + Enter key
  pio_terminal:send(cmd)
end
-- 3. Queue Controller
function M.process_queue()
  local task = table.remove(M.queue, 1)

  if not task then
    M.is_processing = false
    if M.current_cb then
      M.current_cb()
    end -- Final callback
    return
  end

  M.is_processing = true

  if task.cmd then
    M.run_shell_job(task.cmd, task.cb)
  elseif type(task.cb) == 'function' then
    vim.schedule(function()
      task.cb()
      -- Lua tasks need to manually move the queue
      M.process_queue()
    end)
  end
end
------------------------------------------------------
-- Handle after 'pio run -t compiledb' execution
function M.handleDb()
  vim.notify('compiledb: compile_commands.json generated/updated', vim.log.levels.INFO)
  misc.gitignore_lsp_configs('compile_commands.json')
  local pio_manager = require('platformio.pio_setup').pio_manager
  pio_manager.refresh(function()
    local boilerplate_gen = require('platformio.boilerplate').boilerplate_gen
    boilerplate_gen(M.selected_framework, vim.uv.cwd() .. '/src', 'main.cpp')
    boilerplate_gen([[.clangd]], _G.metadata.core_dir)
    M.compile_commandsFix()
    lsp_restart('clangd')
  end)
end

------------------------------------------------------
-- Handle after poioinit execution
--- stylua: ignore
function M.handlePioinit()
  -- local boilerplate_gen = require('platformio.boilerplate').boilerplate_gen
  -- boilerplate_gen([[.clangd_cmd]], vim.g.platformioRootDir)
  -- vim.schedule(function()
  -- local pio_manager = require('platformio.pio_setup').pio_manager
  -- pio_manager.refresh(function()
  -- local boilerplate_gen = require('platformio.boilerplate').boilerplate_gen
  -- boilerplate_gen(M.selected_framework, vim.uv.cwd() .. '/src', 'main.cpp')
  vim.notify('Pioinit: Success', vim.log.levels.INFO)
  -- end)
  -- end)
end
-- Handle after poioinit execution
-- stylua: ignore
function M.handlePiolib()
  vim.notify('Piolib: Success', vim.log.levels.INFO)
end
-- INFO: end commands sequencer
------------------------------------------------------

return M
