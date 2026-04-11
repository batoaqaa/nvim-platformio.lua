local M = {}

M.selected_framework = ''

local misc = require('platformio.utils.misc')
local lsp = require('platformio.utils.lsp')

------------------------------------------------------
-- stylua: ignore
function M.get_pio_dir(type)
  -- 1. Setup Base Paths
  local home = os.getenv('HOME') or os.getenv('USERPROFILE')

  -- 2. Define Mapping (key in INI, Env Var, Default Subfolder)
  local map = {
    core = { ini = 'core_dir', env = 'PLATFORMIO_CORE_DIR', sub = '/.platformio' },
    packages = { ini = 'packages_dir', env = 'PLATFORMIO_PACKAGES_DIR', sub = '/packages' },
    platforms = { ini = 'platforms_dir', env = 'PLATFORMIO_PLATFORMS_DIR', sub = '/platforms' },
  }

  local core_ini, dir_ini = nil, nil
  local core_map, dir_map = map['core'], map[type]
  if not core_map and not dir_map then
    return nil
  end

  -- 3. Try to get explicit value from platformio.ini
  local handle = io.popen('pio project config --json-output')
  if handle then
    local json_str = handle:read('*all')
    local _, config = pcall(vim.json.decode, json_str)
    for _, section in ipairs(config) do
      if section[1] == 'platformio' then
        for _, kv in ipairs(section[2]) do
          if kv[1] == dir_map.ini then
            dir_ini = tostring(kv[2]):match('([^,%s]+)')
          end
          if kv[1] == core_map.ini then
            core_ini = kv[2]
          end
        end
        break
      end
    end
    handle:close()
  end

  -- 4.0 Fallback Logic: INI -> Env Var -> Default
  local core_dir = core_ini or os.getenv('PLATFORMIO_CORE_DIR' or (home .. map['core'].sub)):gsub('[\\/]+$', '')
  core_dir = misc.normalize_path(core_dir) --core_dir:gsub('\\', '/'):gsub('//+', '/')

  if type == 'core' then
    return core_dir
  end

  local  result = dir_ini or os.getenv(dir_map.env) or (core_dir .. dir_map.sub)

  -- 5. Expand ${platformio.core_dir}
  if result:find('${platformio.core_dir}', 1, true) then
    result = result:gsub('%${platformio.core_dir}', core_dir)
  end

  -- 6. Normalize Slashes for Windows
  result = misc.normalize_path(result) --result:gsub('\\', '/'):gsub('//+', '/')
  return result
end
-- function M.get_pio_dir(type)
--   -- 1. Setup Base Paths
--   local home = os.getenv('HOME') or os.getenv('USERPROFILE')
--
--   -- 2. Define Mapping (key in INI, Env Var, Default Subfolder)
--   local map = {
--     core = { ini = 'core_dir', env = 'PLATFORMIO_CORE_DIR', sub = '/.platformio' },
--     packages = { ini = 'packages_dir', env = 'PLATFORMIO_PACKAGES_DIR', sub = '/packages' },
--     platforms = { ini = 'platforms_dir', env = 'PLATFORMIO_PLATFORMS_DIR', sub = '/platforms' },
--   }
--
--   local target_config = map[type]
--   if not target_config then return nil end
--
--   -- 3. Try to get explicit value from platformio.ini
--   local path = vim.fn.getcwd() .. '/platformio.ini'
--   local inifile = io.open(path, 'r')
--   local ini_val = nil
--   local core_val = nil
--   -----------------------------------------------------
--   ---
--   -----------------------------------------------------
--
--   if inifile then
--     for line in inifile:lines() do
--       if core_val == nil then core_val = line:match('^%s*' .. map['core'].ini .. '%s*=%s*([^;%s]+)') end
--       if ini_val == nil then ini_val = line:match('^%s*' .. target_config.ini .. '%s*=%s*([^;%s]+)') end
--       if ini_val and core_val then break end
--     end
--     inifile:close()
--   end
--
--   -- 4.0 Fallback Logic: INI -> Env Var -> Default
--   local core_dir = core_val or os.getenv('PLATFORMIO_CORE_DIR' or (home .. map['core'].sub)):gsub('[\\/]+$', '')
--   core_dir = misc.normalize_path(core_dir) --core_dir:gsub('\\', '/'):gsub('//+', '/')
--   -- if vim.fn.has('win32') == 1 then core_dir = core_dir:gsub('/', '\\') end
--   if type == 'core' then return core_dir end
--
--   -- 4.1 Fallback Logic: INI -> Env Var -> Default
--   local result = ini_val or os.getenv(target_config.env) or (core_dir .. target_config.sub)
--
--   -- 5. Expand ${platformio.core_dir}
--   if result:find('${platformio.core_dir}', 1, true) then result = result:gsub('%${platformio.core_dir}', core_dir) end
--
--   -- 6. Normalize Slashes for Windows
--   result = misc.normalize_path(result) --result:gsub('\\', '/'):gsub('//+', '/')
--   -- if vim.fn.has('win32') == 1 then result = result:gsub('/', '\\') end
--
--   -- Ensure core_dir itself doesn't have trailing slashes for cleaner joins
--   return result
-- end
------------------------------------------------------

