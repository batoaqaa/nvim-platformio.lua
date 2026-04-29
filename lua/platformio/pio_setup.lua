M = {}

-- local lsp_restart = require('platformio.lspConfig.tools').lsp_restart
local boilerplate = require('platformio.boilerplate')
local boilerplate_gen = boilerplate.boilerplate_gen

-- local debounce_timer = vim.uv.new_timer()
-- INFO:
-- =============================================================================
-- UNIVERSAL TOOLCHAIN DETECTION
-- =============================================================================
-- stylua: ignore
function M.get_sysroot_triplet(cc_compiler)
  local bin_path = vim.fn.fnamemodify(cc_compiler, ':h')

  -- Early exit if path is nil or not a directory
  if not bin_path or vim.fn.isdirectory(bin_path) == 0 then return nil end

  -- Normalize backslashes to forward slashes for cross-platform consistency
  bin_path = bin_path:gsub('\\', '/')
  local files = vim.fn.readdir(bin_path)
  local triplet = nil

  -- Loop through files to find the compiler and extract the triplet
  for _, name in ipairs(files) do
    -- Pattern: ^(.*) matches triplet, %- matches dash, g[c%+][c%+] matches gcc/g++
    local match = name:match('^(.*)%-g[c%+][c%+]')
    if match then triplet = vim.misc.normalizePath(match) break
    end
  end

  -- Return nil if no compiler was found in the bin directory
  if not triplet then return nil end

  -- toolchain_root is the parent of the 'bin' folder
  local toolchain_root = vim.misc.normalizePath(vim.fn.fnamemodify(bin_path, ':h'))
  -- sysroot folder is expected to have the same name as the triplet
  local sysroot = vim.misc.normalizePath(toolchain_root .. '/' .. triplet)
  local query_driver = vim.misc.normalizePath(bin_path .. '/' .. triplet .. '-*')

  -- vim.notify('triplet= ' .. triplet, vim.log.levels.INFO)
  -- Only return data if the sysroot folder actually exists on disk
  if vim.fn.isdirectory(sysroot) == 1 then
    _G.metadata.triplet = triplet
    _G.metadata.sysroot = sysroot
    _G.metadata.toolchain_root = toolchain_root
    _G.metadata.query_driver = query_driver
    return {
      triplet = triplet,
      sysroot = sysroot,
      toolchain_root = toolchain_root,
      query_driver = query_driver,
    }
  end
  return nil
end

