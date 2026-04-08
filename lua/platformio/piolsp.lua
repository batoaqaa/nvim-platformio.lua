local M = {}

function M.fix_pio_compile_commands()
  local cwd = vim.fn.getcwd()
  local filename = cwd .. '/compile_commands.json'
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
  -- local pio_home = os.getenv('HOME') or os.getenv('USERPROFILE')
  local pio_home = os.getenv('PLATFORMIO_CORE_DIR') --or os.getenv('USERPROFILE')
  if pio_home then
    -- Recursively find all binaries in PIO packages
    -- local pio_packages = pio_home .. '/.platformio/packages/*/bin/*'
    local pio_packages = pio_home .. '/.platformio/packages/toolchain-*/bin/*'
    local found_binaries = vim.fn.glob(pio_packages, false, true)

    for _, full_path in ipairs(found_binaries) do
      -- Extract filename (e.g., riscv32-esp-elf-gcc)
      local name = full_path:match('([^/\\\\]+)$'):gsub('%.exe$', '')
      path_map[name] = full_path
      print('PioFix1: driver_path=' .. full_path .. ' name=' .. name)
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
          print('PioFix2: short_name=' .. short_name)
          -- Direct Query: Does this name exist in our discovered list?
          if path_map[short_name] then
            cmd_parts[1] = path_map[short_name]
            print('PioFix3: short_name=' .. cmd_parts[1])
            entry.command = table.concat(cmd_parts, ' ')
            modified = modified + 1
          end
        end
      end
    end
  end

  -- PHASE 3: Save and Refresh
  if modified > 0 then
    -- Safe JSON encoding
    local encode_ok, json_str = pcall(vim.json.encode, data, { indent = '  ' })
    if encode_ok and json_str then
      local out_file = io.open(filename, 'w')
      if out_file then
        out_file:write(json_str)
        out_file:close()
        vim.notify('compiledb: fixed', vim.log.levels.INFO)
        M.lsp_restart('clangd')
      end
    end
    -- local out_file = io.open(filename, 'w')
    -- if out_file then
    --   out_file:write(vim.json.encode(data, { indent = '  ' }))
    --   out_file:close()
    --   vim.notify('PIO: Auto-resolved ' .. modified .. ' driver paths', vim.log.levels.INFO)
    --   M.lsp_restart('clangd')
    -- end
  end
end
-- function M.fix_pio_compile_commands()
--   local filename = 'compile_commands.json'
--   local file = io.open(filename, 'r')
--   if not file then
--     return
--   end
--
--   local content = file:read('*a')
--   file:close()
--   if not content or content == '' then
--     return
--   end
--
--   -- Safe JSON decoding
--   local ok, data = pcall(vim.json.decode, content)
--   if not ok or type(data) ~= 'table' then
--     vim.notify('PIO Fix: Invalid JSON in ' .. filename, vim.log.levels.ERROR)
--     return
--   end
--
--   -- print('PioFix0')
--   -- PHASE 1: Scan Disk to build a Map of Name -> Absolute Path
--   local path_map = {}
--   -- local pio_home = os.getenv('HOME') or os.getenv('USERPROFILE')
--   local pio_home = os.getenv('PLATFORMIO_CORE_DIR') --or os.getenv('USERPROFILE')
--   print('PIO Home ' .. pio_home)
--   if pio_home then
--     -- Recursively find all binaries in PIO packages
--     local pio_packages = pio_home .. '/.platformio/packages/*/bin/*'
--     local found_binaries = vim.fn.glob(pio_packages, false, true)
--
--     for _, full_path in ipairs(found_binaries) do
--       -- Extract filename (e.g., riscv32-esp-elf-gcc)
--       local name = full_path:match('([^/\\\\]+)$'):gsub('%.exe$', '')
--       path_map[name] = full_path
--       print('PioFix1: driver_path=' .. full_path .. ' name=' .. name)
--     end
--   end
--
--   -- PHASE 2: Update JSON using the Map
--   local modified = 0
--   for _, entry in ipairs(data) do
--     if type(entry.command) == 'string' then
--       local cmd_parts = vim.split(entry.command, ' ')
--       local first_token = cmd_parts[1]
--
--       if first_token then
--         -- Check if it's already a short name (not an absolute path)
--         local is_abs = first_token:sub(1, 1) == '/' or first_token:match('^%a:[/\\]')
--
--         if not is_abs then
--           local short_name = first_token:gsub('%.exe$', '')
--           print('PioFix2: short_name=' .. short_name)
--           -- Direct Query: Does this name exist in our discovered list?
--           if path_map[short_name] then
--             cmd_parts[1] = path_map[short_name]
--             print('PioFix3: short_name=' .. cmd_parts[1])
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
--   local encode_ok, json_str = pcall(vim.json.encode, data, { indent = '  ' })
--   if encode_ok and json_str then
--     local out_file = io.open(filename, 'w')
--     if out_file then
--       out_file:write(json_str)
--       out_file:close()
--       vim.notify('compiledb: fixed', vim.log.levels.INFO)
--       M.lsp_restart('clangd')
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
  if vim.fn.has('nvim-0.12') == 1 then
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
  local ok, err = pcall(vim.cmd.lsp, { args = { 'restart' } })
  if ok then
    vim.notify('LSP restarted' .. err)
  else
    vim.notify('LSP restart failed: ' .. err)
  end
  -- M.fix_pio_compile_commands()

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
  -- vim.cmd('lsp restart clangd')
  -- end
  -- else
  -- vim.cmd('LspRestart')
  -- end
end

return M
