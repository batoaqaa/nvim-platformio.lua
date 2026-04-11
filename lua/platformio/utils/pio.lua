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

  local target_config = map[type]
  if not target_config then return nil end

  -- 3. Try to get explicit value from platformio.ini
  local path = vim.fn.getcwd() .. '/platformio.ini'
  local inifile = io.open(path, 'r')
  local ini_val = nil
  local core_val = nil

  if inifile then
    for line in inifile:lines() do
      if core_val == nil then core_val = line:match('^%s*' .. map['core'].ini .. '%s*=%s*([^;%s]+)') end
      if ini_val == nil then ini_val = line:match('^%s*' .. target_config.ini .. '%s*=%s*([^;%s]+)') end
      if ini_val and core_val then break end
    end
    inifile:close()
  end

  -- 4.0 Fallback Logic: INI -> Env Var -> Default
  local core_dir = core_val or os.getenv('PLATFORMIO_CORE_DIR' or (home .. map['core'].sub)):gsub('[\\/]+$', '')
  core_dir = misc.normalize_path(core_dir) --core_dir:gsub('\\', '/'):gsub('//+', '/')
  -- if vim.fn.has('win32') == 1 then core_dir = core_dir:gsub('/', '\\') end
  if type == 'core' then return core_dir end

  -- 4.1 Fallback Logic: INI -> Env Var -> Default
  local result = ini_val or os.getenv(target_config.env) or (core_dir .. target_config.sub)

  -- 5. Expand ${platformio.core_dir}
  if result:find('${platformio.core_dir}', 1, true) then result = result:gsub('%${platformio.core_dir}', core_dir) end

  -- 6. Normalize Slashes for Windows
  result = misc.normalize_path(result) --result:gsub('\\', '/'):gsub('//+', '/')
  -- if vim.fn.has('win32') == 1 then result = result:gsub('/', '\\') end

  -- Ensure core_dir itself doesn't have trailing slashes for cleaner joins
  return result
end
------------------------------------------------------

--- stylua: ignore
function _G.get_pio_toolchain_pattern()
  local cwd = vim.fn.getcwd()
  local cache_key = cwd .. (vim.g.pio_active_env or 'auto')

  if _G._pio_cache and _G._pio_cache[cache_key] then
    return _G._pio_cache[cache_key]
  end

  local handle = io.popen('pio project config --json-output')
  if not handle then
    return '/**/bin/*gcc*'
  end
  local json_str = handle:read('*all')
  handle:close()

  local ok, config = pcall(vim.json.decode, json_str)
  if not ok or not config then
    return '/**/bin/*gcc*'
  end

  local active_env = vim.g.pio_active_env
  local env_data = nil
  local core_dir = (os.getenv('HOME') or os.getenv('USERPROFILE')) .. '/.platformio'

  print('toolchain 1.0: core_dir= ' .. core_dir)
  -- 1. Find the target environment in the array of objects
  for _, item in ipairs(config) do
    if type(item) == 'table' then
      -- Identify the global 'platformio' config block
      if item.name == 'platformio' then
        core_dir = item.core_dir or core_dir
        print('toolchain 1.1: core_dir= ' .. core_dir)
        -- Priority: If no manual env is set, try to get default_envs
        if not active_env and item.default_envs then
          active_env = tostring(item.default_envs):match('([^,%s]+)')
          print('toolchain 1.1: active_env= ' .. active_env)
        end
      end

      -- If we have an active_env, find its specific table
      if active_env and (item.name == 'env:' .. active_env or item.name == active_env) then
        env_data = item
        print('toolchain 1.2: env_data= ' .. env_data)
      end
    end
  end

  -- 2. Fallback: If no env_data found yet, pick the first item starting with 'env:'
  print('toolchain 2.0')
  if not env_data then
    for _, item in ipairs(config) do
      if type(item) == 'table' and item.name and item.name:find('^env:') then
        env_data = item
        print('toolchain 2.1: env_data= ' .. env_data)
        break
      end
    end
  end

  if not env_data or not env_data.platform then
    return '/**/bin/*gcc*'
  end
  print('toolchain 3.0')

  -- 3. Resolve the Toolchain Path
  local packages_base = core_dir:gsub('\\', '/') .. '/packages'
  local p_handle = io.popen('pio platform show ' .. env_data.platform .. ' --json-output')
  if not p_handle then
    return packages_base .. '/**/bin/*gcc*'
  end
  print('toolchain 3.1')
  local p_json = p_handle:read('*all')
  p_handle:close()

  local p_ok, p_data = pcall(vim.json.decode, p_json)
  if not p_ok or not p_data.packages then
    return packages_base .. '/**/bin/*gcc*'
  end

  print('toolchain 3.2')
  local arch_glob = '/**/bin/*gcc*'
  for pkg_name, _ in pairs(p_data.packages) do
    if type(pkg_name) == 'string' and pkg_name:find('^toolchain%-') then
      local arch = pkg_name:gsub('toolchain%-', ''):gsub('gcc%-?', '')
      arch_glob = '/**/bin/*' .. arch .. '*gcc*'
      print('toolchain 3.3: arch_glob=' .. arch_glob)
      break
    end
  end

  local final_pattern = (packages_base .. arch_glob):gsub('//+', '/')
  if vim.fn.has('win32') == 1 then
    final_pattern = final_pattern:gsub('/', '\\')
    print('toolchain 3.3: final_pattern=' .. final_pattern)
  end

  _G._pio_cache = _G._pio_cache or {}
  _G._pio_cache[cache_key] = final_pattern
  return final_pattern