-- stylua: ignore
function M.pio_refresh(callback)
  vim.notify('PIO: Config sync ...', vim.log.levels.INFO)

  -- INFO:-------------------------------------------------
  -- get pio project metadata info
  -- stylua: ignore
  local function fetch_metadata(attempts, env)
    local meta = _G.metadata
    local active_env = env or meta.active_env
    if not active_env or active_env == '' then
      return
    end

    -- Set up file paths
    local build_dir = vim.misc.joinPath(vim.uv.cwd(), '.pio', 'build')
    local build_env_dir = vim.misc.joinPath(build_dir, active_env)
    local checksum_file = vim.misc.joinPath(build_dir, 'project.checksum')
    local idedata_file = vim.misc.joinPath(build_env_dir, 'idedata.json')

    ---------------------------------------------------------
    -- INTERNAL PROCESSOR: Applies parsed data to _G.metadata
    local function apply_metadata(data, checksum)
      if not data then return false end

      local norm = function(p) return vim.misc.normalizePath(p) or '' end

      -- Helper for flags/defines to keep order and formatting
      local quote_map = function(list, prefix)
        local res = {}
        for _, v in ipairs(list or {}) do
          local val = prefix and (prefix .. norm(v)) or v
          table.insert(res, string.format('%s', val))
        end
        return res
      end

      -- 1. Base Paths & Compilers
      meta.cc_path = norm(data.cc_path)
      meta.cc_compiler = meta.cc_path
      meta.cxx_path = norm(data.cxx_path)
      meta.gdb_path = norm(data.gdb_path)

      -- 2. Flags & Defines
      meta.cc_flags = quote_map(data.cc_flags)
      meta.cxx_flags = quote_map(data.cxx_flags)
      meta.defines = quote_map(data.defines)

      -- 3. Includes (Build, Toolchain, Compatlib)
      local inc = data.includes or {}
      meta.includes_build = quote_map(inc.build, '-I')
      meta.includes_toolchain = quote_map(inc.toolchain, '-isystem')
      meta.includes_compatlib = quote_map(inc.compatlib, '-isystem')
      meta.last_projectChecksum = checksum
      pcall(M.get_sysroot_triplet, meta.cc_compiler)

      if callback then callback() end
      return true
    end

    ---------------------------------------------------------
    -- STEP 1: Fast Checksum Check
    ---------------------------------------------------------
    local _, current_checksum = vim.misc.readFile(checksum_file)
    if current_checksum and current_checksum ~= '' then
      if current_checksum == meta.last_projectChecksum then
        vim.notify('PIO: Metadata synced with cache', vim.log.levels.INFO)
        return
      end -- Already updated

      -- STEP 2: Cache Path (idedata.json exists and checksum changed)
      local _, content = vim.misc.readFile(idedata_file)
      if content then
        local ok, decoded = pcall(vim.json.decode, content)
        if ok and apply_metadata(decoded, current_checksum) then
          local metadata = require('platformio.metadata')
          metadata.save_project_config()
          vim.notify('PIO: Metadata synced from cache', vim.log.levels.INFO)
          return
        end
      end
    end

    ---------------------------------------------------------
    -- STEP 3: Auto-Initialize (If files are missing)
    ---------------------------------------------------------
    -- if not current_checksum then
    --   vim.notify('PIO: Initializing project metadata...', vim.log.levels.WARN)
    --   vim.system({ 'pio', 'run', '-t', 'idedata', '-e', active_env }, { text = true }, function(obj)
    --     vim.schedule(function()
    --       if obj.code == 0 thenl
    --         fetch_metadata(attempts, active_env) -- Recursive call after files created
    --       else
    --         vim.notify('PIO: Initialization failed. Build project manually.', vim.log.levels.ERROR)
    --       end
    --     end)
    --   end)
    --   return
    -- end

    ---------------------------------------------------------
    -- STEP 4: Standard CLI Fallback (The Slow Path)
    ---------------------------------------------------------
    vim.notify('PIO: Metadata sync ...', vim.log.levels.INFO)
    vim.system({ 'pio', 'project', 'metadata', '-e', active_env, '--json-output' }, { text = true }, function(obj)
      vim.schedule(function()
        if obj.code ~= 0 then
          if attempts > 0 then
            vim.defer_fn(function() fetch_metadata(attempts - 1, env) end, 500)
            return
          end
          return vim.notify('PIO Metadata Error: ' .. (obj.stderr or 'Unknown'), vim.log.levels.WARN)
        end

        local ok, raw_data = pcall(vim.json.decode, obj.stdout or '')
        local _, data = next(raw_data or {})

        if ok and apply_metadata(data, current_checksum) then
          vim.notify('PIO: Metadata synced from CLI', vim.log.levels.INFO)
        else
          vim.notify('PIO: Failed to parse metadata output', vim.log.levels.WARN)
        end
      end)
    end)
  end
  -------------------------------------------------------------------------------------------------------------

  -- INFO:-------------------------------------------------
  -- get pio project config info
  ---------------------------------------------------------
  -- stylua: ignore
  local function fetch_config()
    local meta = _G.metadata
    local home = (os.getenv('HOME') or os.getenv('USERPROFILE') or ""):gsub('[\\/]+$', '')

    vim.system({ 'pio', 'project', 'config', '--json-output' }, { text = true }, function(obj)
      vim.schedule(function()
        -- 1. Check Execution
        if obj.code ~= 0 then
          local msg = obj.code == 127 and "'pio' not found" or (obj.stderr or "Unknown Error")
          return vim.notify("PIO Config Error: " .. msg, vim.log.levels.ERROR)
        end

        -- 2. Decode JSON safely
        local ok, decoded = pcall(vim.json.decode, obj.stdout or "")
        if not ok or type(decoded) ~= "table" then
          return vim.notify("PIO: Failed to decode config JSON", vim.log.levels.ERROR)
        end

        -- Reset core structure
        meta.envs = {}
        meta.default_envs = {}

        -- 3. Parse Sections
        for _, section in ipairs(decoded) do
          local name, data = section[1], section[2]
          if name == 'platformio' then
            for _, kv in ipairs(data) do
              meta[kv[1]] = kv[2]
            end
          elseif name:match('^env:') then
            local env_name = name:match('^env:(.+)')
            meta.envs[env_name] = {}
            for _, kv in ipairs(data) do
              meta.envs[env_name][kv[1]] = kv[2]
            end
          end
        end

        -- 4. Assign active_env
        meta.active_env = meta.default_envs[1] or next(meta.envs) or ""

        -- 5. Resolve Paths (INI -> Env -> Default)
        local path_map = {
          { key = 'core_dir',      env = 'PLATFORMIO_CORE_DIR',      sub = '/.platformio' },
          { key = 'packages_dir',  env = 'PLATFORMIO_PACKAGES_DIR',  sub = '/.platformio/packages' },
          { key = 'platforms_dir', env = 'PLATFORMIO_PLATFORMS_DIR', sub = '/.platformio/platforms' },
        }

        for _, item in ipairs(path_map) do
          local val = meta[item.key]
          -- Fallback chain
          if not val or val == "" then
            val = os.getenv(item.env) or (home .. item.sub)
          end
          -- Expand variables and Normalize
          if type(val) == "string" then
            val = val:gsub('%%${platformio.core_dir}', meta.core_dir or "")
            meta[item.key] = vim.misc.normalizePath(val)
          end
        end

        -- 6. Trigger next step
        if meta.active_env ~= "" then
          vim.notify('PIO: Config sync successful', vim.log.levels.INFO)
          fetch_metadata(1, meta.active_env)
        else
          vim.notify('PIO: No [env:] found. Please add a board.', vim.log.levels.ERROR)
        end
      end)
    end)
  end
  fetch_config()
