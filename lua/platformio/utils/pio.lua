---@class platformio.utils.pio
local M = {}

-- to fix require loop, this value is set in plugin/platformio
local misc = vim.misc

-- local sep = package.config:sub(1, 1) -- Dynamic OS separator (\ or /)
M.selected_framework = ''
M.is_processing = false
M.queue = {}

local term = require('platformio.utils.term')
local lsp_restart = require('platformio.lspConfig.tools').lsp_restart

-- INFO:
-- =============================================================================
-- UNIVERSAL TOOLCHAIN DETECTION
-- =============================================================================
-- stylua: ignore
function M.compile_commandsFix() --M.dbPathsFix()
  local filename = vim.fs.joinpath(vim.uv.cwd(), 'compile_commands.json')
  local content = vim.fn.readfile(filename)
  if #content == 0 then return end

  local start_time = vim.loop.hrtime()
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

  -- 2. Update Entries
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
              -- print(string.format('ful_compiler_path = %s flags=%s', full_compiler_path, args))
              prntFlags = false
            end
            entry.command = full_compiler_path .. args
            modified = true
          end
        end
      end
    end
  end
  -- -- 3. Save with Formatting
  if modified then
    local jok, formatted = pcall(vim.misc.jsonFormat, data)
    -- local jok, formatted = pcall(M.pretty_print, data)
    if not jok then
      print('Formatting failed: ' .. formatted)
      return
    end

    local wk, err = vim.misc.writeFile(filename, formatted, { overwrite = true, mkdir = true })
    if not wk then print(err) end

    local end_time = vim.loop.hrtime()
    local duration = (end_time - start_time) / 1e6
    vim.notify(string.format('compiledb: paths fixed in %.2fms', duration), vim.log.levels.INFO)
    lsp_restart('clangd')
  end
  _G.metadata.isBusy = false
end