--- stylua: ignore
function _G.get_pio_toolchain_pattern()
  local cwd = vim.fn.getcwd()
  local cache_key = cwd .. (vim.g.pio_active_env or 'auto')

  _G._pio_cache = _G._pio_cache or {}
  if _G._pio_cache[cache_key] then
    return _G._pio_cache[cache_key]
  end

  local handle = io.popen('pio project config --json-output')
  if not handle then
    return '**/toolchain-*/**/bin/*'
  end
  local json_str = handle:read('*all')
  handle:close()

  local ok, config = pcall(vim.json.decode, json_str)
  if not ok or not config then
    return '**/toolchain-*/**/bin/*'
  end

  local active_env = vim.g.pio_active_env
  local target_platform = nil
  local core_dir = (os.getenv('HOME') or os.getenv('USERPROFILE')) .. '/.platformio'

  -- 1. Pass One: Extract default_envs and core_dir from 'platformio' section
  if not active_env then
    for _, section in ipairs(config) do
      if section[1] == 'platformio' then
        for _, kv in ipairs(section[2]) do
          if kv[1] == 'default_envs' then
            active_env = tostring(kv[2]):match('([^,%s]+)')
          end
          if kv[1] == 'core_dir' then
            core_dir = kv[2]
          end
        end
      end
    end
  end

  -- 2. Pass Two: Find the platform for the active environment
  for _, section in ipairs(config) do
    local name = section[1]
    if active_env and (name == 'env:' .. active_env or name == active_env) then
      for _, kv in ipairs(section[2]) do
        if kv[1] == 'platform' then
          target_platform = kv[2]
        end
      end
    end
  end

  -- 3. Fallback: If still nothing, take the first platform from any 'env:' section
  if not target_platform then
    for _, section in ipairs(config) do
      if type(section[1]) == 'string' and section[1]:find('^env:') then
        for _, kv in ipairs(section[2]) do
          if kv[1] == 'platform' then
            target_platform = kv[2]
          end
        end
        if target_platform then
          break
        end
      end
    end
  end

  if not target_platform then
    return '**/toolchain-*/**/bin/*'
  end

  -- 4. Query the platform for the toolchain package name
  local p_handle = io.popen('pio platform show ' .. target_platform .. ' --json-output')
  if not p_handle then
    return '**/toolchain-*/**/bin/*'
  end
  local p_json = p_handle:read('*all')
  p_handle:close()

  local p_ok, p_data = pcall(vim.json.decode, p_json)
  if not p_ok or not p_data.packages then
    return '**/toolchain-*/**/bin/*'
  end

  -- 5. Extract Arch
  local arch_glob = '**/toolchain-*/**/bin/*'
  for pkg_name, _ in pairs(p_data.packages) do
    if type(pkg_name) == 'string' and pkg_name:find('^toolchain%-') then
      local arch = pkg_name:gsub('toolchain%-', ''):gsub('gcc%-?', '')
      arch_glob = '/**/bin/*' .. arch .. '*'
      break
    end
  end

  local final_pattern = (core_dir:gsub('\\', '/') .. '/packages' .. arch_glob):gsub('//+', '/')
  -- if vim.fn.has('win32') == 1 then
  --   final_pattern = final_pattern:gsub('/', '\\')
  -- end

  _G._pio_cache[cache_key] = final_pattern
  print('tollchain 9.0: final_pattern=' .. final_pattern)
  return final_pattern
