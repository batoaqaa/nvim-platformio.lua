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
--   -- local pio_binaries = (_G.metadata.toolchain_root or "") .. '/bin/*'
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

function M.compile_commandsFix()
  local filename = vim.uv.cwd() .. '/compile_commands.json'
  local file = io.open(filename, 'r')
  if not file then
    return
  end

  -- read compile_commands.json file to content
  local content = file:read('*a')
  file:close()
  if not content or content == '' then
    return
  end

  -- JSON decoding content to data
  local ok, data = pcall(vim.json.decode, content)
  if not ok or type(data) ~= 'table' then
    vim.notify('PIO Fix: Invalid JSON in ' .. filename, vim.log.levels.ERROR)
    return
  end

  print('PioFix0')
  -- PHASE 1: Scan Disk to build a Map of Name -> Absolute Path
  local path_map = {}
  local pio_home = _G.metadata.core_dir --os.getenv('PLATFORMIO_CORE_DIR') --or os.getenv('USERPROFILE')
  if pio_home then
    -- Recursively find all binaries in PIO packages
    local pio_packages = _G.metadata.toolchain_root .. '/bin/*' --M.get_pio_dir('packages') .. '/*/bin/*'
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
        lsp_restart('clangd')
        _G.metadata.isBusy = false
      end
    end
  end
end