end

-- INFO:
-- 1. Helper: Unified hashing for change detection
local function get_hash(path)
  if vim.fn.filereadable(path) == 0 then
    return nil
  end
  -- local ok, data = pcall(vim.fn.readfile, path) -- readfile is safer than io.open
  -- return ok and vim.fn.sha256(table.concat(data, '\n')) or nil
  local ok, data = vim.misc.readFile(path) -- readfile is safer than io.open
  return (ok and data) and vim.fn.sha256(data) or ''
end

function M.run_compiledb()
  if _G.metadata.isBusy then
    return
  end
  _G.metadata.isBusy = true

  -- Use pcall to catch immediate 'command not found' errors
  local ok, result = pcall(function()
    return vim.system({ 'pio', 'run', '-t', 'compiledb' }, {}, function(obj)
      vim.schedule(function()
        _G.metadata.isBusy = false
        if obj.code == 0 then
          vim.notify('DB Updated', vim.log.levels.INFO)
        else
          -- Check stderr if code is non-zero
          local err = (obj.stderr and obj.stderr ~= '') and obj.stderr or 'Exit code ' .. obj.code
          vim.notify('PIO Error: ' .. err, vim.log.levels.ERROR)
        end
      end)
    end)
  end)

  if not ok then
    vim.notify('Failed to start PIO: ' .. tostring(result), vim.log.levels.ERROR)
    _G.metadata.isBusy = false
  end
end


-- _G.metadata.isBusy = false
-- stylua: ignore
-- function M.run_compiledb()
--   if _G.metadata.isBusy then return end
--   _G.metadata.isBusy = true
--
--   M.stop_watchers() -- 1. Silence watchers to prevent the loop
--   vim.notify('Building DB...', vim.log.levels.INFO)
--
--   vim.system({ 'pio', 'run', '-t', 'compiledb' }, {}, function(obj)
--     vim.schedule(function()
--       if obj.code == 0 then
--         -- 2. PERFORM CHECKSUM ACTIONS MANUALLY
--         local checksum_path = vim.misc.joinPath(vim.uv.cwd(), '.pio/build', 'project.checksum')
--         local ok, new_checksum = vim.misc.readFile(checksum_path)
--         if ok then
--           _G.metadata.last_projectChecksum = new_checksum -- Sync the state
--
--           -- 3. Run the refresh logic (The "Action" normally taken by the watcher)
--           M.pio_refresh(function()
--             vim.notify('DB & Cache Updated', vim.log.levels.INFO)
--             _G.metadata.isBusy = false
--             M.start_watchers() -- 4. Re-enable watchers for future changes
--           end)
--         else
--           -- If we can't read the checksum, something is wrong with the build output
--           _G.metadata.isBusy = false
--           M.start_watchers()
--         end
--       else
--         vim.notify('Build Failed', vim.log.levels.ERROR)
--         _G.metadata.isBusy = false
--         M.start_watchers()
--       end
--     end)
--   end)
-- end