end
-- local function normalize(path)
--   return path:gsub('\\', '/'):gsub('//+', '/')
-- end
--
-- function _G.get_pio_toolchain_pattern()
--   local cwd = vim.fn.getcwd()
--   local cache_key = cwd .. (vim.g.pio_active_env or 'auto')
--
--   -- 1. Session Cache for Speed
--   _G._pio_cache = _G._pio_cache or {}
--   if _G._pio_cache[cache_key] then
--     return _G._pio_cache[cache_key]
--   end
--
--   -- 2. Fetch Project Config
--   local handle = io.popen('pio project config --json-output')
--   if not handle then
--     return '/**/bin/*gcc*'
--   end
--   local json_str = handle:read('*all')
--   handle:close()
--   print('tollchain 2.0')
--
--   local ok, config = pcall(vim.json.decode, json_str)
--   if not ok or not config then
--     return '/**/bin/*gcc*'
--   end
--   print('tollchain 2.1')
--
--   local active_env = vim.g.pio_active_env
--   local target_platform = nil
--   local home = os.getenv('HOME') or os.getenv('USERPROFILE')
--   local core_dir = home .. '/.platformio'
--
--   -- 3. Parse Nested Array Structure
--   -- Structure: { { "section_name", { {"key", "val"}, ... } }, ... }
--
--   -- First Pass: Determine Active Env if not set
--   if not active_env then
--     for _, section in ipairs(config) do
--       if section[1] == 'platformio' then
--         for _, kv in ipairs(section[2]) do
--           if kv[1] == 'default_envs' then
--             active_env = tostring(kv[2]):match('([^,%s]+)')
--           elseif kv[1] == 'core_dir' then
--             core_dir = kv[2]
--           end
--         end
--       end
--     end
--   end
--   print('tollchain 3.0')
--
--   -- Second Pass: Find Platform for the Active Env
--   for _, section in ipairs(config) do
--     local name = section[1]
--     if active_env and (name == 'env:' .. active_env or name == active_env) then
--       for _, kv in ipairs(section[2]) do
--         if kv[1] == 'platform' then
--           target_platform = kv[2]
--         end
--       end
--     end
--   end
--
--   print('tollchain 4.0')
--   -- Fallback: If still no env, pick the first one available
--   if not target_platform then
--     for _, section in ipairs(config) do
--       if section[1]:find('^env:') then
--         for _, kv in ipairs(section[2]) do
--           if kv[1] == 'platform' then
--             target_platform = kv[2]
--           end
--         end
--         if target_platform then
--           break
--         end
--       end
--     end
--   end
--
--   if not target_platform then
--     return '/**/bin/*gcc*'
--   end
--   print('tollchain 5.0')
--
--   -- 4. Query Platform for Toolchain Package Name
--   local p_handle = io.popen('pio platform show ' .. target_platform .. ' --json-output')
--   if not p_handle then
--     return '/**/bin/*gcc*'
--   end
--   print('tollchain 6.0')
--   local p_json = p_handle:read('*all')
--   p_handle:close()
--
--   local p_ok, p_data = pcall(vim.json.decode, p_json)
--   if not p_ok or not p_data.packages then
--     return '/**/bin/*gcc*'
--   end
--   print('tollchain 7.0')
--
--   -- 5. Extract Arch and Build Pattern
--   local arch_glob = '/**/bin/*gcc*'
--   for pkg_name, _ in pairs(p_data.packages) do
--     if type(pkg_name) == 'string' and pkg_name:find('^toolchain%-') then
--       local arch = pkg_name:gsub('toolchain%-', ''):gsub('gcc%-?', '')
--       arch_glob = '/**/bin/*' .. arch .. '*gcc*'
--       break
--     end
--   end
--
--   print('tollchain 8.0')
--   -- 6. Final Path Assembly
--   local packages_path = normalize(core_dir .. '/packages')
--   local final_pattern = normalize(packages_path .. arch_glob)
--
--   if vim.fn.has('win32') == 1 then
--     final_pattern = final_pattern:gsub('/', '\\')
--   end
--
--   print('tollchain 9.0: final_pattern=' .. final_pattern)
--   _G._pio_cache[cache_key] = final_pattern
--   return final_pattern
-- end
--
---
------------------------------------------------------
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
        lsp.lsp_restart('clangd')
      end
    end
  end
