local M = {}

local sep = package.config:sub(1, 1) -- Dynamic OS separator (\ or /)
M.selected_framework = ''
M.is_processing = false
M.queue = {}
local pio_buffer = '' -- Persistent stream buffer

-- to fix require loop, this value is set in plugin/platformio

local term = require('platformio.utils.term')
local misc = require('platformio.utils.misc')
local lsp_restart = require('platformio.lsp.tools').lsp_restart

------------------------------------------------------
-- stylua: ignore
-- 1. Optimized Cross-Platform Path Fixer
function M.compile_commandsFix()
  local filename = vim.fs.joinpath(vim.uv.cwd(), 'compile_commands.json')
  if vim.fn.filereadable(filename) == 0 then M.process_queue() return end

  local ok, data = pcall(vim.json.decode, table.concat(vim.fn.readfile(filename), "\n"))
  if not ok or type(data) ~= 'table' then M.process_queue() return end

  local path_map = {}
  local toolchain = _G.metadata and _G.metadata.toolchain_root or ""
  if toolchain ~= "" then
    local bin_glob = vim.fs.joinpath(toolchain, "bin", "*")
    for _, full_path in ipairs(vim.fn.glob(bin_glob, false, true)) do
      local name = full_path:match('([^' .. sep .. ']+)$'):gsub('%.exe$', '')
      path_map[name] = full_path
    end
  end

  local modified = false
  for _, entry in ipairs(data) do
    local cmd = entry.command or ""
    local first_token = cmd:match("^%S+")
    if first_token and not (first_token:sub(1,1) == '/' or first_token:match('^%a:')) then
      local name = first_token:gsub('%.exe$', '')
      if path_map[name] then
        entry.command = path_map[name] .. cmd:sub(#first_token + 1)
        modified = true
      end
    end
  end

  if modified then
    local ok_enc, json_str = pcall(vim.json.encode, data, { indent = "  " })
    if ok_enc then
      vim.fn.writefile(vim.split(json_str, "\n"), filename, 's')
    end
  end
  -- function M.compile_commandsFix()
  -- local filename = vim.uv.cwd() .. '/compile_commands.json'
  -- if vim.fn.filereadable(filename) == 0 then return end
  --
  -- -- Atomic read using built-in Vim function
  -- local content = table.concat(vim.fn.readfile(filename), "\n")
  -- local ok, data = pcall(vim.json.decode, content)
  -- if not ok or type(data) ~= 'table' then return end
  --
  -- -- 1. Build Path Map (Scan toolchain)
  -- local path_map = {}
  -- local toolchain_bin = (_G.metadata and _G.metadata.toolchain_root or "") .. '/bin/*'
  -- for _, full_path in ipairs(vim.fn.glob(toolchain_bin, false, true)) do
  --   local name = full_path:match('([^/\\\\]+)$'):gsub('%.exe$', '')
  --   path_map[name] = full_path
  -- end
  --
  -- -- 2. Update Entries efficiently with string matching
  -- local modified = false
  -- for _, entry in ipairs(data) do
  --   local cmd = entry.command or ""
  --   local first_token = cmd:match("^%S+") -- Grab only the compiler driver
  --
  --   -- Fix if it's a relative path (doesn't start with / or Drive letter)
  --   if first_token and not (first_token:sub(1,1) == '/' or first_token:match('^%a:')) then
  --     local short_name = first_token:gsub('%.exe$', '')
  --     if path_map[short_name] then
  --       -- Replace only the first token to preserve arguments
  --       entry.command = path_map[short_name] .. cmd:sub(#first_token + 1)
  --       modified = true
  --     end
  --   end
  -- end
  --
  -- -- PHASE 3: Save and Refresh
  -- if modified then
  --   local jok, json_str = pcall(vim.json.encode, data, { indent = "  " })
  --   if not jok or not json_str then
  --     vim.notify("PIO: JSON Encoding failed", 4)
  --     return M.process_queue() -- Don't get stuck
  --   end
  --
  --   local lines = vim.split(json_str, '\n')
  --
  --   -- 1. Check if the directory is actually writable (Safety Check)
  --   local dir = vim.fn.fnamemodify(filename, ":h")
  --   if vim.fn.isdirectory(dir) == 0 then
  --     vim.notify("PIO: Directory does not exist: " .. dir, 4)
  --     return M.process_queue()
  --   end
  --
  --   -- 2. Use pcall to prevent the function from "exiting" on error
  --   local write_ok, status = pcall(vim.fn.writefile, lines, filename, 's')
  --
  --   if write_ok and status == 0 then
  --     vim.notify('compiledb: fixed and saved', 2)
  --   else
  --     local err_msg = not write_ok and status or "Write error (check permissions)"
  --     vim.notify('PIO Save Failed: ' .. err_msg, 4)
  --   end
  -- end
  -- -- 3. Save with Python formatting
  -- -- if modified then
  -- --   local json_str = vim.json.encode(data)
  -- --   local formatted = vim.fn.system('python -m json.tool', json_str)
  -- --
  -- --   if vim.v.shell_error == 0 then
  -- --     -- Atomic write back to disk
  -- --     vim.fn.writefile(vim.split(formatted, "\n"), filename)
  -- --     vim.notify('compiledb: paths fixed', vim.log.levels.INFO)
  -- --   else
  -- --     vim.notify('compiledb: paths fix failed', vim.log.levels.ERROR)
  -- --   end
  -- -- end
  lsp_restart('clangd')
  _G.metadata.isBusy = false
  -- M.process_queue()
end


------------------------------------------------------
-- INFO: ToggleTerminal commands sequencer

------------------------------------------------------
-- INFO: ToggleTerminal commands stdout filter
-- stylua: ignore
function M.stdoutcallback(_, _, data)
  if #M.queue == 0 then return end

  -- 1. attach partial buffer from previous data last line to 1st line
  pio_buffer = pio_buffer .. data[1]
  -- 2. If the chunk has more than one element, we've encountered newlines
  if #data > 1 then
    -- 3. Process any "middle" lines which are guaranteed to be complete
    for i = 2, #data - 1 do pio_buffer = pio_buffer .. data[i] end

    for status in pio_buffer:gmatch('_CMMNDS_:(%a+)') do
      if status then
        -- if status == 'PASS' then
        --   pio_buffer = data[#data]
        --   vim.schedule(function() M.process_queue() end)
        -- elseif status == 'FAIL' then
        -- end
        if status == 'PASS' then
          -- 4. Store the last element as the new partial buffer for the next call
          pio_buffer = data[#data]
          local task = table.remove(M.queue, 1)
          if task then vim.schedule(task) end
        elseif status == 'DONE' then
          pio_buffer = ''
          M.queue = {} -- Clear queue on any other status
          local task = table.remove(M.queue, 1)
          if task then vim.schedule(task) end
        elseif status == 'FAIL' then
          pio_buffer = ''
          M.queue = {} -- Clear queue on any other status (failure)
          local task = table.remove(M.queue, 1)
          if task then vim.schedule(task) end
        end
        break
      end
    end
  end
  if #pio_buffer > 10000 then pio_buffer = pio_buffer:sub(-5000) end
end

------------------------------------------------------
-- INFO: ToggleTerminal commands Sequencer
--- stylua: ignore
M.run_sequence = function(tasks)
  -- Reset local state for new run
  M.queue = {}
  pio_buffer = ''
  local full_cmd = ''
  local done = ' && echo _CMMNDS_":"DONE'
  local pass = ' && echo _CMMNDS_":"PASS'
  local fail = ' || echo _CMMNDS_":"FAIL'
  --
  for _, task in ipairs(tasks) do
    table.insert(M.queue, task.cb)
    local part = string.format('%s %s', task.cmd, pass)
    if full_cmd == '' then
      full_cmd = part
    else
      full_cmd = full_cmd .. ' && ' .. part
    end
  end
  full_cmd = full_cmd .. done .. fail

  table.insert(M.queue, function()
    vim.notify('Pioinit: Done', vim.log.levels.INFO)
    term.stdout_callback = nil
  end)

  table.insert(M.queue, function()
    vim.notify('Pioinit: Failed', vim.log.levels.INFO)
  end)

  -- full_cmd = full_cmd .. ' || ' .. fail
  _G.metadata.isBusy = true
  -- local ToggleTerminal = require('platformio.utils.term').ToggleTerminal
  term.stdout_callback = M.stdoutcallback
  term.ToggleTerminal(full_cmd, 'float')
end

-- {
--   cmd = 'echo _CMMNDS_":"DONE',
--   cb = function () vim.notify('Pioinit: Done', vim.log.levels.INFO) end
-- },
------------------------------------------------------
-- Handle after 'pio run -t compiledb' execution
function M.handleDb()
  vim.notify('compiledb: Pass', vim.log.levels.INFO)
  misc.gitignore_lsp_configs('compile_commands.json')
  -- M.compile_commandsFix()
  _G.metadata.dbTrigger = true
end

------------------------------------------------------
-- Handle after pioinit execution
function M.handlePioinitPass()
  vim.notify('Pioinit: Pass', vim.log.levels.INFO)
  local pio_manager = require('platformio.pio_setup').pio_manager
  pio_manager.refresh(function()
    local boilerplate_gen = require('platformio.boilerplate').boilerplate_gen
    boilerplate_gen(M.selected_framework, vim.uv.cwd() .. '/src', 'main.cpp')
    boilerplate_gen([[.clangd]], _G.metadata.core_dir)
  end)
end
------------------------------------------------------
-- Handle after piolib execution
function M.handlePiolib()
  vim.notify('Piolib: Success', vim.log.levels.INFO)
end

return M
