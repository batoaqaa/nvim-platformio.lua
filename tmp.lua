-- local meta = _G.metadata
-- INFO: get project metadata
-- local function get_metadata(attempts, env)
--   local active_env = env or meta.active_env
--   vim.system({ 'pio', 'project', 'metadata', '-e', active_env, '--json-output' }, { text = true }, function(int_obj)
--     vim.schedule(function()
--       vim.notify('PIO: Fetching metadata ...', vim.log.levels.INFO)
--       --
--       if int_obj.code ~= 0 then
--         -- Schedule notification to avoid error in the system callback thread
--         vim.schedule(function()
--           if int_obj.code == 127 then
--             vim.notify("PIO Manager metadata: 'pio' command not found. Ensure PlatformIO Core is installed.", vim.log.levels.ERROR)
--           else
--             vim.notify('PIO Manager metadata: Failed to fetch metadata(' .. int_obj.stderr or 'Unknown Error' .. ')', vim.log.levels.WARN)
--           end
--         end)
--         return
--       end
--       --
--       if int_obj.code == 0 and int_obj.stdout then
--         local ok, raw_data = pcall(vim.json.decode, int_obj.stdout)
--         if ok and raw_data then
--           local _, data = next(raw_data)
--           if data then
--             -- 1. Process cc_compiler
--             if data.cc_path then
--               meta.query_driver = ''
--               meta.includes_build = {}
--               meta.includes_comaptlib = {}
--               meta.includes_toolchain = {}
--               meta.cc_flags = {}
--               meta.cxx_path = ''
--               meta.cxx_flags = {}
--               meta.gdb_path = ''
--               meta.defines = {}
--               meta.triplet = ''
--               meta.toolchain_root = ''
--               meta.sysroot = ''
--               meta.cc_compiler = misc.normalizePath(data.cc_path) or ''
--               meta.cc_path = misc.normalizePath(data.cc_path) or ''
--               --
--               -- 2. Process cc_flags
--               if data.cc_flags then
--                 local cc_flags = {}
--                 for _, flag in ipairs(data.cc_flags) do
--                   table.insert(cc_flags, string.format('%q', flag))
--                 end
--                 meta.cc_flags = cc_flags
--               end
--               --
--               -- 3. Process cxx_compiler
--               if data.cxx_path then
--                 meta.cxx_path = misc.normalizePath(data.cxx_path) or ''
--               end
--               --
--               -- 4. Process cxx_flags
--               if data.cxx_flags then
--                 local cxx_flags = {}
--                 for _, flag in ipairs(data.cxx_flags) do
--                   table.insert(cxx_flags, string.format('%q', flag))
--                 end
--                 meta.cxx_flags = cxx_flags
--               end
--               --
--               -- 5. Process gdb_path
--               if data.gdb_path then
--                 meta.gdb_path = misc.normalizePath(data.gdb_path) or ''
--               end
--               --
--               -- 6. Process Defines
--               if data.defines then
--                 local defines = {}
--                 for _, define in ipairs(data.defines) do
--                   table.insert(defines, string.format('%q', define))
--                 end
--                 meta.defines = defines
--               end
--               --
--               -- 7. Process Includes
--               if data.includes then
--                 for category, paths in pairs(data.includes) do
--                   -- 7.1 Process Includes_build
--                   if category == 'build' then
--                     local includes_build = {}
--                     local flag = '-I'
--                     for _, path in ipairs(paths) do
--                       table.insert(includes_build, string.format('%q', flag .. misc.normalizePath(path)))
--                     end
--                     meta.includes_build = includes_build
--                   end
--                   --
--                   -- 7.2 Process includes_toolchain
--                   if category == 'toolchain' then
--                     local includes_toolchain = {}
--                     local flag = '-isystem'
--                     for _, path in ipairs(paths) do
--                       table.insert(includes_toolchain, string.format('%q', flag .. misc.normalizePath(path)))
--                     end
--                     meta.includes_toolchain = includes_toolchain
--                   end
--                   --
--                   -- 7.3 Process includes_compatlib
--                   if category == 'compatlib' then
--                     local includes_compatlib = {}
--                     local flag = '-isystem'
--                     for _, path in ipairs(paths) do
--                       table.insert(includes_compatlib, string.format('%q', flag .. misc.normalizePath(path)))
--                     end
--                     meta.includes_build = includes_compatlib
--                   end
--                 end
--               end
--               --
--               pcall(M.get_sysroot_triplet, meta.cc_compiler)
--             end
--           end
--         else
--           vim.schedule(function()
--             vim.notify('PIO: Syncing Environment failed', vim.log.levels.WARN)
--           end)
--         end
--       end
--       -- RETRY LOGIC: Handles "Error 1" (file busy) or temporary syntax errors during save
--       if attempts > 0 then
--         vim.defer_fn(function()
--           get_metadata(attempts - 1)
--         end, 500)
--       else
--         if callback then
--           vim.schedule(function()
--             vim.notify('PIO: Fetching metadata successful', vim.log.levels.INFO)
--             callback()
--           end)
--         end
--       end
--     end)
--   end)
-- end

