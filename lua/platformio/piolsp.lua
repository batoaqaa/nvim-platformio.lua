local M = {}

local boilerplate_gen = require('platformio.boilerplate').boilerplate_gen

function M.cleanup(selected_framework)
  vim.notify('LSP: compile_commands.json generation/update completed!', vim.log.levels.INFO)
  M.fix_pio_compile_commands()
  M.gitignore_lsp_configs('compile_commands.json')
  boilerplate_gen(selected_framework, vim.fn.getcwd() .. '/src', 'main.cpp')
  M.lsp_restart('clangd')
end

function M.fix_pio_compile_commands()
  local filename = 'compile_commands.json'
  local file = io.open(filename, 'r')
  if not file then
    return
  end

  local content = file:read('*a')
  file:close()
  if not content or content == '' then
    return
  end

  -- Safe JSON decoding
  local ok, data = pcall(vim.json.decode, content)
  if not ok or type(data) ~= 'table' then
    vim.notify('PIO Fix: Invalid JSON in ' .. filename, vim.log.levels.ERROR)
    return
  end

  print('PioFix0')
  -- PHASE 1: Scan Disk to build a Map of Name -> Absolute Path
  local path_map = {}
  local pio_home = os.getenv('HOME') or os.getenv('USERPROFILE')
  if pio_home then
    -- Recursively find all binaries in PIO packages
    local pio_packages = pio_home .. '/.platformio/packages/*/bin/*'
    local found_binaries = vim.fn.glob(pio_packages, false, true)

    for _, full_path in ipairs(found_binaries) do
      -- Extract filename (e.g., riscv32-esp-elf-gcc)
      local name = full_path:match('([^/\\\\]+)$'):gsub('%.exe$', '')
      path_map[name] = full_path
      print('PioFix: driver_path=' .. full_path .. ' name=' .. name)
    end
  end

  -- PHASE 2: Update JSON using the Map
  local modified = 0
  for _, entry in ipairs(data) do
    if type(entry.command) == 'string' then
      local cmd_parts = vim.split(entry.command, ' ')
      local first_token = cmd_parts[1]

      if first_token then
        -- Check if it's already a short name (not an absolute path)
        local is_abs = first_token:sub(1, 1) == '/' or first_token:match('^%a:[/\\]')

        if not is_abs then
          local short_name = first_token:gsub('%.exe$', '')
          print('PioFix: short_name=' .. short_name)
          -- Direct Query: Does this name exist in our discovered list?
          if path_map[short_name] then
            cmd_parts[1] = path_map[short_name]
            entry.command = table.concat(cmd_parts, ' ')
            modified = modified + 1
          end
        end
      end
    end
  end

  -- PHASE 3: Save and Refresh
  -- Safe JSON encoding
  local encode_ok, json_str = pcall(vim.json.encode, data, { indent = '  ' })
  if encode_ok and json_str then
    local out_file = io.open(filename, 'w')
    if out_file then
      out_file:write(json_str)
      out_file:close()
      vim.cmd('LspRestart')
    end
  end
end

-- function M.fix_pio_compile_commands()
--   local cwd = vim.fn.getcwd()
--   local filename = cwd .. '/compile_commands.json'
--   print('PioFix0:' .. filename)
--   local file = io.open(filename, 'r')
--   if not file then
--     return
--   end
--
--   local content = file:read('*a')
--   file:close()
--
--   local ok, data = pcall(vim.json.decode, content)
--   if not ok or type(data) ~= 'table' then
--     return
--   end
--
--   local path_map = {}
--   local modified = 0
--   print('PioFix0')
--   -- Phase 1: Discover paths
--   for _, entry in ipairs(data) do
--     if type(entry.command) == 'string' then
--       -- Handle both spaces and potential escaped quotes in commands
--       local cmd_parts = vim.split(entry.command, ' ')
--       local driver_path = cmd_parts[1]
--
--       if driver_path then
--         -- Detect Absolute Path: Starts with / (Linux) or X:\ (Windows)
--         local is_abs = driver_path:sub(1, 1) == '/' or driver_path:match('^%a:[/\\]')
--
--         if is_abs then
--           -- Extract name: works for /path/to/gcc and C:\path\to\gcc.exe
--           local name = driver_path:match('([^/\\\\]+)$'):gsub('%.exe$', '')
--           path_map[name] = driver_path
--           print('PioFix1: driver_path=' .. driver_path .. ' name=' .. name)
--         end
--       end
--     end
--   end
--
--   print('PioFix2')
--   -- Phase 2: Replace bare names
--   for _, entry in ipairs(data) do
--     if type(entry.command) == 'string' then
--       local cmd_parts = vim.split(entry.command, ' ')
--       local first = cmd_parts[1]
--
--       if first then
--         local is_abs = first:sub(1, 1) == '/' or first:match('^%a:[/\\]')
--         if not is_abs then
--           local short_name = first:gsub('%.exe$', '')
--           print('PioFix20:' .. short_name)
--           if path_map[short_name] then
--             cmd_parts[1] = path_map[short_name]
--             entry.command = table.concat(cmd_parts, ' ')
--             modified = modified + 1
--           end
--         end
--       end
--     end
--   end
--
--   print('PioFix3')
--   if modified > 0 then
--     print('PioFix4')
--     local out_file = io.open(filename, 'w')
--     if out_file then
--       -- Encode with 2-space indentation
--       local success, json_str = pcall(vim.json.encode, data, { indent = '  ' })
--
--       print('PioFix5')
--       if success then
--         print('PioFix6')
--         out_file:write(json_str)
--         out_file:close()
--         vim.notify('PIO: Paths fixed and JSON formatted.', vim.log.levels.INFO)
--         M.lsp_restart('clangd')
--       else
--         print('PioFix7')
--         out_file:close()
--         vim.notify('LSP: Failed to encode JSON', vim.log.levels.ERROR)
--       end
--     end
--   end
-- end