end
-- function _G.get_pio_toolchain_pattern()
--   local cwd = vim.fn.getcwd()
--
--   -- 1. Performance: Check Session Cache
--   local cache_key = cwd .. (vim.g.pio_active_env or 'auto')
--   if _G._pio_cache and _G._pio_cache[cache_key] then return _G._pio_cache[cache_key] end
--   print("toolchain 1:")
--
--   -- 2. Get Full Project Config via JSON
--   local handle = io.popen('pio project config --json-output')
--   if not handle then return '/**/bin/*gcc*' end
--   local json_str = handle:read('*all')
--   handle:close()
--   print("toolchain 2:")
--
--   local ok, config = pcall(vim.json.decode, json_str)
--   if not ok or not config then return '/**/bin/*gcc*' end
--
--   -- 3. Determine Active Environment (Priority: Manual > default_envs > First [env:])
--   local active_env = vim.g.pio_active_env
--   print("toolchain 3:")
--
--   if not active_env then
--     -- A. Check if default_envs is defined in [platformio]
--     if config.platformio and config.platformio.default_envs then
--       -- Handles comma-separated lists like "env1, env2"
--       active_env = tostring(config.platformio.default_envs):match('([^,%s]+)')
--     end
--     print("toolchain 3.0:")
--
--     -- B. Fallback: Find the first environment name starting with "env:"
--     if not active_env then
--       print(vim.inspect(config))
--       for name, value in pairs(config) do
--         print("toolchain 3.0: name=" .. name .. ' value=' .. value)
--         -- FIX: Check type to prevent "attempt to index local 'name' (a number value)"
--         if type(name) == 'string' then
--           local env_match = name:match('^env:(.+)')
--           print("toolchain 3.0: env_match=" .. env_match)
--           if env_match then active_env = env_match break
--           end
--         end
--       end
--     end
--   end
--
--   -- 4. Target the specific config block
--   -- PIO JSON uses "env:NAME" keys for environments
--   local env_key = 'env:' .. (active_env or '')
--   local env_data = config[env_key] or config[active_env]
--   print("toolchain 4:")
--
--   if not env_data or not env_data.platform then return '/**/bin/*gcc*' end
--
--   print("toolchain 5:")
--   -- 5. Build Paths (Normalizing for Windows/Linux)
--   local home = os.getenv('HOME') or os.getenv('USERPROFILE')
--   local core_dir = (config.platformio and config.platformio.core_dir) or (home .. '/.platformio')
--   local packages_base = core_dir:gsub('\\', '/') .. '/packages'
--
--   -- 6. Query PIO for the Toolchain Architecture
--   local p_handle = io.popen('pio platform show ' .. env_data.platform .. ' --json-output')
--   if not p_handle then return packages_base .. '/**/bin/*gcc*' end
--   local p_json = p_handle:read('*all')
--   p_handle:close()
--   print("toolchain 6:")
--
--   local p_ok, p_data = pcall(vim.json.decode, p_json)
--   if not p_ok or not p_data.packages then return packages_base .. '/**/bin/*gcc*' end
--   print("toolchain 6.0:")
--
--   local arch_glob = '/**/bin/*gcc*'
--   for pkg_name, _ in pairs(p_data.packages) do
--     if type(pkg_name) == 'string' and pkg_name:find('^toolchain%-') then
--       print("toolchain 6.1: pkg_name=" .. pkg_name)
--       local arch = pkg_name:gsub('toolchain%-', ''):gsub('gcc%-?', '')
--       arch_glob = '/**/bin/*' .. arch .. '*gcc*'
--       break
--     end
--   end
--
--   -- 7. Final Path Normalization
--   local final_pattern = (packages_base .. arch_glob):gsub('//+', '/')
--   if vim.fn.has('win32') == 1 then final_pattern = final_pattern:gsub('/', '\\') end
--   print("toolchain 6.1: final_pattern=" .. final_pattern)
--
--   -- Save to cache
--   _G._pio_cache = _G._pio_cache or {}
--   _G._pio_cache[cache_key] = final_pattern
--   return final_pattern
-- end
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
