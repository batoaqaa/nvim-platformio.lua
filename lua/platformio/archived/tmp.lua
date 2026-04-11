M = {}
function M.get_pio_dir(type)
  -- 1. Setup Base Paths
  local home = os.getenv('HOME') or os.getenv('USERPROFILE')

  -- 2. Define Mapping (key in INI, Env Var, Default Subfolder)
  local map = {
    core = { ini = 'core_dir', env = 'PLATFORMIO_CORE_DIR', sub = '/.platformio' },
    packages = { ini = 'packages_dir', env = 'PLATFORMIO_PACKAGES_DIR', sub = '/packages' },
    platforms = { ini = 'platforms_dir', env = 'PLATFORMIO_PLATFORMS_DIR', sub = '/platforms' },
  }

  local core_ini, packages_ini, platforms_ini = nil, nil, nil
  local core_map, packages_map, platforms_map = map['core'], map['packages'], map['platforms']
  if not core_map and not packages_map and not platforms_map then
    return nil
  end

  -- 3. Try to get explicit value from platformio.ini
  -----------------------------------------------------
  local handle = io.popen('pio project config --json-output')
  if handle then
    local json_str = handle:read('*all')
    local _, config = pcall(vim.json.decode, json_str)
    for _, section in ipairs(config) do
      if section[1] == 'platformio' then
        for _, kv in ipairs(section[2]) do
          if kv[1] == platforms_map.ini then
            platforms_ini = tostring(kv[2]):match('([^,%s]+)')
          end
          if kv[1] == packages_map then
            packages_ini = tostring(kv[2]):match('([^,%s]+)')
          end
          if kv[1] == core_map then
            core_ini = kv[2]
          end
        end
      end
    end
    handle:close()
  end

  -- 4.0 Fallback Logic: INI -> Env Var -> Default
  -----------------------------------------------------
  local core_dir = core_ini or os.getenv('PLATFORMIO_CORE_DIR' or (home .. map['core'].sub)):gsub('[\\/]+$', '')
  core_dir = misc.normalize_path(core_dir) --core_dir:gsub('\\', '/'):gsub('//+', '/')

  if type == 'core' then
    return core_dir
  end

  local result
  if type == 'packages' then
    result = packages_ini or os.getenv(packages_map.env) or (core_dir .. packages_map.sub)
  end
  if type == 'platforms' then
    result = platforms_ini or os.getenv(platforms_map.env) or (core_dir .. platforms_map.sub)
  end

  -- 5. Expand ${platformio.core_dir}
  if result:find('${platformio.core_dir}', 1, true) then
    result = result:gsub('%${platformio.core_dir}', core_dir)
  end

  -- 6. Normalize Slashes for Windows
  result = misc.normalize_path(result) --result:gsub('\\', '/'):gsub('//+', '/')
  -- if vim.fn.has('win32') == 1 then result = result:gsub('/', '\\') end

  -- Ensure core_dir itself doesn't have trailing slashes for cleaner joins
  return result
end

return M
