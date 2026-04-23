local term = require('platformio.utils.term')
local pio_buffer = '' -- Persistent stream buffer
local callBack = nil
local commandPassed = 0
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
      if callBack and status then
        if status == 'PASS' then
          -- Store the last element as the new partial buffer for the next call
          pio_buffer = data[#data]
          vim.schedule(function() callBack('PASS') end)
        elseif status == 'DONE' then
          vim.schedule(function() callBack('DONE') end)
        elseif status == 'FAIL' then
          vim.schedule(function() callBack('DONE') end)
        end
        break
      end
    end
  end
  if #pio_buffer > 10000 then pio_buffer = pio_buffer:sub(-5000) end
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
  elseif result == 'DONE' then
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

-- -- Detect OS and Home directory dynamically
-- local is_windows = vim.loop.os_uname().version:find('Windows')
-- local home = os.getenv('HOME') or os.getenv('USERPROFILE')
-- local username = os.getenv('USERNAME') or os.getenv('USER')
--
-- -- Build a list of common compiler paths
-- local drivers = {
--   'C:/Program Files/LLVM/bin/*', -- Windows Clang
--   'C:/msys64/*/bin/*', -- Windows MinGW (MSYS2)
--   home .. '/.platformio/packages/*/bin/*', -- PlatformIO (Both OS)
--   '/usr/bin/*', -- Linux standard
--   '/usr/local/bin/*', -- Linux local
-- }
--
-- require('lspconfig').clangd.setup({
--   cmd = {
--     'clangd',
--     '--background-index',
--     '--clang-tidy',
--     '--offset-encoding=utf-16',
--     -- Combine all paths into one comma-separated string
--     '--query-driver=' .. table.concat(drivers, ','),
--   },
--   -- Other standard config options...
-- })