-- function M.run_compiledb()
--   if _G.metadata.isBusy then
--     return
--   end
--   _G.metadata.isBusy = true
--
--   M.stop_watchers() -- Kill watchers so they don't fire during the build
--   vim.notify('Building Compilation DB...', vim.log.levels.INFO, { title = 'PlatformIO' })
--
--   vim.system({ 'pio', 'run', '-t', 'compiledb' }, {}, function(obj)
--     vim.schedule(function()
--       -- 1. Check Execution
--       if obj.code ~= 0 then
--         _G.metadata.isBusy = false
--         M.start_watchers() -- 2. RESTART after success
--         local msg = (obj.stderr and obj.stderr ~= '') and obj.stderr or 'Check pio logs'
--         return vim.notify('PIO run_compiledb Error: ' .. msg, vim.log.levels.ERROR, { title = 'PlatformIO' })
--       end
--       -- 1. Sync the checksum manually so the second watcher ignores this change
--       -- local checksum_path = vim.misc.joinPath(vim.uv.cwd(), '.pio/build', 'project.checksum')
--       -- local ok, new_checksum = vim.misc.readFile(checksum_path)
--       -- if ok then
--       _G.metadata.last_projectChecksum = new_checksum
--       -- end
--
--       -- 2. Refresh
--       M.pio_refresh(function()
--         -- local dbFix = require('platformio.utils.pio').compile_commandsFix
--         -- dbFix()
--         vim.notify('DB Updated', vim.log.levels.INFO, { title = 'PlatformIO' })
--         _G.metadata.isBusy = false
--         M.start_watchers() -- 2. RESTART after success
--         -- pio_generate_db()
--         -- lsp_restart('clangd')
--       end)
--     end)
--   end)
-- end

-- Store handles globally within the module so we can stop them

-- stylua: ignore
-- local timer = uv.new_timer()
--
-- local function watch_file(full_path, callback)
--   local handle = uv.new_fs_event()
--   local target_file = vim.fn.fnamemodify(full_path, ':t')
--   local parent_dir = vim.fn.fnamemodify(full_path, ':h')
--
--   if not handle then
--     return nil
--   end
--
--   handle:start(parent_dir, {}, function(err, filename)
--     -- 1. Strict Filter: Only process if it's our file and we aren't already busy
--     if err or filename ~= target_file or (_G.metadata and _G.metadata.isBusy) then
--       return
--     end
--
--     -- 2. Debounce: Reset the timer on every event
--     -- Only after 500ms of "silence" will the actual callback run
--     if timer then
--       timer:stop()
--       timer:start(
--         500,
--         0,
--         vim.schedule_wrap(function()
--           -- 3. Final Check: Ensure file exists before running heavy logic
--           local stat = uv.fs_stat(full_path)
--           if stat and stat.type == 'file' then
--             callback()
--           end
--         end)
--       )
--     end
--   end)
--   return handle
-- end



local uv = vim.uv or vim.loop
M.watcher_handles = {}

-- Use a single, global-ish timer variable to handle debouncing across all events
-- local debounce_timer = vim.uv.new_timer()
--
-- local function watch_file(full_path, callback)
--   -- 1. Nil check input parameters
--   if not full_path or type(callback) ~= 'function' then
--     vim.notify('watch_file: Invalid path or callback', vim.log.levels.ERROR)
--     return nil
--   end
--
--   local handle, init_err = vim.uv.new_fs_event()
--   if not handle then
--     vim.notify('watch_file: Failed to create handle: ' .. tostring(init_err), vim.log.levels.ERROR)
--     return nil
--   end
--
--   local parent_dir = vim.fn.fnamemodify(full_path, ':h')
--   local target_file = vim.fn.fnamemodify(full_path, ':t')
--
--   -- Start the watcher on the parent directory
--   handle:start(parent_dir, {}, function(err, filename, events)
--     -- 2. Robust error checking (tostring handles nil err)
--     if err then
--       vim.schedule(function()
--         vim.notify('Watcher system error: ' .. tostring(err), vim.log.levels.ERROR)
--       end)
--       return
--     end
--
--     -- 3. Guard against nil filename and metadata
--     -- Only proceed if the event is for our target file and we aren't busy
--     local is_target = (filename == target_file)
--     local is_busy = (_G.metadata and _G.metadata.isBusy == true)
--
--     if not is_target or is_busy then
--       return
--     end
--
--     if debounce_timer then
--       -- 4. Debounce Logic with Timer Safety
--       -- Stop existing timer if it's currently running (debouncing)
--       if debounce_timer:is_active() then
--         debounce_timer:stop()
--       end
--
--       -- Start/Restart the timer
--       debounce_timer:start(
--         500,
--         0,
--         vim.schedule_wrap(function()
--           -- 5. Final existence check before execution
--           -- Some editors delete/rename files during save (atomic saves)
--           local stat = vim.uv.fs_stat(full_path)
--           if stat and stat.type == 'file' then
--             print('File settled: ' .. target_file)
--             callback()
--           end
--         end)
--       )
--     end
--   end)
--
--   return handle
-- end

