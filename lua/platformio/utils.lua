local config = require('platformio').config
local boilerplate_gen = require('platformio.boilerplate').boilerplate_gen
local piolsp = require('platformio.piolsp') --.piolsp
local is_windows = jit.os == 'Windows'
-- local pioinit = require('platformio.pioinit')

local M = {}

M.selected_framework = ''
M.devNul = is_windows and ' 2>./nul' or ' 2>/dev/null'

-- M.extra = 'printf \'\\\\n\\\\033[0;33mPlease Press ENTER to continue \\\\033[0m\'; read'
-- M.extra = ' && echo . && echo . && echo Please Press ENTER to continue'

------------------------------------------------------
-- INFO: Dispatcher

M.queue = {}
local pio_buffer = '' -- Persistent stream buffer

-- 1. The Dispatcher (The Brain)
function M.dispatcher(t, _, data)
  if #M.queue == 0 then
    return
  end

  -- Reassemble fragmented chunks into the persistent stream
  pio_buffer = pio_buffer .. table.concat(data, '')
  local clean_stream = pio_buffer:gsub('[%s%c]', '')

  -- We check for the brackets.
  -- The terminal command sent was: echo ___DONE___:SUCCESS
  -- The terminal output will be: ___DONE___:SUCCESS
  -- Because the sent string doesn't have the brackets, Lua ignores the echo-back!
  -- Check for Success Signal
  if clean_stream:find('%[___DONE___:SUCCESS%]') then
    pio_buffer = ''
    local task = table.remove(M.queue, 1)
    if task then
      vim.schedule(task)
    end
    -- Check for Failure Signal
  elseif clean_stream:find('%[___DONE___:FAILED%]') then
    pio_buffer = ''
    M.queue = {}
    vim.notify('Aborted', 4)
  end
end

-- M.queue = {}
-- -- Outside the function to persist across multiple stdout calls
--
-- -- Unified Dispatcher
-- -- stylua: ignore
-- function M.dispatcher(_, _, data)
--   if #M.queue == 0 then return end
--
--   for _, line in ipairs(data) do
--
--     -- 1. Strip ALL whitespace and non-printable control characters (like \r)
--     -- %s is whitespace, %c is control characters
--     local clean_line = line:gsub("[%s%c]", "")
--
--     -- 2. Look for the pattern in the fully sanitized string
--     -- Regex match: captures 'SUCCESS' or 'FAILED'
--     local status = clean_line:match('^___DONE___:(%a+)')
--     if status then
--       if status == 'SUCCESS' then
--         local task = table.remove(M.queue, 1)
--         if task then vim.schedule(task) end
--       else
--         M.queue = {} -- Clear queue on any other status (failure)
--         vim.schedule(function() vim.notify('PIO Sequence: Aborted', 4) end)
--       end
--       break
--     end
--   end
-- end

-- Improved Runner: Accepts a table of { cmd = "...", cb = function }
--- stylua: ignore
M.run_sequence = function(tasks)
  -- Reset local state for new run
  M.queue = {}
  pio_buffer = ''
  local full_cmd = ''
  local success = 'echo [___DONE___:SUCCESS]'
  local failure = 'echo [___DONE___:FAILED]'

  for _, task in ipairs(tasks) do
    table.insert(M.queue, task.cb)

    -- Windows CMD/PowerShell specific syntax:
    -- No parentheses ensures compatibility with basic 'cmd.exe'
    -- Chain: command && success || failure
    -- local part = string.format('(%s && %s || %s)', task.cmd, success, failure)
    local part = string.format('%s && %s', task.cmd, success)

    if full_cmd == '' then
      full_cmd = part
    else
      full_cmd = full_cmd .. ' && ' .. part
    end -- Chain multiple commands
  end
  full_cmd = full_cmd .. ' || ' .. failure
  M.ToggleTerminal(full_cmd, 'float')
end

-- Handle after 'pio run -t compiledb' execution
function M.handleDb()
  vim.notify('compiledb: compile_commands.json generated/updated', vim.log.levels.INFO)
  piolsp.gitignore_lsp_configs('compile_commands.json')
  piolsp.fix_pio_compile_commands()
  piolsp.lsp_restart('clangd')
end
-- Handle after poioinit execution
function M.handlePioinit()
  vim.notify('Pioinit: Success', vim.log.levels.INFO)
  boilerplate_gen(M.selected_framework, vim.fn.getcwd() .. '/src', 'main.cpp')