end

------------------------------------------------------
-- INFO: Dispatcher

M.queue = {}
local pio_buffer = '' -- Persistent stream buffer

------------------------------------------------------
-- The Dispatcher (The Brain)
-- stylua: ignore
function M.dispatcher(_, _, data)
  if #M.queue == 0 then return end

  -- 1. attach partial buffer from previous data last line to 1st line 
  pio_buffer = pio_buffer .. data[1]
  -- 2. If the chunk has more than one element, we've encountered newlines
  if #data > 1 then
    -- 3. Process any "middle" lines which are guaranteed to be complete
    for i = 2, #data - 1 do pio_buffer = pio_buffer .. data[i] end

    for status in pio_buffer:gmatch('___DONE___:(%a+)') do
      if status then
        if status == 'SUCCESS' then
          -- 4. Store the last element as the new partial buffer for the next call
          pio_buffer = data[#data]
          local task = table.remove(M.queue, 1)
          if task then vim.schedule(task) end
        elseif status == 'FAILED' then
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

------------------------------------------------------
-- stylua: ignore
M.run_sequence = function(tasks)
  -- Reset local state for new run
  M.queue = {}
  pio_buffer = ''
  local full_cmd = ''

  local success = 'echo ___DONE___":"SUCCESS'
  local failure = 'echo ___DONE___":"FAILED'

  for _, task in ipairs(tasks) do
    table.insert(M.queue, task.cb)
    local part = string.format('%s && %s', task.cmd, success)
    if full_cmd == '' then full_cmd = part
    else full_cmd = full_cmd .. ' && ' .. part end -- Chain multiple commands
  end
  full_cmd = full_cmd .. ' || ' .. failure
  local ToggleTerminal = require('platformio.utils.term').ToggleTerminal
  ToggleTerminal(full_cmd, 'float')
end

------------------------------------------------------
-- Handle after 'pio run -t compiledb' execution
function M.handleDb()
  vim.notify('compiledb: compile_commands.json generated/updated', vim.log.levels.INFO)
  misc.gitignore_lsp_configs('compile_commands.json')
  M.fix_pio_compile_commands()
  lsp.lsp_restart('clangd')
end

------------------------------------------------------
-- Handle after poioinit execution
-- stylua: ignore
function M.handlePioinit()
  vim.notify('Pioinit: Success', vim.log.levels.INFO)
  local boilerplate_gen = require('platformio.boilerplate').boilerplate_gen
  boilerplate_gen([[.clangd_cmd]], vim.g.platformioRootDir)
  boilerplate_gen(M.selected_framework, vim.fn.getcwd() .. '/src', 'main.cpp')
end
-- Handle after poioinit execution
-- stylua: ignore
function M.handlePiolib()
  vim.notify('Piolib: Success', vim.log.levels.INFO)
end
-- INFO: endDispatcher
------------------------------------------------------

return M
