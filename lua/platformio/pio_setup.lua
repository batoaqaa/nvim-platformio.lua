M = {}

_G.metadata = {
  envs = {},
  default_envs = {},
  core_dir = '',
  packages_dir = '',
  platforms_dir = '',
  active_env = '',
  driver_path = '',
  cc_path = '',
  fallback_flags = {},
}

local misc = require('platformio.utils.misc')
local lsp = require('platformio.utils.lsp')
local boilerplate_gen = require('platformio.boilerplate').boilerplate_gen

-- lua/pio_setup.lua
-- This module manages PlatformIO project integration, LSP toolchain detection,
-- and automatic sysroot patching for standard library headers (<algorithm>, etc.)

local debounce_timer = vim.uv.new_timer()

-- INFO:
-- DATABASE PATCHER: Generates compile_commands.json and injects the --sysroot flag
-- stylua: ignore
local function pio_generate_db()
  vim.schedule(function() vim.notify('PIO: Generating Compile Database...', vim.log.levels.INFO) end)
  vim.system({ 'pio', 'run', '-t', 'compiledb' }, { text = true }, function(obj)
    if obj.code ~= 0 then
      vim.schedule(function() vim.notify('PIO: Generating Compile Database failed', vim.log.levels.INFO) end)
      return
    end
    vim.schedule(function() vim.notify('PIO: Generating Compile Database successful', vim.log.levels.INFO) end)
  end)
end

-- INFO:
-- stylua: ignore
local function GetActivePioEnv()
  local file = io.open('platformio.ini', 'r')
  if not file then
    _G.metadata.active_env = ''
    return nil
  end

  local result_env = nil
  for line in file:lines() do
    -- 1. Try to find the explicit default_envs first
    local default = line:match('^default_envs%s*=%s*(%S+)')
    if default then
      result_env= default
    -- 2. Capture the first [env:NAME] we see as a fallback
    elseif not result_env then
      result_env = line:match('^%[env:(%S+)%]')
    end
  end
  file:close()
  print(result_env)
  -- Return the first env found if no default was explicitly set
  return result_env
end