end
-- INFO: endDispatcher
------------------------------------------------------

------------------------------------------------------
function M.strsplit(inputstr, del)
  local t = {}
  if type(inputstr) == 'string' and inputstr and inputstr ~= '' then
    for str in string.gmatch(inputstr, '([^' .. del .. ']+)') do
      table.insert(t, str)
    end
  end
  return t
end

function M.check_prefix(str, prefix)
  return str:sub(1, #prefix) == prefix
end

local function pathmul(n)
  return '..' .. string.rep('/..', n)
end

------------------------------------------------------

-- INFO: get current OS enter
function M.enter()
  local shell = vim.o.shell
  if is_windows then
    return vim.fn.executable('pwsh') and '\r' or '\r\n'
  elseif shell:find('nu') then
    return '\r'
  else
    return '\n'
  end
end

-- INFO: get previous window
local function getPreviousWindow(orig_window)
  local prev = {
    orig_window = orig_window,
    term = nil, --active terminal
    cli = nil, --cli terminal
    mon = nil, --mon terminal
    float = false, --is active terminal direction float
  }
  local terms = require('toggleterm.terminal').get_all(true)
  if #terms ~= 0 then
    for i = 1, #terms do
      if terms[i].display_name and terms[i].display_name ~= '' and terms[i].display_name:find('pio', 1) then
        local name_splt = M.strsplit(terms[i].display_name, ':')
        if name_splt[1] == 'piocli' then
          prev.cli = terms[i]
          if terms[i].window == orig_window then
            ---@diagnostic disable-next-line: cast-local-type
            prev.orig_window = tonumber(name_splt[2]) -- set orig_window to the previous terminal onrig_window
            prev.term = terms[i]
          end
          if terms[i].direction == 'float' then
            prev.float = true
          end
        elseif name_splt[1] == 'piomon' then
          prev.mon = terms[i]
          if terms[i].window == orig_window then
            ---@diagnostic disable-next-line: cast-local-type
            prev.orig_window = tonumber(name_splt[2]) -- set orig_window to the previous terminal onrig_window
            prev.term = terms[i]
          end
          if terms[i].direction == 'float' then
            prev.float = true
          end
        end
      end
    end
  end
  return prev
end

------------------------------------------------------
-- INFO: Send command
local function send(term, cmd)
  vim.fn.chansend(term.job_id, cmd .. M.enter())
  if vim.api.nvim_buf_is_loaded(term.bufnr) and vim.api.nvim_buf_is_valid(term.bufnr) then
    if term.window and vim.api.nvim_win_is_valid(term.window) then --vim.ui.term_has_open_win(term) then
      vim.api.nvim_set_current_win(term.window) -- terminal focus
      vim.api.nvim_buf_call(term.bufnr, function()
        local mode = vim.api.nvim_get_mode().mode
        if mode == 'n' or mode == 'nt' then
          vim.cmd('normal! G') -- normal command to Goto bottom of buffer (scroll)
        end
      end)
    end
  end
end

------------------------------------------------------
-- INFO: PioTermClose
local function PioTermClose(t)
  local orig_window = tonumber(M.strsplit(t.display_name, ':')[2])
  -- close terminal window
  vim.api.nvim_win_close(t.window, true)

  -- go back to previous window
  if orig_window and vim.api.nvim_win_is_valid(orig_window) then
    vim.api.nvim_set_current_win(orig_window)
  else
    vim.api.nvim_set_current_win(0)
  end
end

------------------------------------------------------
-- INFO: ToggleTerminal
function M.ToggleTerminal(command, direction)
  local status_ok, _ = pcall(require, 'toggleterm')
  if not status_ok then
    vim.api.nvim_echo({ { 'toggleterm not found!', 'ErrorMsg' } }, true, {})
    return
  end

  local title = ''
  local pioOpts = {}

  -- INFO: set orig_window to current window, or if available get current toggleterm previous window
  local prev = getPreviousWindow(vim.api.nvim_get_current_win())
  local orig_window = prev.orig_window

  if string.find(command, ' monitor') then
    if prev.mon then -- INFO: if previous monitor terminal already opened ==> reopen
      prev.mon.display_name = 'piomon:' .. orig_window
      local win_type = vim.fn.win_gettype(prev.mon.window)
      local win_open = win_type == '' or win_type == 'popup'
      if prev.mon.window and (win_open and vim.api.nvim_win_get_buf(prev.mon.window) == prev.mon.bufnr) then
        vim.api.nvim_set_current_win(prev.mon.window)
      else
        prev.mon:open()
      end
      return
    end
    title = 'Pio Monitor: [In normal mode press: q or :q to hide; :q! to quit; :PioTermList to list terminals]'
    pioOpts.display_name = 'piomon:' .. orig_window
  else -- INFO: if previous cli terminal already opened ==> reopen
    if prev.cli then
      prev.cli.display_name = 'piocli:' .. orig_window
      local win_type = vim.fn.win_gettype(prev.cli.window)
      local win_open = win_type == '' or win_type == 'popup'
      if prev.cli.window and (win_open and vim.api.nvim_win_get_buf(prev.cli.window) == prev.cli.bufnr) then
        vim.api.nvim_set_current_win(prev.cli.window)
      else
        prev.cli:open()
      end
      vim.defer_fn(function()
        if command and command ~= '' then
          send(prev.cli, command)
        end
      end, 50) -- 50ms delay, adjust as needed
      return
    end
    title = 'Pio CLI> [In normal mode press: q or :q to hide; :q! to quit; :PioTermList to list terminals]'
    pioOpts.display_name = 'piocli:' .. orig_window
  end
  pioOpts.direction = direction
  ------------------------------------------------------

  -- INFO: termConfig table start
  local termConfig = {
    hidden = true, -- Start hidden, we'll open it explicitly
    hide_numbers = true,
    float_opts = {
      winblend = 0,
      width = function()
        return math.ceil(vim.o.columns * 0.85)
      end,
      height = function()
        return math.ceil(vim.o.lines * 0.85)
      end,
      highlights = {
        border = 'FloatBorder',
        background = 'NormalFloat',
      },
    },
    close_on_exit = false, --closeOnexit,

    -- INFO: on_open()
    on_open = function(t)
      -- Get properties of the 'Normal' highlight group (background of main editor)
      -- local hl = vim.api.nvim_get_hl(0, { name = 'PmenuSel' })
      -- local hl = { bg = '#e4cf0e', fg = '#0012d9' }
      local hl = { bg = '#80a3d4', fg = '#000000' }

      if hl then
        vim.api.nvim_set_hl(0, 'MyWinBar', { bg = hl.bg, fg = hl.fg })

        local winBartitle = '%#MyWinBar#' .. title .. '%*'
        vim.api.nvim_set_option_value('winbar', winBartitle, { scope = 'local', win = t.window })

        -- Following necessary to solve that some time winbar not showing
        vim.schedule(function()
          vim.api.nvim_set_option_value('winbar', winBartitle, { scope = 'local', win = t.window })
        end)
      end
      vim.keymap.set('t', '<Esc>', [[<C-\><C-n>k]], { buffer = t.bufnr })
      vim.keymap.set('n', '<Esc>', [[<C-\><C-n>a]], { buffer = t.bufnr })

      vim.keymap.set('n', 'q', function()
        PioTermClose(t)
      end, { desc = 'PioTermClose', buffer = t.bufnr })

      if config.debug then
        local name_splt = M.strsplit(t.display_name, ':')
        vim.api.nvim_echo({
          { 'ToggleTerm ', 'MoreMsg' },
          { '(Term name: ' .. name_splt[1] .. ')', 'MoreMsg' },
          { '(Prev win ID: ' .. name_splt[2] .. ')', 'MoreMsg' },
          { '(Term Win ID: ' .. t.window .. ')', 'MoreMsg' },
          { '(Term Buffer#: ' .. t.bufnr .. ')', 'MoreMsg' },
          { '(Term id: ' .. t.id .. ')', 'MoreMsg' },
          { '(Job ID: ' .. t.job_id .. ')', 'MoreMsg' },
        }, true, {})
      end
    end,

    -- INFO: on_close()
    on_close = function(t)
      orig_window = tonumber(M.strsplit(t.display_name, ':')[2])
      ---@diagnostic disable-next-line: param-type-mismatch
      if orig_window and vim.api.nvim_win_is_valid(orig_window) then
        vim.api.nvim_set_current_win(orig_window)
      else
        vim.api.nvim_set_current_win(0)
      end
    end,

    -- -- INFO: on_exit()
    -- on_exit = function(_)
    --   exit_callback()
    -- end,

    -- INFO: on_stdout
    -- on_stdout = stdout_callback,
    on_stdout = M.dispatcher,

    -- INFO: on_create() {
    on_create = function(t)
      local platformio = vim.api.nvim_create_augroup(M.strsplit(t.display_name, ':')[1], { clear = true })

      -- INFO: CmdlineLeave
      vim.api.nvim_create_autocmd('CmdlineLeave', {
        group = platformio,
        -- pattern = ':',
        buffer = t.bufnr,
        callback = function()
          if vim.v.event and not vim.v.event.abort and vim.v.event.cmdtype == ':' then
            local quit = vim.fn.getcmdline() == 'q'
            local quitbang = vim.fn.getcmdline() == 'q!'
            if quitbang or quit then
              local name_splt = M.strsplit(t.display_name, ':')
              if quitbang then
                if name_splt[1] == 'piomon' then -- monitor terminal
                  local exit = vim.api.nvim_replace_termcodes('<C-C>exit', true, true, true)
                  send(t, exit)
                else -- cli terminal
                  send(t, 'exit')
                end
              end

              orig_window = tonumber(name_splt[2])
              vim.schedule(function()
                -- go back to previous window
                if orig_window and vim.api.nvim_win_is_valid(orig_window) then
                  vim.api.nvim_set_current_win(orig_window)
                else
                  vim.api.nvim_set_current_win(0)
                end
              end)
            end
          end
        end,
      })

      -- INFO: BufUnload
      vim.api.nvim_create_autocmd('BufUnload', {
        group = platformio,
        desc = 'toggleterm buffer unloaded',
        buffer = t.bufnr,
        callback = function(args)
          vim.keymap.del('t', '<Esc>', { buffer = args.buf })
          vim.keymap.del('n', '<Esc>', { buffer = args.buf })

          -- clear autommmand when quit
          vim.api.nvim_clear_autocmds({ group = M.strsplit(t.display_name, ':')[1] })
        end,
      })
    end,
  }
  -- INFO: termConfig table end

  termConfig = vim.tbl_deep_extend('force', termConfig, pioOpts or {})

  -- INFO: create new terminal
  local terminal = require('toggleterm.terminal').Terminal:new(termConfig)
  if prev.term and prev.float then
    prev.term:close()
  end
  terminal:toggle()
  vim.defer_fn(function()
    if command and command ~= '' then
      send(terminal, command)
    end
  end, 50) -- 50ms delay, adjust as needed sgget
end

----------------------------------------------------------------------------------------

local paths = { '.', '..', pathmul(1), pathmul(2), pathmul(3), pathmul(4), pathmul(5) }

function M.file_exists(name)
  local f = io.open(name, 'r')
  if f ~= nil then
    io.close(f)
    return true
  else
    return false
  end
end

function M.set_platformioRootDir()
  if vim.g.platformioRootDir ~= nil then
    return
  end
  for _, path in pairs(paths) do
    if M.file_exists(path .. '/platformio.ini') then
      vim.g.platformioRootDir = path
      return
    end
  end
  vim.notify('Could not find platformio.ini, run :Pioinit to create a new project', vim.log.levels.ERROR)
end

function M.cd_pioini()
  M.set_platformioRootDir()
  vim.cmd('cd ' .. vim.g.platformioRootDir)
end

function M.pio_install_check()
  local handel = (jit.os == 'Windows') and assert(io.popen('where.exe pio 2>./nul')) or assert(io.popen('which pio 2>/dev/null'))
  local pio_path = assert(handel:read('*a'))
  handel:close()

  if #pio_path == 0 then
    vim.notify('Platformio not found in the path', vim.log.levels.ERROR)
    return false
  end
  return true
end

function M.async_shell_cmd(cmd, callback)
  local output = {}

  vim.fn.jobstart(cmd, {
    stdout_buffered = true,
    stderr_buffered = false,

    on_stdout = function(_, data)
      if data then
        for _, line in ipairs(data) do
          if line ~= '' then
            table.insert(output, line)
          end
        end
      end
    end,

    on_exit = function(_, code)
      callback(output, code)
    end,
  })
end

function M.shell_cmd_blocking(command)
  local handle = io.popen(command, 'r')
  if not handle then
    return nil, 'failed to run command'
  end

  local result = handle:read('*a')
  handle:close()

  return result
end

return M
