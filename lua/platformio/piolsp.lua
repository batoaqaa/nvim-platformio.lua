local M = {}

-- stylua: ignore
function M.get_pio_dir(type)
  -- 1. Setup Base Paths
  local home = os.getenv('HOME') or os.getenv('USERPROFILE')
  -- Ensure core_dir itself doesn't have trailing slashes for cleaner joins
  local core_dir = (os.getenv('PLATFORMIO_CORE_DIR') or (home .. '/.platformio')):gsub('[\\/]+$', '')

  -- 2. Define Mapping (key in INI, Env Var, Default Subfolder)
  local map = {
    packages = { ini = 'packages_dir', env = 'PLATFORMIO_PACKAGES_DIR', sub = '/packages' },
    platforms = { ini = 'platforms_dir', env = 'PLATFORMIO_PLATFORMS_DIR', sub = '/platforms' },
  }

  local target_config = map[type]
  if not target_config then return nil end

  -- 3. Try to get explicit value from platformio.ini
  local path = vim.fn.getcwd() .. '/platformio.ini'
  local inifile = io.open(path, 'r')
  local raw_val = nil

  if inifile then
    for line in inifile:lines() do
      raw_val = line:match('^%s*' .. target_config.ini .. '%s*=%s*([^;%s]+)')
      if raw_val then break end
    end
    inifile:close()
  end

  -- 4. Fallback Logic: INI -> Env Var -> Default
  local result = raw_val or os.getenv(target_config.env) or (core_dir .. target_config.sub)

  -- 5. Expand ${platformio.core_dir}
  if result:find('${platformio.core_dir}', 1, true) then result = result:gsub('%${platformio.core_dir}', core_dir) end

  -- 6. Normalize Slashes for Windows
  result = result:gsub('\\', '/'):gsub('//+', '/')
  if vim.fn.has('win32') == 1 then result = result:gsub('/', '\\') end

  return result
end

-- stylua: ignore
function M.fix_pio_compile_commands()
  local filename = vim.fn.getcwd() .. '/compile_commands.json'
  local file = io.open(filename, 'r')
  if not file then return end

  local content = file:read('*a')
  file:close()
  if not content or content == '' then return end

  -- Safe JSON decoding
  local ok, data = pcall(vim.json.decode, content)
  if not ok or type(data) ~= 'table' then
    vim.notify('PIO Fix: Invalid JSON in ' .. filename, vim.log.levels.ERROR)
    return
  end

  -- print('PioFix0')
  -- PHASE 1: Scan Disk to build a Map of Name -> Absolute Path
  local path_map = {}
  local pio_home = os.getenv('PLATFORMIO_CORE_DIR') --or os.getenv('USERPROFILE')
  if pio_home then

    -- Recursively find all binaries in PIO packages
    local pio_packages = M.get_pio_dir('packages') .. '/*/bin/*'

    local found_binaries = vim.fn.glob(pio_packages, false, true)

    for _, full_path in ipairs(found_binaries) do
      -- Extract filename (e.g., riscv32-esp-elf-gcc)
      local name = full_path:match('([^/\\\\]+)$'):gsub('%.exe$', '')
      path_map[name] = full_path
      -- print('PioFix1: driver_path=' .. full_path .. ' name=' .. name)
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
          -- print('PioFix2: short_name=' .. short_name)
          -- Direct Query: Does this name exist in our discovered list?
          if path_map[short_name] then
            cmd_parts[1] = path_map[short_name]
            -- print('PioFix3: full_name=' .. cmd_parts[1])
            entry.command = table.concat(cmd_parts, ' ')
            modified = modified + 1
          end
        end
      end
    end
  end

  -- PHASE 3: Save and Refresh
  -- Safe JSON encoding
  if modified > 0 then
    local out_file = io.open(filename, 'w')
    if out_file then
      local encode_ok, json_str = pcall(vim.json.encode, data, { indent = '  ' })
      if encode_ok and json_str then
        -- 1. Format the string using python's json.tool
        -- The second argument to vim.fn.system() is the "stdin" passed to the command
        local formatted_json = vim.fn.system('python -m json.tool', json_str)

        -- out_file:write(json_str)
        out_file:write(formatted_json)
        out_file:close()
        vim.notify('compiledb: fixed', vim.log.levels.INFO)
        M.lsp_restart('clangd')
      end
    end
  end
end

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

-- stylua: ignore
function M.lsp_restarti(name)
  local clients = vim.lsp.get_clients({ name = name })
  for _, c in ipairs(clients) do
    local configc = c.config
    c:stop(true)
    vim.defer_fn(function() vim.lsp.config(name, configc) vim.lsp.enable(name) end, 600)
  end
end

--- stylua: ignore
function M.lsp_restart(name)
  if vim.fn.has('nvim-0.12') == 1 then
    -- local clients = vim.lsp.get_clients({ name = name })
    local clangd = vim.lsp.get_clients({ name = name })[1]
    if clangd then
      local ok, err = pcall(vim.cmd.lsp, { args = { 'restart', 'clangd' } })
      if not ok then
        vim.notify('LSP ' .. name .. ' restart failed: ' .. err)
      else
        vim.notify('LSP ' .. name .. ' restarted' .. err)
      end
    end
  else
    local clients = vim.lsp.get_clients({ name = name })
    for _, c in ipairs(clients) do
      local configc = c.config
      c:stop(true)
      vim.defer_fn(function()
        vim.lsp.config(name, configc)
        vim.lsp.enable(name)
      end, 600)
    end
    -- -- 1. Stop the specific client
    -- for _, client in ipairs(clients) do client:stop() end
    --
    -- -- 2. Reload all loaded buffers to trigger re-attachment for that client
    -- -- (Note: 'checktime' is safer than 'bufdo edit' as it respects unsaved changes)
    -- vim.cmd('checktime')
  end
end

-- stylua: ignore
function M.piolsp()
  local ok, err = pcall(vim.cmd.lsp, { args = { 'restart' } })
  if ok then vim.notify('LSP restarted' .. err)
  else vim.notify('LSP restart failed: ' .. err) end
  -- M.fix_pio_compile_commands()
end

return M