-- stylua: ignore
local function watch_file(full_path, callback)
  local handle = uv.new_fs_event()
  local parent_dir = vim.fn.fnamemodify(full_path, ':h')
  local target_file = vim.fn.fnamemodify(full_path, ':t')

  if not handle then return nil end
  handle:start(parent_dir, {}, function(err, filename, events)
    -- 1. Catch REAL system errors
    if err or filename ~= target_file or (_G.metadata and _G.metadata.isBusy) or (events and not (events.change or events.rename)) then
      if err then
      -- Use vim.schedule to notify so we don't block the loop
        vim.schedule(function()
          vim.notify('Watcher error: ' .. tostring(err), vim.log.levels.ERROR)
        end)
      end
      return --handle:stop()
    end

    -- if filename == target_file then
    -- end

    -- 2. SILENTLY ignore events that aren't our target file
    -- Or if we are currently busy processing another task
    -- if filename ~= target_file or _G.metadata.isBusy then
    --   return
    -- end

    -- Debounce: Use vim.schedule to ensure we don't fire
    -- during the middle of a file-swap operation
    -- 3. Trigger the callback safely
    vim.defer_fn(function()
      print('file watched')
      -- Re-verify file exists before calling
      if vim.loop.fs_stat(full_path) then callback() end
    end, 500)
    -- vim.schedule(callback)
  end)
  return handle
end

-- stylua: ignore
function M.start_watchers()
  -- Clean up any existing watchers first to prevent duplicates
  M.stop_watchers()

  _G.metadata.isBusy = false
  local project_root = vim.uv.cwd() -- Use dynamic CWD instead of hardcoded path
  local active_env = _G.metadata.active_env or 'default'

  local targets = {
    { -- watcher for platformio.ini
      current_ini_hash = '',
      path = vim.misc.joinPath(project_root, 'platformio.ini'),
      cb = function(self)
        local new_hash = get_hash(self.path) or ''
        if new_hash and new_hash ~= self.current_ini_hash then
          self.current_ini_hash = new_hash
          M.run_compiledb() -- Smart: Auto-update DB if config changes
          -- local pio = require('platformio.utils.pio')
          -- pio.run_sequence({
          --   cmnds = {
          --     'pio run -t compiledb',
          --   },
          --   cb = pio.handlePiodb,
          -- })
        end
      end,
    },
    { -- watcher for ./.pio/build/projct.checksum
      idedata_path = vim.misc.joinPath(project_root, '.pio/build', active_env, 'idedata.json'),--idedata.json path
      path = vim.misc.joinPath(project_root, '.pio/build', 'project.checksum'), --checksum_path
      cb = function(self)
        local _, current_checksum = vim.misc.readFile(self.path)
        if current_checksum and current_checksum ~= '' then
          if current_checksum == _G.metadata.last_projectChecksum then
            return
          end -- Already updated

          vim.notify('Checksum change', vim.log.levels.INFO, { title = 'PlatformIO' })
        _G.metadata.isBusy = false
          -- STEP 2: Cache Path (idedata.json exists and checksum changed)
          -- M.pio_refresh(function()
          --   -- local dbFix = require('platformio.utils.pio').compile_commandsFix
          --   -- dbFix()
          --   vim.notify('DB Updated', vim.log.levels.INFO, { title = 'PlatformIO' })
          -- end)
        end
      end,
    },
  }
  targets[1].current_ini_hash = get_hash(targets[1].path) or ''

  for _, target in ipairs(targets) do
    --[[ wrap the callback in a small anonymous function,
        so it passes the target (self) back into it.]]
    local h = watch_file(target.path, function() target.cb(target) end)
    table.insert(M.watcher_handles, h)
  end
end

-- stylua: ignore
function M.stop_watchers()
  -- Safety: Ensure it's a table before looping
  M.watcher_handles = M.watcher_handles or {}

  for _, handle in ipairs(M.watcher_handles) do
    if handle and not handle:is_closing() then handle:stop() end
  end
  M.watcher_handles = {}