-- -- Cache the toolchain path once globally so we don't glob on every save
-- local cached_toolchain = nil
--
-- function M.fix_pio_compile_commands()
--   local cwd = vim.fn.getcwd()
--   local json_path = cwd .. '/compile_commands.json'
--
--   -- 1. Performance: Check if file exists and get last modified time
--   local stats = vim.loop.fs_stat(json_path)
--   if not stats then
--     if vim.fn.filereadable(cwd .. '/platformio.ini') == 1 then
--       vim.fn.system('pio run -t compiledb')
--       stats = vim.loop.fs_stat(json_path) -- Re-check after gen
--     end
--   end
--   if not stats then
--     return
--   end
--
--   -- 2. Performance: Only run if the file was modified in the last 5 seconds
--   -- This prevents re-parsing the JSON every time you hit :w
--   local now = os.time()
--   if (now - stats.mtime.sec) > 5 and _G.PIO_FIXED_ONCE then
--     return
--   end
--
--   -- 3. Get Toolchain (Cached)
--   if not cached_toolchain then
--     local glob = vim.fn.glob(vim.env.HOME .. '/.platformio/packages/toolchain-*/bin/')
--     if glob == '' then
--       return
--     end
--     cached_toolchain = vim.split(glob, '\n')[1] -- Ensure single string
--   end
--
--   -- 4. Safe Read
--   local file = io.open(json_path, 'r')
--   if not file then
--     return
--   end
--   local content = file:read('*all')
--   file:close()
--   if not content or content == '' then
--     return
--   end
--
--   -- 5. Safe Decode
--   local ok, data = pcall(vim.json.decode, content)
--   if not ok or type(data) ~= 'table' then
--     return
--   end
--
--   local changed = false
--   for _, entry in ipairs(data) do
--     -- Defensive Nil Checks
--     if type(entry) == 'table' and entry.command then
--       -- Prepend only if relative and not already fixed
--       if not entry.command:match('^/') and not entry.command:find(cached_toolchain, 1, true) then
--         entry.command = cached_toolchain .. entry.command
--         changed = true
--       end
--     end
--   end
--
--   -- 6. Safe Save
--   if changed then
--     local out = io.open(json_path, 'w')
--     if out then
--       out:write(vim.json.encode(data, { indent = '  ' }))
--       out:close()
--       _G.PIO_FIXED_ONCE = true
--       vim.schedule(function()
--         print('PIO: Database optimized')
--         M.lsp_restarti('clangd')
--       end)
--     end
--   end
-- end

function M.gitignore_lsp_configs(config_file)
  local gitignore_path = vim.fs.joinpath(vim.g.platformioRootDir, '.gitignore')
  local file = io.open(gitignore_path, 'r')
  local pattern = '^%s*' .. vim.pesc(config_file) .. '%s*$'

  if file then
    for line in file:lines() do
      if line:match(pattern) then
        file:close()
        return
      end
    end
    file:close()
  end

  file = io.open(gitignore_path, 'a')
  if file then
    file:write(config_file .. '\n')
    file:close()
  end
end

function M.lsp_restarti(name)
  local clients = vim.lsp.get_clients({ name = name })

  -- if #clients == 0 then
  --   -- I'm using my own implementation of `vim.lsp.enable()`
  --   -- To work with default one change group name from `MyLsp` to `nvim.lsp.enable`
  --   -- It is not tested with default one, so not sure if it would 100% work.
  --   vim.api.nvim_exec_autocmds('FileType', { group = 'nvim.lsp.enable', buffer = 0 })
  --   return
  -- end

  for _, c in ipairs(clients) do
    local configc = c.config
    -- print(vim.inspect(configc))
    c:stop(true)

    vim.defer_fn(function()
      vim.lsp.config(name, configc)
      vim.lsp.enable(name)
    end, 600)
  end
end

function M.lsp_restart(name)
  if vim.fn.has('nvim-0.11') == 1 then
    -- local clients = vim.lsp.get_clients({ name = name })
    local clangd = vim.lsp.get_clients({ name = name })[1]

    if clangd then
      -- Client is active, try to restart
      local ok, err = pcall(vim.cmd.lsp, { args = { 'restart', 'clangd' } })
      if not ok then
        vim.notify('LSP ' .. name .. ' restart failed: ' .. err)
      else
        vim.notify('LSP ' .. name .. ' restarted' .. err)
      end
    end
  else
    vim.cmd('LspRestart')
  end
end

function M.piolsp()
  M.fix_pio_compile_commands()

  --
  --
  -- if not utils.pio_install_check() then
  --   return
  -- end
  -- utils.cd_pioini()
  --
  -- utils.shell_cmd_blocking('pio run -t compiledb')
  -- vim.notify('LSP: compile_commands.json generation/update completed!', vim.log.levels.INFO)
  -- M.gitignore_lsp_configs('compile_commands.json')
  --
  -- -- if vim.fn.has('nvim-0.12') then
  -- -- local clangd = vim.lsp.get_clients({ name = 'clangd' })[1]
  -- -- if clangd then
  -- --   -- print('number of attaced: ' .. #clangd.attached_buffers)
  -- --   -- print('piolsp: lsp restart ' .. clangd.name)
  -- -- pcall(vim.cmd.lsp, { args = { 'restart', 'clangd' } })
  -- M.lsp_restart('clangd')
  -- -- vim.cmd('lsp restart clangd')
  -- -- end
  -- -- else
  -- -- vim.cmd('LspRestart')
  -- -- end
end

return M