local callBack = nil
local pio_buffer = '' -- Persistent stream buffer
------------------------------------------------------
-- INFO: ToggleTerminal commands stdout filter
-- stylua: ignore
function M.stdoutcallback(_, _, data)
  if not data then return end

  -- 1. Combine the last partial line with the new first line
  local lines_to_process = pio_buffer .. data[1]

  -- 2. If there are newlines, we have complete lines to check
  if #data > 1 then
    -- Join all complete parts (everything except the very last partial line)
    for i = 2, #data - 1 do lines_to_process = lines_to_process .. data[i] end

    -- 3. Search for the status in the complete chunk
    local status = lines_to_process:match('_CMMNDS_:(%a+)')
    if status and callBack then vim.schedule(function() callBack(status) end) end
    -- save the trailing part for the next chunk
    pio_buffer = data[#data]
  else
    -- Only one element in data means no newline yet; just update the partial buffer
    pio_buffer = lines_to_process
  end

  -- 4. Safety Trim (Prevents memory leaks if no newline ever comes)
  if #pio_buffer > 5000 then pio_buffer = pio_buffer:sub(-2500) end
end

local commandPassed = 0
------------------------------------------------------
-- INFO: commands sequencer
-- stylua: ignore
M.run_sequence = function(tasks)
  M.queue = {}
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


  callBack = tasks.cb -- 1. Save the callback in a local variable
  commandPassed = 0
  _G.metadata.isBusy = true

  term.stdout_callback = M.stdoutcallback
  vim.schedule(function() if callBack then callBack('INIT') end end)
end

------------------------------------------------------
-- Handle after pioinit execution
function M.handlePioinitDb(result)
  if result == 'INIT' then
    local boilerplate = require('platformio.boilerplate')
    local boilerplate_gen = boilerplate.boilerplate_gen

    boilerplate.core_dir = _G.metadata.core_dir
    boilerplate_gen([[platformio.ini]], vim.g.platformioRootDir)

    boilerplate_gen([[.clang-format]], vim.g.platformioRootDir)

    boilerplate_gen([[.clangd]], vim.g.platformioRootDir)
    -- boilerplate_gen([[.clangd]], _G.metadata.core_dir)
    -- boilerplate_gen([[.clangd]], vim.fs.joinpath(vim.env.XDG_CONFIG_HOME, 'clangd'), 'config.yaml')

    term.ToggleTerminal(table.remove(M.queue, 1), 'float')
  elseif result == 'PASS' then
    commandPassed = commandPassed + 1
    if commandPassed == 1 then
      vim.schedule(function()
        vim.notify('Pioinit: Done ..', vim.log.levels.INFO)
        local boilerplate_gen = require('platformio.boilerplate').boilerplate_gen
        boilerplate_gen([[.clangd]], _G.metadata.core_dir)
      end)
      -- elseif commandPassed == 2 then -- if you sned more than 2 commands you need this
    end
    term.ToggleTerminal(table.remove(M.queue, 1), 'float')
  elseif result == 'DONE' then -- result of the last command
    vim.schedule(function()
      vim.notify('compiledb: Done ..', vim.log.levels.INFO)
      M.queue = {}
      term.stdout_callback = nil
      local pio_refresh = require('platformio.pio_setup').pio_refresh
      pio_refresh('PIO init+db: ', function()
        vim.misc.gitignore_lsp_configs('compile_commands.json')
        lsp_restart('clangd')
        -- _G.metadata.dbTrigger = true
        -- local ok, _ = pcall(M.compile_commandsFix)
        -- if not ok then
        --   print('Env: dbTrigger, fail to call dbFix')
        -- end
      end)
    end)
  elseif result == 'FAIL' then
    M.queue = {}
    term.stdout_callback = nil
    _G.metadata.isBusy = false
  end
end

------------------------------------------------------
-- Handle after pioinit execution
function M.handlePioinit(result)
  if result == 'INIT' then
    local boilerplate = require('platformio.boilerplate')
    local boilerplate_gen = boilerplate.boilerplate_gen

    boilerplate.core_dir = _G.metadata.core_dir
    boilerplate_gen([[platformio.ini]], vim.g.platformioRootDir)

    boilerplate_gen([[.clang-format]], vim.g.platformioRootDir)

    boilerplate_gen([[.clangd]], vim.g.platformioRootDir)
    -- boilerplate_gen([[.clangd]], _G.metadata.core_dir)
    -- boilerplate_gen([[.clangd]], vim.fs.joinpath(vim.env.XDG_CONFIG_HOME, 'clangd'), 'config.yaml')

    term.ToggleTerminal(table.remove(M.queue, 1), 'float')
  elseif result == 'DONE' then -- result of the last command
    vim.schedule(function()
      vim.notify('Pioinit: Done ..', vim.log.levels.INFO)
      local pio_refresh = require('platformio.pio_setup').pio_refresh
      pio_refresh('PIO init: ', function()
        vim.misc.gitignore_lsp_configs('compile_commands.json')
        local boilerplate_gen = require('platformio.boilerplate').boilerplate_gen
        boilerplate_gen([[.clangd]], _G.metadata.core_dir)
      end)
    end)
  elseif result == 'FAIL' then
  end
  M.queue = {}
  term.stdout_callback = nil
  _G.metadata.isBusy = false
end

------------------------------------------------------
-- Handle after piolib execution
function M.handlePiolib(result)
  if result == 'INIT' then
    term.ToggleTerminal(table.remove(M.queue, 1), 'float')
  elseif result == 'DONE' then -- result of the only and the last command
    vim.notify('Piolib: Success', vim.log.levels.INFO)
  elseif result == 'FAIL' then
  end
  M.queue = {}
  term.stdout_callback = nil
  _G.metadata.isBusy = false
end

function M.handlePiodb(target, result)
  if result == 'INIT' then
    term.ToggleTerminal(table.remove(M.queue, 1), 'float')
  elseif result == 'DONE' then -- result of the only and the last command
    target.isBusy = false
    vim.notify('Piodb: Success', vim.log.levels.INFO)
  elseif result == 'FAIL' then
  end
  M.queue = {}
  term.stdout_callback = nil
  _G.metadata.isBusy = false
end

return M
