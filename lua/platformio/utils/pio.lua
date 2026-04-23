local M = {}

-- to fix require loop, this value is set in plugin/platformio
local misc = vim.misc

-- local sep = package.config:sub(1, 1) -- Dynamic OS separator (\ or /)
M.selected_framework = ''
M.is_processing = false
M.queue = {}

local term = require('platformio.utils.term')
local lsp_restart = require('platformio.lsp.tools').lsp_restart

-- stylua: ignore
function M.compile_commandsFix() --M.dbPathsFix()
  local filename = vim.fs.joinpath(vim.uv.cwd(), 'compile_commands.json')
  local content = vim.fn.readfile(filename)
  if #content == 0 then return end

  local ok, data = pcall(vim.json.decode, table.concat(content, '\n'))
  if not ok or type(data) ~= 'table' then return end

  -- 1. Build Path Map (Scan toolchain)
  local path_map = {}

  local pio_binaries = _G.metadata.query_driver or '/bin/*'
  -- local pio_binaries = (_G.metadata.toolchain_root or "") .. '/bin/*'
  for _, full_path in ipairs(vim.fn.glob(pio_binaries, false, true)) do
    local name = full_path:match('([^/\\\\]+)$'):gsub('%.exe$', '')
    path_map[name] = full_path
  end

  local modified = false
  local prntFlags = true
  for _, entry in ipairs(data) do
    -- Standard normalization
    if entry.directory then entry.directory = misc.normalizePath(entry.directory) end
    if entry.file then entry.file = misc.normalizePath(entry.file) end
    if entry.arguments then entry.arguments = misc.normalizeFlags(entry.arguments) end
    if entry.output then entry.output = misc.normalizePath(entry.output) end

    if entry.command then
      -- Extract compiler and everything after it
      local compiler, args = entry.command:match("^%s*(%S+)(.*)")
      if compiler then
        local is_absolute = compiler:sub(1, 1) == '/' or compiler:match('^%a:')

        if not is_absolute then
          local short_name = compiler:match('([^/\\\\]+)$'):gsub('%.exe$', '')

          if path_map[short_name] then
            -- Use normalizePath on the new path
            local full_compiler_path = misc.normalizePath(path_map[short_name])

            -- Quote the path if it contains spaces
            if full_compiler_path:find(" ") then
              full_compiler_path = '"' .. full_compiler_path .. '"'
            end
            if prntFlags then
              print(string.format('ful_compiler_path = %s', full_compiler_path))
              -- print(string.format('ful_compiler_path = %s flags=%s', full_compiler_path, args))
              prntFlags = false
            end
            -- local argsFormated = misc.normalizeFlags(args)
            -- entry.command = full_compiler_path .. argsFormated
            entry.command = full_compiler_path .. args
            modified = true
          end
        end
      end
    end
  end
  -- 2. Update Entries
  -- local modified = false
  -- for _, entry in ipairs(data) do
  --   if entry.directory then entry.directory = misc.normalizePath(entry.directory) end
  --   if entry.file then entry.file = misc.normalizePath(entry.file) end
  --   if entry.arguments then entry.arguments = misc.normalizeFlags(entry.arguments) end
  --   --
  --   if entry.command then
  --     -- local first_token = cmd:match('^%S+') -- Get first word before space
  --     local compiler, args = entry.command:match("^%s*(%S+)(.*)")
  --
  --     -- Check if it's already a short name (not an absolute path)
  --     if compiler and not (compiler:sub(1, 1) == '/' or compiler:match('^%a:')) then
  --       -- get the file name without .exe
  --       -- local short_name = compiler:gsub('%.exe$', '')
  --       local short_name = compiler:match('([^/\\\\]+)$'):gsub('%.exe$', '')
  --       if path_map[short_name] then -- if there is full path for this file
  --         -- Swap compiler with full path safely
  --         local full_compiler_path = path_map[short_name] --misc.normalizePath(path_map[short_name])
  --         --Quore the path if it contains spaces
  --         if full_compiler_path.find(" ") then
  --           full_compiler_path = '"' .. full_compiler_path .. '"'
  --         end
  --         print(string.format('compiler = %s', compiler))
  --         -- local argsFormated = misc.normalizeFlags(args)
  --         -- entry.command = full_compiler_path .. argsFormated
  --         entry.command = full_compiler_path .. args
  --         modified = true
  --       end
  --     end
  --   end
  -- end
  -- -- 3. Save with Formatting
  if modified then
    local start_time = vim.loop.hrtime()

    local jok, formatted = pcall(vim.misc.jsonFormat, data)
    -- local jok, formatted = pcall(M.pretty_print, data)
    if not jok then
      print('Formatting failed: ' .. formatted)
      return
    end

    local f = io.open(filename, 'w')
    if f then
      f:write(formatted)
      f:close()
      print('Fixed and formatted ' .. filename)
    end

    local end_time = vim.loop.hrtime()
    local duration = (end_time - start_time) / 1e6
    print(string.format('Saved %s in %.2fms', filename, duration))
    vim.notify('compiledb: paths fixed', vim.log.levels.INFO)
    lsp_restart('clangd')
    _G.metadata.isBusy = false
  end