local function fetch_config() -- INFO: Setup Base Paths
  local meta = _G.metadata
  local home = os.getenv('HOME') or os.getenv('USERPROFILE')
  --
  -- The format is typically: { { "section_name", { {"key", "value"}, ... } }, ... }
  vim.system({ 'pio', 'project', 'config', '--json-output' }, { text = true }, function(ext_obj)
    vim.schedule(function()
      if ext_obj.code ~= 0 then
        -- Schedule notification to avoid error in the system callback thread
        if ext_obj.code == 127 then
          vim.notify("PIO Manager config: 'pio' command not found. Ensure PlatformIO Core is installed.", vim.log.levels.ERROR)
        else
          vim.notify('PIO Manager config: Failed to fetch config (' .. ext_obj.stderr or 'Unknown Error' .. ')', vim.log.levels.WARN)
        end
        return
      end

      meta.core_dir = ''
      meta.packages_dir = ''
      meta.platforms_dir = ''
      meta.active_env = ''
      meta.default_envs = {}
      meta.envs = {}

      local decoded = vim.json.decode(ext_obj.stdout)
      for _, section in ipairs(decoded) do
        if type(section) == 'table' and #section >= 2 then
          local name, data = section[1], section[2]
          -- 1. Extract Global PlatformIO Settings if available [core_dir][packages_dir][platforms_dir][default_envs]
          if name == 'platformio' then
            for _, kv in ipairs(data) do
              local key, val = kv[1], kv[2]
              if key ~= nil then
                -- if meta[key] ~= nil then
                meta[key] = ((type(val) == 'table' and next(val) ~= nil) or (type(val) == 'string' and val ~= '')) and misc.normalizePath(val) or val
              end
            end
            -- 2. Extract all hardware [envs] like [env:seeed_xiao_esp32c3], skipping generic [env]
          elseif name:match('^env:') then
            local env_name = name:match('^env:(.+)')
            meta.envs[env_name] = {}
            for _, kv in ipairs(data) do
              meta.envs[env_name][kv[1]] = kv[2]
            end
          end
        end
      end
      -- assign [active_env]
      if #meta.default_envs > 0 then
        meta.active_env = meta.default_envs[1] or ''
      elseif meta.envs and next(meta.envs) ~= '' then
        meta.active_env = next(meta.envs) or ''
      end

      -- INFO: -- Define Mapping (key in INI, Env Var, Default Subfolder)
      local map = {
        core = { ini = 'core_dir', env = 'PLATFORMIO_CORE_DIR', sub = '/.platformio' },
        packages = { ini = 'packages_dir', env = 'PLATFORMIO_PACKAGES_DIR', sub = '/.platformio/packages' },
        platforms = { ini = 'platforms_dir', env = 'PLATFORMIO_PLATFORMS_DIR', sub = '/.platformio/platforms' },
      }
      for _, kv in ipairs(map) do
        -- 4.0 Fallback Logic: INI -> Env Var -> Default
        local result = meta[kv.ini] or os.getenv(kv.env or (home .. kv.sub)):gsub('[\\/]+$', '')
        -- 5. Expand ${platformio.core_dir}
        if type(result) == 'string' then
          if result:find('${platformio.core_dir}', 1, true) then
            result = result:gsub('%${platformio.core_dir}', meta.core_dir)
          end
        end
        -- 6. Normalize Slashes for Windows
        -- meta[kv.ini] = misc.normalize_path(result) --core_dir:gsub('\\', '/'):gsub('//+', '/')
        -- meta[kv.ini] = result:gsub('\\', '/'):gsub('//+', '/')
        meta[kv.ini] = misc.normalizePath(result)
      end
      -- return meta[map[type].ini]
      -- end

      if meta.active_env ~= '' then
        vim.schedule(function()
          vim.notify('PIO: Fetching config successful', vim.log.levels.INFO)
        end)
        get_metadata(1, meta.active_env)
      else
        vim.schedule(function()
          vim.notify('PIO: no [env:] found, add board first', vim.log.levels.ERROR)
        end)
      end
    end)
  end)
