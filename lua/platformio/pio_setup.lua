M = {}

local misc = require('platformio.utils.misc')
local lsp = require('platformio.lsp.tools')
local boilerplate_gen = require('platformio.boilerplate').boilerplate_gen

-- lua/pio_setup.lua
-- This module manages PlatformIO project integration, LSP toolchain detection,
-- and automatic sysroot patching for standard library headers (<algorithm>, etc.)

local debounce_timer = vim.uv.new_timer()

-- vim.notify('triplet= ' .. triplet, vim.log.levels.INFO)
-- -- INFO:
-- -- =============================================================================
-- -- UNIVERSAL TOOLCHAIN DETECTION
-- -- =============================================================================
-- --- stylua: ignore
-- local function get_sysroot_triplet(cc_compiler)
--   local bin_path = vim.fn.fnamemodify(cc_compiler, ':h')
--   -- Early exit if path is nil or not a directory
--   if not bin_path or vim.fn.isdirectory(bin_path) == 0 then
--     return nil
--   end
--
--   -- Normalize backslashes to forward slashes for cross-platform consistency
--   bin_path = bin_path:gsub('\\', '/')
--   local files = vim.fn.readdir(bin_path)
--   local triplet = nil
--
--   -- Loop through files to find the compiler and extract the triplet
--   for _, name in ipairs(files) do
--     -- Pattern: ^(.*) matches triplet, %- matches dash, g[c%+][c%+] matches gcc/g++
--     local match = name:match('^(.*)%-g[c%+][c%+]')
--     if match then
--       triplet = match
--       break
--     end
--   end
--
--   -- Return nil if no compiler was found in the bin directory
--   if not triplet then
--     return nil
--   end
--
--   -- toolchain_root is the parent of the 'bin' folder
--   local toolchain_root = vim.fn.fnamemodify(bin_path, ':h')
--   -- sysroot folder is expected to have the same name as the triplet
--   local sysroot = toolchain_root .. '/' .. triplet
--
--   -- vim.notify('triplet= ' .. triplet, vim.log.levels.INFO)
--   -- Only return data if the sysroot folder actually exists on disk
--   if vim.fn.isdirectory(sysroot) == 1 then
--     return {
--       triplet = triplet,
--       sysroot = sysroot,
--       toolchain_root = toolchain_root,
--       query_driver = bin_path .. '/' .. triplet .. '-*',
--     }
--   end
--   return nil
-- end
--