end


-- stylua: ignore
-- function M.compile_commandsFix()
--   local filename = vim.fs.joinpath(vim.uv.cwd(), 'compile_commands.json')
--   if vim.fn.filereadable(filename) == 0 then return end
--
--   -- 1. Read and Decode (Atomic read)
--   local content = table.concat(vim.fn.readfile(filename), "\n")
--   local ok, data = pcall(vim.json.decode, content)
--   if not ok or type(data) ~= 'table' then return end
--
--   -- 2. Build Path Map (Dynamic OS Separator)
--   local sep = package.config:sub(1,1)
--   local path_map = {}
--   local toolchain = (_G.metadata and _G.metadata.toolchain_root or "")
--
--   if toolchain ~= "" then
--     local bin_glob = vim.fs.joinpath(toolchain, "bin", "*")
--     for _, full_path in ipairs(vim.fn.glob(bin_glob, false, true)) do
--       -- Correct regex for both / and \
--       local name = full_path:match("([^" .. sep .. "/]+)$"):gsub("%.exe$", "")
--       path_map[name] = full_path
--     end
--   end
--
--   -- 3. Update Entries
--   local modified = false
--   for _, entry in ipairs(data) do
--     local cmd = entry.command or ""
--     local first_token = cmd:match("^%S+")
--
--     if first_token then
--       -- Check if it's already absolute (starts with / or C:)
--       local is_abs = first_token:sub(1,1) == '/' or first_token:match("^%a:")
--       if not is_abs then
--         local name = first_token:gsub("%.exe$", "")
--         if path_map[name] then
--           entry.command = path_map[name] .. cmd:sub(#first_token + 1)
--           modified = true
--         end
--       end
--     end
--   end
--
--   if modified then
--     -- 1. Encode with 2-space indentation (This creates \n characters in the string)
--     local ok, json_str = pcall(vim.json.encode, data, { indent = "  " })
--
--     if ok and json_str then
--       -- 2. FORCE SPLIT: Turn the one long string into a List of lines
--       -- The { plain = true } ensures we split on the literal \n
--       local lines = vim.split(json_str, "\n", { plain = true })
--
--       -- 3. Use writefile:
--       -- Linux: joins table with \n
--       -- Windows: joins table with \r\n (Fixing your single-line issue!)
--       local status = vim.fn.writefile(lines, filename, 's')
--
--       if status == 0 then
--         vim.cmd("checktime " .. vim.fn.fnameescape(filename))
--         vim.notify("PIO: Fixed paths and line endings", 2)
--       end
--     end
--   end
--   lsp_restart('clangd')
--   _G.metadata.isBusy = false
--   -- M.process_queue()
-- end

  -- lsp_restart('clangd')
  -- _G.metadata.isBusy = false
  -- M.process_queue()







local pio_buffer = '' -- Persistent stream buffer
local callBack = nil
local commandPassed = 0
------------------------------------------------------
-- INFO: ToggleTerminal commands stdout filter
--- stylua: ignore
function M.stdoutcallback(_, _, data)
  if #M.queue == 0 then
    return
  end

  -- 1. attach partial buffer from previous data last line to 1st line
  pio_buffer = pio_buffer .. data[1]
  -- 2. If the chunk has more than one element, we've encountered newlines
  if #data > 1 then
    -- 3. Process any "middle" lines which are guaranteed to be complete
    for i = 2, #data - 1 do
      pio_buffer = pio_buffer .. data[i]
    end

    for status in pio_buffer:gmatch('_CMMNDS_:(%a+)') do
      if callBack and status then
        if status == 'PASS' then
          -- Store the last element as the new partial buffer for the next call
          pio_buffer = data[#data]
        end
        -- vim.schedule(function() callBack('PASS') end)
        --   callBack('PASS')
        -- elseif status == 'DONE' then
        -- callBack('PASS')
        -- vim.schedule(function() callBack('DONE') end)
        -- elseif status == 'FAIL' then
        -- callBack('PASS')
        callBack(status)
        -- vim.schedule(function() callBack('DONE') end)
        -- end
        break
      end
    end
  end
  if #pio_buffer > 10000 then
    pio_buffer = pio_buffer:sub(-5000)
  end
end

-- stylua: ignore
M.run_sequence = function(tasks)
  M.queue = {}
  callBack = tasks.cb -- 1. Save the callback in a local variable
  local commands = tasks.cmnds

  local done = ' && echo _CMMNDS_":"DONE'
  local pass = ' && echo _CMMNDS_":"PASS'
  local fail = ' || echo _CMMNDS_":"FAIL'
  --
  for i, cmd in ipairs(commands) do
    local full_cmd = ''
    if i == #commands then full_cmd = cmd .. done .. fail
    else full_cmd = cmd .. pass .. fail end
    table.insert(M.queue, full_cmd)
  end
  vim.schedule(function()
    if callBack then callBack('INIT') end
  end)
end

-- Handle after pioinit execution
function M.handlePioinit(result)
  if result == 'INIT' then
    commandPassed = 0
    _G.metadata.isBusy = true
    pio_buffer = ''
    local full_cmd = table.remove(M.queue, 1)
    term.stdout_callback = M.stdoutcallback
    term.ToggleTerminal(full_cmd, 'float')
  elseif result == 'PASS' then
    commandPassed = commandPassed + 1
    if commandPassed == 1 then
      vim.schedule(function()
        vim.notify('Pioinit: commandPassed', vim.log.levels.INFO)
        local pio_manager = require('platformio.pio_setup').pio_manager
        pio_manager.refresh(function()
          local boilerplate_gen = require('platformio.boilerplate').boilerplate_gen
          boilerplate_gen(M.selected_framework, vim.uv.cwd() .. '/src', 'main.cpp')
          boilerplate_gen([[.clangd]], _G.metadata.core_dir)
        end)
      end)
      -- elseif commandPassed == 2 then
    end
    local full_cmd = table.remove(M.queue, 1)
    term.ToggleTerminal(full_cmd, 'float')
  elseif result == 'DONE' then -- compile_commands.json created
    pio_buffer = ''
    M.queue = {} -- Clear queue on any other status (failure)
    term.stdout_callback = nil
    vim.schedule(function()
      vim.notify('compiledb: Pass', vim.log.levels.INFO)
      vim.misc.gitignore_lsp_configs('compile_commands.json')
      _G.metadata.dbTrigger = true
    end)
  elseif result == 'FAIL' then
    pio_buffer = ''
    M.queue = {} -- Clear queue on any other status (failure)
    term.stdout_callback = nil
  end
end

------------------------------------------------------
-- INFO: ToggleTerminal commands sequencer

-- local pio_buffer = '' -- Persistent stream buffer
-- ------------------------------------------------------
-- -- INFO: ToggleTerminal commands stdout filter
-- -- stylua: ignore
-- function M.stdoutcallback(_, _, data)
--   if #M.queue == 0 then return end
--
--   -- 1. attach partial buffer from previous data last line to 1st line
--   pio_buffer = pio_buffer .. data[1]
--   -- 2. If the chunk has more than one element, we've encountered newlines
--   if #data > 1 then
--     -- 3. Process any "middle" lines which are guaranteed to be complete
--     for i = 2, #data - 1 do pio_buffer = pio_buffer .. data[i] end
--
--     for status in pio_buffer:gmatch('_CMMNDS_:(%a+)') do
--       if status then
--         -- if status == 'PASS' then
--         --   pio_buffer = data[#data]
--         --   vim.schedule(function() M.process_queue() end)
--         -- elseif status == 'FAIL' then
--         -- end
--         if status == 'PASS' then
--           -- 4. Store the last element as the new partial buffer for the next call
--           pio_buffer = data[#data]
--           local task = table.remove(M.queue, 1)
--           if task then vim.schedule(task) end
--         elseif status == 'DONE' then
--           pio_buffer = ''
--           M.queue = {} -- Clear queue on any other status
--           local task = table.remove(M.queue, 1)
--           if task then vim.schedule(task) end
--         elseif status == 'FAIL' then
--           pio_buffer = ''
--           M.queue = {} -- Clear queue on any other status (failure)
--           local task = table.remove(M.queue, 1)
--           if task then vim.schedule(task) end
--         end
--         break
--       end
--     end
--   end
--   if #pio_buffer > 10000 then pio_buffer = pio_buffer:sub(-5000) end
-- end
--
-- ------------------------------------------------------
-- -- INFO: ToggleTerminal commands Sequencer
-- -- Semicolon (;): Runs the next command regardless of whether the first one succeeded.
-- -- Success Operator (&&): Runs the second command only if the first succeeds.
-- -- Fail Operator (||): Runs if any of the previous commands fail
-- --- stylua: ignore
-- M.run_sequence = function(tasks)
--   -- Reset local state for new run
--   M.queue = {}
--   pio_buffer = ''
--   local full_cmd = ''
--   local done = ' && echo _CMMNDS_":"DONE'
--   local pass = ' && echo _CMMNDS_":"PASS'
--   local fail = ' || echo _CMMNDS_":"FAIL'
--   --
--   for _, task in ipairs(tasks) do
--     table.insert(M.queue, task.cb)
--     local part = string.format('%s %s', task.cmd, pass)
--     if full_cmd == '' then
--       full_cmd = part
--     else
--       full_cmd = full_cmd .. ' && ' .. part
--     end
--   end
--   full_cmd = full_cmd .. done .. fail
--
--   table.insert(M.queue, function()
--     vim.notify('Pioinit: Done', vim.log.levels.INFO)
--     term.stdout_callback = nil
--   end)
--
--   table.insert(M.queue, function()
--     vim.notify('Pioinit: Failed', vim.log.levels.INFO)
--   end)
--
--   -- full_cmd = full_cmd .. ' || ' .. fail
--   _G.metadata.isBusy = true
--   -- local ToggleTerminal = require('platformio.utils.term').ToggleTerminal
--   term.stdout_callback = M.stdoutcallback
--   term.ToggleTerminal(full_cmd, 'float')
-- end
--
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