end

-- local dir_path = vim.uv.cwd()
-- local ini_file = vim.misc.joinPath(dir_path, 'platformio.ini')
-- -- INFO:
-- -- 4. Simple Watcher: Only triggers if the FILE CONTENT changed
-- function M.start_watcher()
--   if not dir_path or vim.fn.filereadable(ini_file) == 0 then
--     return
--   end
--   local current_ini_hash = get_hash(ini_file)
--   _G.metadata.isBusy = false
--
--   local handle = vim.uv.new_fs_event()
--   if handle then
--     handle:start(
--       dir_path,
--       { recursive = false },
--       vim.schedule_wrap(function(err, fname, events)
--         if err or fname ~= 'platformio.ini' or _G.metadata.isBusy or not events or not (events.change or events.renamce) then
--           return handle:stop()
--         end
--
--         if _G.metadata.isBusy then
--           return
--         end
--
--         local new_hash = get_hash(ini_file)
--         if new_hash and new_hash ~= current_ini_hash then
--           current_ini_hash = new_hash
--           M.run_compiledb() -- Smart: Auto-update DB if config changes
--         end
--       end)
--     )
--   end
-- end

----------------------------------------------------------------------------------------------
-- local function start_pio_watcher()
--   local dir_path = vim.uv.cwd()
--   if not dir_path then return end
--
--   -- Create a directory watcher
--   local handle = vim.uv.new_fs_event()
--   if not handle then return end
--
--   -- local last_trigger = 0
--   -- Watch the directory for platformio.ini creation or changes
--   handle:start(
--     dir_path,
--     {
--       watch_entry = false, -- watch the file/dir itself
--       stat = false,        -- use stat to detect changes (slower but more reliable on some FS)
--       recursive = false,   -- watch subdirectories (if path is a directory)
--     },
--     vim.schedule_wrap(function(err, filename, events)
--       if err or not events or not events.change then return end
--       -- Trigger only if the changed file is platformio.ini
--       if filename == 'platformio.ini' and (events.change or events.rename) then
--         if debounce_timer then
--           debounce_timer:stop()
--           debounce_timer:start(
--             500,
--             0,
--             vim.schedule_wrap(function()
--               pio_refresh(function()
--                 boilerplate_gen([[.clangd]], vim.g.platformioRootDir)
--                 boilerplate_gen([[.clangd]], _G.metadata.core_dir)
--                 -- boilerplate_gen([[.clangd]], vim.env.XDG_CONFIG_HOME .. '/clangd', 'config.yaml')
--                 pio_generate_db()
--                 lsp_restart('clangd')
--                 -- end)
--   end) end)) end end end))
-- end
------------------------------------------------------------------------------------------------------
-- INFO: 6.  Exported setup function
function M.init()
  local config = require('platformio').config
  if config.lspClangd.enabled == true then
    vim.notify('PIO setup initialize', vim.log.levels.INFO)

    -- activate meta save and upload and env switch
    local metadata = require('platformio.metadata')
    metadata.load_project_config()

    require('platformio.lspConfig.clangd')
    if config.lspClangd.attach.enabled then
      require('platformio.lspConfig.attach')
    end

    -- Always start the watcher so it can catch a future 'pio init'
    M.start_watchers()

    -- boilerplate_gen([[platformio.ini]], vim.g.platformioRootDir)
    -- If the file already exists, do an initial sync
    if vim.fn.filereadable(vim.uv.cwd() .. '/platformio.ini') == 1 then
      ----------------------------------------------------------------------------------------
      -- INFO: create clangd required files
      -----------------------------------------------------------------------------------------
      boilerplate_gen([[.clangd]], vim.g.platformioRootDir)
      -- boilerplate_gen([[.clangd]], vim.fs.joinpath(vim.env.XDG_CONFIG_HOME, 'clangd'), 'config.yaml')
      -- boilerplate_gen([[.clangd]], _G.metadata.core_dir)
      boilerplate.core_dir = _G.metadata.core_dir
      boilerplate_gen([[.clang-format]], vim.g.platformioRootDir)
      ---------------------------------------------------------------------------------
      -- M.run_compiledb() -- Smart: Auto-update DB if config changes
      M.pio_refresh(function()
        -- vim.schedule(function()
        --   lsp_restart('clangd')
        -- end)
      end)
    end
  end
end

return M