-- INFO:
-- DATABASE PATCHER: Generates compile_commands.json and injects the --sysroot flag
-- stylua: ignore
local function pio_generate_db()
  vim.schedule(function() vim.notify('PIO: Generating Compile Database...', vim.log.levels.INFO) end)
  vim.system({ 'pio', 'run', '-t', 'compiledb' }, { text = true }, function(obj)
    if obj.code ~= 0 then
      vim.schedule(function()
        if obj.code == 127 then
          vim.notify("PIO Manager db: 'pio' command not found. Ensure PlatformIO Core is installed.", vim.log.levels.ERROR)
        else
          vim.notify('PIO Manager db: Generating Compile Database failed (' .. obj.stderr or 'Unknown Error' .. ')', vim.log.levels.WARN)
        end
      end)
      return
    end
    vim.schedule(function() vim.notify('PIO: Generating Compile Database successful', vim.log.levels.INFO) end)
  end)
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
      if section and type(section) == 'table' and #section >= 2 then
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
      vim.notify('PIO: Fetching Config ...', vim.log.levels.INFO)
    end)

    -- INFO: get project metadata
    local function get_metadata(attempts, env)
      local active_env = env or _G.metadata.active_env
      vim.system({ 'pio', 'project', 'metadata', '-e', active_env, '--json-output' }, { text = true }, function(int_obj)
        vim.schedule(function()
          vim.notify('PIO: Fetching metadata ...', vim.log.levels.INFO)
        end)

        if int_obj.code ~= 0 then
          -- Schedule notification to avoid error in the system callback thread
          vim.schedule(function()
            if int_obj.code == 127 then
              vim.notify("PIO Manager metadata: 'pio' command not found. Ensure PlatformIO Core is installed.", vim.log.levels.ERROR)
            else
              vim.notify('PIO Manager metadata: Failed to fetch metadata(' .. int_obj.stderr or 'Unknown Error' .. ')', vim.log.levels.WARN)
            end
          end)
          return
        end

        if int_obj.code == 0 and int_obj.stdout then
          local ok, raw_data = pcall(vim.json.decode, int_obj.stdout)
          if ok and raw_data then
            local _, data = next(raw_data)
            if data then
              local fallbackFlags = {}
              -- 1. Process Includes
              if data.includes then
                for category, paths in pairs(data.includes) do
                  -- If it's a toolchain path, use -isystem to suppress warnings
                  -- and tell clangd these are standard libraries
                  if category == 'toolchain' then
                    local flag = '-isystem'
                    for _, path in ipairs(paths) do
                      -- table.insert(fallbackFlags, string.format('%q', flag))
                      -- table.insert(fallbackFlags, string.format('%q', path:gsub('\\', '/')))
                      table.insert(fallbackFlags, string.format('%q', flag .. path:gsub('\\', '/')))
                    end
                  end
                  -- local flag = (category == 'toolchain') and '-isystem' or '-I'
                  -- for _, path in ipairs(paths) do
                  --   table.insert(fallbackFlags, flag .. path)
                  -- end
                end
              end
              -- 2. Process Defines
              if data.defines then
                for _, define in ipairs(data.defines) do
                  table.insert(fallbackFlags, string.format('%q', '-D' .. define))
                end
              end

              -- get [cc_compiler]and [falbackFlags]
              -- _G.metadata.query_driver = misc.normalize_path(env.cc_compiler:match('(.*[/\\])') .. '*') or '**'
              _G.metadata.cc_compiler = misc.normalize_path(data.cc_path) or ''
              _G.metadata.fallbackFlags = fallbackFlags

              -- print(vim.inspect(_G.metadata))
              if callback then
                vim.schedule(function()
                  vim.notify('PIO: Fetching config successful', vim.log.levels.INFO)
                  callback()
                end)
              end
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
        end
      end)
    end

    -- INFO: Setup Base Paths
    local home = os.getenv('HOME') or os.getenv('USERPROFILE')

    -- INFO: Try to get explicit value from platformio.ini
    -- HELPER: Navigates the specific nested list format used by 'pio project config --json-output'
    -- The format is typically: { { "section_name", { {"key", "value"}, ... } }, ... }
    vim.system({ 'pio', 'project', 'config', '--json-output' }, { text = true }, function(ext_obj)
      if ext_obj.code ~= 0 then
        -- Schedule notification to avoid error in the system callback thread
        vim.schedule(function()
          if ext_obj.code == 127 then
            vim.notify("PIO Manager config: 'pio' command not found. Ensure PlatformIO Core is installed.", vim.log.levels.ERROR)
          else
            vim.notify('PIO Manager config: Failed to fetch config (' .. ext_obj.stderr or 'Unknown Error' .. ')', vim.log.levels.WARN)
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
          -- 1. Extract Global PlatformIO Settings if available [core_dir][packages_dir][platforms_dir][default_envs]
          if name == 'platformio' then
            for _, kv in ipairs(data) do
              local key, val = kv[1], kv[2]
              if key ~= nil then
                -- if _G.metadata[key] ~= nil then
                _G.metadata[key] = val
              end
            end
          -- 2. Extract all hardware [envs] like [env:seeed_xiao_esp32c3], skipping generic [env]
          elseif name:match('^env:') then
            local env_name = name:match('^env:(.+)')
            _G.metadata.envs[env_name] = {}
            for _, kv in ipairs(data) do
              _G.metadata.envs[env_name][kv[1]] = kv[2]
            end
          end
        end
      end
      -- assign [active_env]
      if #_G.metadata.default_envs > 0 then
        _G.metadata.active_env = _G.metadata.default_envs[1] or ''
      elseif _G.metadata.envs and next(_G.metadata.envs) ~= '' then
        _G.metadata.active_env = next(_G.metadata.envs) or ''
      end

      -- INFO: -- Define Mapping (key in INI, Env Var, Default Subfolder)
      local map = {
        core = { ini = 'core_dir', env = 'PLATFORMIO_CORE_DIR', sub = '/.platformio' },
        packages = { ini = 'packages_dir', env = 'PLATFORMIO_PACKAGES_DIR', sub = '/.platformio/packages' },
        platforms = { ini = 'platforms_dir', env = 'PLATFORMIO_PLATFORMS_DIR', sub = '/.platformio/platforms' },
      }
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
          vim.notify('PIO: Fetching metadata successful', vim.log.levels.INFO)
        end)
        get_metadata(1, _G.metadata.active_env)
      else
        vim.schedule(function()
          vim.notify('PIO: no [env:] found, add board first', vim.log.levels.ERROR)
        end)
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
  local pio_info = { includes = {}, cc_compiler = '' }
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
      pio_info.cc_compiler = full_path
    end
  end

  local final = packages_dir .. '/' .. toolchain_pkg .. '/bin/*'
  print('get_pio_sdk_info(): final=' .. final)
  -- Normalize paths for the OS and ensure backslashes for Windows if needed
  -- print(vim.inspect(_G.metadata))
  return (misc.normalize_path(final))
  -- return _G.metadata.query_driver
  -- return pio_info
end

-- INFO:
-- FILE WATCHER: Listens for changes in platformio.ini to trigger auto-sync
-- stylua: ignore
local function start_pio_watcher()
  local dir_path = vim.uv.cwd()
  if not dir_path then return end

  -- Create a directory watcher
  local handle = vim.uv.new_fs_event()
  if not handle then return end

  -- local last_trigger = 0
  -- Watch the directory for platformio.ini creation or changes
  handle:start(
    dir_path,
    {
      watch_entry = false, -- watch the file/dir itself
      stat = false,        -- use stat to detect changes (slower but more reliable on some FS)
      recursive = false,   -- watch subdirectories (if path is a directory)
    },
    vim.schedule_wrap(function(err, filename, events)
      if err or not events or not events.change then return end
      -- Trigger only if the changed file is platformio.ini
      if filename == 'platformio.ini' and (events.change or events.rename) then
        -- -- ignore events within time
        -- local current_time = vim.uv.now()
        -- -- IGNORE events if they happen within 100ms of the last one
        -- if current_time - last_trigger < 100 then
        --     return
        -- end
        -- last_trigger = current_time

        if debounce_timer then
          debounce_timer:stop()
          debounce_timer:start(
            500,
            0,
            vim.schedule_wrap(function()
              pio_manager.refresh(function()
                -- vim.schedule(function()
                -- local status, data = pcall(lsp.get_sysroot_triplet, _G.metadata.cc_compiler)
                -- if status and data and data.triplet and data.triplet ~= '' then
                --   _G.metadata.triplet = data.triplet
                --   _G.metadata.sysroot = data.sysroot
                --   _G.metadata.query_driver = data.query_driver
                --   _G.metadata.toolchain = data.toolchain_root
                -- end
                -- boilerplate_gen([[.clangd_init_options]], vim.g.platformioRootDir)
                boilerplate_gen([[.clangd]], vim.g.platformioRootDir)
                boilerplate_gen([[.clangd]], _G.metadata.core_dir) --require('platformio.utils.pio').get_pio_dir('core')) --vim.env.PLATFORMIO_CORE_DIR)

                pio_generate_db()
                lsp.lsp_restart('clangd')
                -- end)
  end) end)) end end end))