-- INFO: 1. The Core PIO Manager & Generic Extractor
--- stylua: ignore
local pio_manager = (function()
  local cache = nil -- Stores the decoded platformio.ini JSON structure
  -- INFO:
  local function find_in_data(data, section_name, key_name)
    -- Safety check: Ensure data is a valid table from a successful JSON decode
    if type(data) ~= 'table' then
      return nil
    end

    for _, section in ipairs(data) do
      -- Each section must be a table with at least 2 elements: [1]=name, [2]=content
      if type(section) == 'table' and #section >= 2 then
        local s_id = section[1] -- Section header string
        local s_body = section[2] -- Table of key-value pairs

        if s_id == section_name and type(s_body) == 'table' then
          for _, kv in ipairs(s_body) do
            -- Each kv is a table: [1]=key, [2]=value
            if type(kv) == 'table' and #kv >= 2 and kv[1] == key_name then
              local val = kv[2]
              -- Treat empty strings or empty tables as nil to trigger fallback logic
              if val == nil or val == '' or (type(val) == 'table' and #val == 0) then
                return nil
              end
              return val
            end
          end
        end
      end
    end
    return nil
  end

  -- INFO: ASYNC REFRESH: Fetches the latest config from PlatformIO CLI
  --- stylua: ignore
  local function refresh(callback)
    vim.schedule(function()
      vim.notify('PIO: Fetching Config...', vim.log.levels.INFO)
    end)

    -- INFO: get metadata
    local function get_metadata(attempts)
      -- INFO: internal: pio project metadata
      -- vim.system({ 'pio', 'project', 'metadata', '-e', _G.metadata.active_env, '--json-output' }, { text = true }, function(int_obj)
      vim.schedule(function()
        print('active_env metadata: ' .. _G.metadata.active_env)
      end)
      if not _G.metadata.active_env or _G.metadata.active_env == '' then
        vim.schedule(function()
          vim.notify('PIO: no env: found, add board first', vim.log.levels.ERROR)
        end)
        return
      end
      vim.system({ 'pio', 'project', 'metadata', '-e', 'seeed_xiao_esp32c3', '--json-output' }, { text = true }, function(int_obj)
        if int_obj.code ~= 0 then
          -- Schedule notification to avoid error in the system callback thread
          vim.schedule(function()
            if int_obj.code == 127 then
              vim.notify("PIO Manager: 'pio' command not found. Ensure PlatformIO Core is installed.", vim.log.levels.ERROR)
            else
              vim.notify('PIO Manager: Failed to fetch metadata(' .. int_obj.stderr or 'Unknown Error' .. ')', vim.log.levels.WARN)
            end
          end)
          return
        end
        -- Error Checking: int_obj.code 0 means success
        if int_obj.code == 0 and int_obj.stdout then
          local ok, raw_data = pcall(vim.json.decode, int_obj.stdout)
          if ok and raw_data then
            local _, env = next(raw_data)
            if not env then
              return
            end
            local fallback_flags = {}
            -- 1. Process Includes
            -- if env.includes then
            --   for category, paths in pairs(env.includes) do
            --     -- If it's a toolchain path, use -isystem to suppress warnings
            --     -- and tell clangd these are standard libraries
            --     local flag = (category == 'toolchain') and '-isystem' or '-I'
            --     for _, path in ipairs(paths) do
            --       table.insert(fallback_flags, flag .. path)
            --     end
            --   end
            -- end
            -- 2. Process Defines
            -- if env.defines then
            --   for _, define in ipairs(env.defines) do
            --     table.insert(fallback_flags, '-D' .. define)
            --   end
            -- end

            _G.metadata.driver_path = misc.normalize_path(env.cc_path:match('(.*[/\\])') .. '*') or '**'
            _G.metadata.cc_path = misc.normalize_path(env.cc_path) or ''
            _G.metadata.fallback_flags = fallback_flags

            print(vim.inspect(_G.metadata))
            if callback then
              vim.schedule(function()
                vim.notify('PIO: Syncing Environment successful', vim.log.levels.INFO)
                callback()
              end)
            end
          else
            vim.schedule(function()
              vim.notify('PIO: Syncing Environment failed', vim.log.levels.WARN)
            end)
          end
        end
        -- RETRY LOGIC: Handles "Error 1" (file busy) or temporary syntax errors during save
        if attempts > 0 then
          vim.defer_fn(function()
            get_metadata(attempts - 1)
          end, 500)
        else
          vim.schedule(function()
            if int_obj.code ~= 0 then
              vim.notify('PIO: Config Error. Check platformio.ini syntax.', vim.log.levels.WARN)
            end
          end)
        end
      end)
    end

    -- INFO: -- 1. Setup Base Paths
    local home = os.getenv('HOME') or os.getenv('USERPROFILE')
    -- INFO: -- 2. Define Mapping (key in INI, Env Var, Default Subfolder)
    local map = {
      core = { ini = 'core_dir', env = 'PLATFORMIO_CORE_DIR', sub = '/.platformio' },
      packages = { ini = 'packages_dir', env = 'PLATFORMIO_PACKAGES_DIR', sub = '/.platformio/packages' },
      platforms = { ini = 'platforms_dir', env = 'PLATFORMIO_PLATFORMS_DIR', sub = '/.platformio/platforms' },
    }

    -- INFO: 3. Try to get explicit value from platformio.ini
    -- HELPER: Navigates the specific nested list format used by 'pio project config --json-output'
    -- The format is typically: { { "section_name", { {"key", "value"}, ... } }, ... }
    vim.system({ 'pio', 'project', 'config', '--json-output' }, { text = true }, function(ext_obj)
      if ext_obj.code ~= 0 then
        -- Schedule notification to avoid error in the system callback thread
        vim.schedule(function()
          if ext_obj.code == 127 then
            vim.notify("PIO Manager: 'pio' command not found. Ensure PlatformIO Core is installed.", vim.log.levels.ERROR)
          else
            vim.notify('PIO Manager: Failed to fetch config (' .. ext_obj.stderr or 'Unknown Error' .. ')', vim.log.levels.WARN)
          end
        end)
        return
      end
      _G.metadata.core_dir = ''
      _G.metadata.packages_dir = ''
      _G.metadata.platforms_dir = ''
      _G.metadata.active_env = ''
      _G.metadata.default_envs = {}
      _G.metadata.envs = {}

      local decoded = vim.json.decode(ext_obj.stdout)
      for _, section in ipairs(decoded) do
        if type(section) == 'table' and #section >= 2 then
          local name, data = section[1], section[2]
          -- 1. Extract Global PlatformIO Settings
          if name == 'platformio' then
            for _, kv in ipairs(data) do
              local key, val = kv[1], kv[2]
              if key ~= nil then
                -- if _G.metadata[key] ~= nil then
                _G.metadata[key] = val
              end
            end
            -- 2. Extract all hardware envs like [env:seeed_xiao_esp32c3], skipping generic [env]
          elseif name:match('^env:') then
            local env_name = name:match('^env:(.+)')
            _G.metadata.envs[env_name] = {}
            for _, kv in ipairs(data) do
              _G.metadata.envs[env_name][kv[1]] = kv[2]
            end
          end
        end
      end
      if #_G.metadata.default_envs > 0 then
        _G.metadata.active_env = _G.metadata.default_envs[1] or ''
      else
        _G.metadata.active_env = next(_G.metadata.envs) or ''
      end

      for _, kv in ipairs(map) do
        -- 4.0 Fallback Logic: INI -> Env Var -> Default
        local result = _G.metadata[kv.ini] or os.getenv(kv.env or (home .. kv.sub)):gsub('[\\/]+$', '')
        -- 5. Expand ${platformio.core_dir}
        if type(result) == 'string' then
          if result:find('${platformio.core_dir}', 1, true) then
            result = result:gsub('%${platformio.core_dir}', _G.metadata.core_dir)
          end
        end
        -- 6. Normalize Slashes for Windows
        -- _G.metadata[kv.ini] = misc.normalize_path(result) --core_dir:gsub('\\', '/'):gsub('//+', '/')
        _G.metadata[kv.ini] = result:gsub('\\', '/'):gsub('//+', '/')
      end
      -- return _G.metadata[map[type].ini]
      -- end

      if _G.metadata.active_env ~= '' then
        vim.schedule(function()
          print('active_env config: ' .. _G.metadata.active_env)
        end)
        get_metadata(1)
      end
    end)
  end

  -- INFO:
  return {
    refresh = refresh,
    -- INFO:
    get = function(s, k)
      if not cache then
        return nil
      end
      local res = find_in_data(cache, s, k)

      -- FALLBACK: If default_envs is missing/empty, find the first hardware [env:xxx] block
      if k == 'default_envs' and not res then
        for _, section in ipairs(cache) do
          if type(section) == 'table' and type(section[1]) == 'string' then
            local name = section[1]
            if name:find('^env:') then
              local fallback = name:match('^env:(.+)')
              if fallback then
                vim.schedule(function()
                  vim.notify('PIO: default_envs empty. Using: ' .. fallback, vim.log.levels.INFO)
                end)
                return fallback
              end
            end
          end
        end
        vim.schedule(function()
          vim.notify('PIO: Config Error. Check platformio.ini no env', vim.log.levels.WARN)
        end)
      elseif k == 'default_envs' and res and type(res) == 'table' then
        return res[1]
      else
        return res
      end
    end,
  }
end)()

-- INFO:
function _G.get_pio_sdk_info()
  local pio_info = { includes = {}, cc_path = '' }
  if vim.fn.filereadable('platformio.ini') == 0 then
    return nil
  end

  local handle = io.popen('pio run -t envdump')
  if not handle then
    return nil
  end

  local packages_dir, cc_name, toolchain_pkg = '', '', ''

  for line in handle:lines() do
    -- 1. Get the global packages directory
    packages_dir = packages_dir ~= '' and packages_dir or line:match("'PROJECT_PACKAGES_DIR': '([^']+)'")

    -- 2. Get the compiler executable name (e.g., riscv32-esp-elf-gcc)
    cc_name = cc_name ~= '' and cc_name or line:match("'CC': '([^']+)'")

    -- 3. Find the specific toolchain package name from the PACKAGES list
    -- Matches lines like "- toolchain-riscv32-esp @ 14.2.0"
    local pkg = line:match('%- (toolchain%-[^ ]+)')
    if pkg then
      toolchain_pkg = pkg
    end

    -- 4. Collect include paths
    local path_list = line:match("'CPPPATH': %[(.+)%]")
    if path_list then
      for path in path_list:gmatch("'([^']+)'") do
        table.insert(pio_info.includes, '-I' .. path)
      end
    end
  end
  handle:close()

  -- Construct the absolute path: <packages_dir>/<toolchain_pkg>/bin/<cc_name>
  if packages_dir and packages_dir ~= '' and toolchain_pkg and toolchain_pkg ~= '' and cc_name ~= '' then
    local full_path = packages_dir .. '/' .. toolchain_pkg .. '/bin/' .. cc_name
    if vim.fn.executable(full_path) == 1 then
      pio_info.cc_path = full_path
    end
  end

  local final = packages_dir .. '/' .. toolchain_pkg .. '/bin/*'
  print('get_pio_sdk_info(): final=' .. final)
  -- Normalize paths for the OS and ensure backslashes for Windows if needed
  print(vim.inspect(_G.metadata))
  return (misc.normalize_path(final))
  -- return _G.metadata.driver_path
  -- return pio_info
end

-- INFO:
-- LSP HELPER: Returns the glob pattern for clangd's --query-driver
-- e.g., C:\Users\tom\.platformio\packages\toolchain-riscv32-esp\bin\*
function _G.get_pio_toolchain_pattern()
  return _G.metadata.driver_path
end

-- INFO:
-- FILE WATCHER: Listens for changes in platformio.ini to trigger auto-sync
-- stylua: ignore
local function start_pio_watcher()
  local dir_path = vim.uv.cwd()
  if not dir_path then return end

  -- Create a directory watcher
  local w = vim.uv.new_fs_event()
  if not w then
    return
  end

  -- Watch the directory for platformio.ini creation or changes
  w:start(
    dir_path,
    {},
    vim.schedule_wrap(function(err, filename, events)
      if err or not events or not events.change then
        return
      end
      -- Trigger only if the changed file is platformio.ini
      if filename == 'platformio.ini' and (events.change or events.rename) then
      if debounce_timer then
        debounce_timer:stop()
        debounce_timer:start(
          500,
          0,
          vim.schedule_wrap(function()
            -- _G.metadata.active_env = GetActivePioEnv()
            pio_manager.refresh(function()
              vim.schedule(function()
                boilerplate_gen([[.clangd_cmd]], vim.g.platformioRootDir)
                pio_generate_db()
                lsp.lsp_restart('clangd')
                -- vim.notify('PIO: Syncing Environment successful')
              end)
            end)
          end)
        )
      end
    end
    end)
  )
end
------------------------------------------------------------------------------------------------------
-- INFO: 6.  Exported setup function
function M.init()
  local config = require('platformio').config
  if config.lspClangd.enabled == true then
    vim.notify('PIO setup initialize', vim.log.levels.INFO)
    ----------------------------------------------------------------------------------------
    -- INFO: create clangd required files
    -----------------------------------------------------------------------------------------
    boilerplate_gen([[platformio.ini]], vim.g.platformioRootDir)
    boilerplate_gen([[.clangd]], vim.g.platformioRootDir)
    boilerplate_gen([[.clangd]], require('platformio.utils.pio').get_pio_dir('core')) --vim.env.PLATFORMIO_CORE_DIR)
    -- boilerplate_gen([[.clangd]], vim.fn.stdpath('data'))
    -- boilerplate_gen([[.clangd]], vim.env.XDG_CONFIG_HOME .. '/clangd', 'config.yaml')
    boilerplate_gen([[.clang-format]], vim.g.platformioRootDir)
    boilerplate_gen([[.stylua.toml]], vim.g.platformioRootDir)
    ---------------------------------------------------------------------------------

    require('platformio.lspConfig.clangd')
    if config.lspClangd.attach.enabled then
      require('platformio.lspConfig.attach')
    end

    start_pio_watcher()
    if vim.fn.filereadable(vim.uv.cwd() .. '/platformio.ini') == 1 then
      -- _G.metadata.active_env = GetActivePioEnv()
      pio_manager.refresh(function()
        vim.schedule(function()
          boilerplate_gen([[.clangd_cmd]], vim.g.platformioRootDir)
          pio_generate_db()
          lsp.lsp_restart('clangd')
          -- vim.notify('PIO: Syncing Environment successful')
        end)
      end)
    end
  end
end

return M