end

local function get_metadata(attempts, env)
  vim.notify('PIO: Fetching metadata...', vim.log.levels.INFO)
  --"C:\Users\batoaqaa\AppData\Local\ahmed\test\.pio\build\seeed_xiao_esp32c3\idedata.json"
  local active_env = env or _G.metadata.active_env
  local filename = vim.uv.cwd() .. '/.pio/build/' .. active_env .. '/idedata.json'
  local content = vim.misc.readFile(filename)
  if content then
    -- 2. JSON Decoding
    local ok, data = pcall(vim.json.decode, content or '')
    if not ok or not data then
      vim.notify('PIO: Failed to parse metadata JSON', vim.log.levels.WARN)
      return
    end

    -- 3. Update Global Metadata (Resetting with defaults)
    local meta = _G.metadata
    local norm = function(p)
      return misc.normalizePath(p) or ''
    end
    local quote_map = function(list, prefix)
      local res = {}
      for _, v in ipairs(list or {}) do
        table.insert(res, string.format('%q', (prefix or '') .. (prefix and norm(v) or v)))
      end
      return res
    end

    -- Overwrite/Refresh Meta safely
    meta.cc_path = norm(data.cc_path)
    meta.cc_compiler = meta.cc_path
    meta.cxx_path = norm(data.cxx_path)
    meta.gdb_path = norm(data.gdb_path)

    meta.cc_flags = quote_map(data.cc_flags)
    meta.cxx_flags = quote_map(data.cxx_flags)
    meta.defines = quote_map(data.defines)

    -- 4. Process Includes
    local inc = data.includes or {}
    meta.includes_build = quote_map(inc.build, '-I')
    meta.includes_toolchain = quote_map(inc.toolchain, '-isystem')
    meta.includes_compatlib = quote_map(inc.compatlib, '-isystem')

    -- 5. Finalize
    pcall(M.get_sysroot_triplet, meta.cc_compiler)

    if callback then
      vim.notify('PIO: Metadata sync successful', vim.log.levels.INFO)
      callback()
    end
  else
    vim.system({ 'pio', 'project', 'metadata', '-e', active_env, '--json-output' }, { text = true }, function(obj)
      vim.schedule(function()
        -- 1. Error Handling
        if obj.code ~= 0 then
          local msg = obj.code == 127 and "'pio' not found" or (obj.stderr or 'Unknown Error')
          vim.notify('PIO Metadata Error: ' .. msg, vim.log.levels.WARN)

          -- Retry Logic
          if attempts > 0 then
            vim.defer_fn(function()
              get_metadata(attempts - 1, env)
            end, 500)
          end
          return
        end

        -- 2. JSON Decoding
        local ok, raw_data = pcall(vim.json.decode, obj.stdout or '')
        local _, data = next(raw_data or {})

        if not ok or not data then
          vim.notify('PIO: Failed to parse metadata JSON', vim.log.levels.WARN)
          return
        end

        -- 3. Update Global Metadata (Resetting with defaults)
        local meta = _G.metadata
        local norm = function(p)
          return misc.normalizePath(p) or ''
        end
        local quote_map = function(list, prefix)
          local res = {}
          for _, v in ipairs(list or {}) do
            table.insert(res, string.format('%q', (prefix or '') .. (prefix and norm(v) or v)))
          end
          return res
        end

        -- Overwrite/Refresh Meta safely
        meta.cc_path = norm(data.cc_path)
        meta.cc_compiler = meta.cc_path
        meta.cxx_path = norm(data.cxx_path)
        meta.gdb_path = norm(data.gdb_path)

        meta.cc_flags = quote_map(data.cc_flags)
        meta.cxx_flags = quote_map(data.cxx_flags)
        meta.defines = quote_map(data.defines)

        -- 4. Process Includes
        local inc = data.includes or {}
        meta.includes_build = quote_map(inc.build, '-I')
        meta.includes_toolchain = quote_map(inc.toolchain, '-isystem')
        meta.includes_compatlib = quote_map(inc.compatlib, '-isystem')

        -- 5. Finalize
        pcall(M.get_sysroot_triplet, meta.cc_compiler)

        if callback then
          vim.notify('PIO: Metadata sync successful', vim.log.levels.INFO)
          callback()
        end
      end)
    end)
  end
end