end
------------------------------------------------------------------------------------------------------
-- INFO: 6.  Exported setup function
function M.init()
  local config = require('platformio').config
  if config.lspClangd.enabled == true then
    vim.notify('PIO setup initialize', vim.log.levels.INFO)

    -- activate meta save and upload and env switch
    local metadata = require('platformio.metadata')
    metadata.load_project_config()

    local pio_group = vim.api.nvim_create_augroup('PioPersist', { clear = true })
    vim.api.nvim_create_autocmd({ 'BufWritePost', 'VimLeavePre' }, {
      group = pio_group,
      callback = function()
        -- Pass 'true' to save silently in the background
        metadata.save_project_config(true)
      end,
      desc = 'Automatically save PlatformIO project metadata',
    })
    -- 5. Keybindings
    -- Switch Environment
    vim.keymap.set('n', '<leader>\\e', metadata.switch_env, { desc = 'Switch environment' })
    -- Manual Status Check
    vim.keymap.set('n', '<leader>\\s', function()
      metadata.save_project_config(false)
    end, { desc = 'Config status' })

    ----------------------------------------------------------------------------------------
    -- INFO: create clangd required files
    -----------------------------------------------------------------------------------------
    boilerplate_gen([[platformio.ini]], vim.g.platformioRootDir)
    -- boilerplate_gen([[.clangd]], vim.g.platformioRootDir)
    -- boilerplate_gen([[.clangd]], require('platformio.utils.pio').get_pio_dir('core')) --vim.env.PLATFORMIO_CORE_DIR)
    -- boilerplate_gen([[.clangd]], vim.fn.stdpath('data'))
    -- boilerplate_gen([[.clangd]], vim.env.XDG_CONFIG_HOME .. '/clangd', 'config.yaml')
    boilerplate_gen([[.clang-format]], vim.g.platformioRootDir)
    boilerplate_gen([[.stylua.toml]], vim.g.platformioRootDir)
    ---------------------------------------------------------------------------------

    require('platformio.lsp.clangd')
    if config.lspClangd.attach.enabled then
      require('platformio.lsp.attach')
    end

    -- Always start the watcher so it can catch a future 'pio init'
    start_pio_watcher()

    -- If the file already exists, do an initial sync
    if vim.fn.filereadable(vim.uv.cwd() .. '/platformio.ini') == 1 then
      pio_manager.refresh(function()
        -- vim.schedule(function()
        -- boilerplate_gen([[.clangd_cmd]], vim.g.platformioRootDir)
        pio_generate_db()
        lsp.lsp_restart('clangd')
        -- end)
      end)
    end
  end
end

return M
