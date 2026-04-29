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

-- =============================================================================
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

-- =============================================================================
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

-- =============================================================================
-- stylua: ignore
-- INFO:
-- 1.run_compiledb
function M.run_compiledb()
  -- 1. Prevent overlapping builds
  if _G.metadata.isBusy then
    return
  end
  _G.metadata.isBusy = true
  M.stop_watchers()

  vim.notify('PIO: Building Compilation DB...', vim.log.levels.INFO, { title = 'PlatformIO' })

  -- 2. Run the command asynchronously
  -- 'pio run -t compiledb' updates compile_commands.json
  vim.system({ 'pio', 'run', '-t', 'compiledb' }, { detach = true, text = true }, function(obj)
    vim.schedule(function()
      -- 3. Release the lock immediately when the process returns
      _G.metadata.isBusy = false

      if obj.code == 0 then
        -- Optional: Sync the hash of platformio.ini so the watcher doesn't refire
        -- (Assuming targets[1] is the ini watcher)
        -- targets[1].last_hash = get_hash(targets[1].path)

        vim.notify('DB Updated Successfully', vim.log.levels.INFO, { title = 'PlatformIO' })
        M.start_watchers()

        -- Trigger refresh (LSP restart, etc.)
        -- if M.pio_refresh then
        --   M.pio_refresh(function()
        --     -- Post-refresh logic here
        --   end)
        -- end
      else
        -- 4. Handle errors (missing pio, syntax error in config, etc.)
        local err = (obj.stderr and obj.stderr ~= '') and obj.stderr or 'Check PIO logs'
        vim.notify('PIO Build Failed: ' .. err, vim.log.levels.ERROR, { title = 'PlatformIO' })
        M.start_watchers()
      end
    end)
  end)
end

-- =============================================================================
-- INFO:
-- Ensure this is at the TOP of your file, outside any functions
local uv = vim.uv or vim.loop
M.watcher_handles = {}
local debounce_timer = uv.new_timer()

-- =============================================================================
-- stylua: ignore
-- INFO:
-- 2.stop_watchers 
function M.stop_watchers()
  if not M.watcher_handles or (type(M.watcher_handles) ~= 'table') then M.watcher_handles = {} return end

  for _, handle in ipairs(M.watcher_handles) do
    if handle and not handle:is_closing() then
      handle:stop()
      handle:close() -- CRITICAL: This allows Neovim to quit instantly
    end
  end
  M.watcher_handles = {}
end

-- =============================================================================
-- stylua: ignore
-- INFO:
-- 3.watcher cleanup
function M.cleanup()
  M.stop_watchers()
  if debounce_timer and not debounce_timer:is_closing() then
    debounce_timer:stop()
    debounce_timer:close()
  end
end

-- =============================================================================
-- stylua: ignore
-- INFO:
-- 4. watch_file
-- stylua: ignore
local function watch_file(full_path, callback)
  local handle = uv.new_fs_poll()
  if not handle then return end

  -- Poll every 1000ms. This is light on CPU and ignores "save noise".
  handle:start(full_path, 1000, function(err, stat)
    if err or not stat or (_G.metadata and _G.metadata.isBusy) then return end
    vim.schedule(callback)
  end)

  table.insert(M.watcher_handles, handle)
  return handle
end

-- =============================================================================
-- INFO:
-- 5.Force cleanup when leaving Neovim to prevent :qa lag
vim.api.nvim_create_autocmd('VimLeavePre', {
  callback = function()
    M.cleanup()
  end,
})

-- =============================================================================
-- stylua: ignore
-- INFO:
-- 5. start_watches
function M.start_watchers()
  -- Clean up any existing watchers first to prevent duplicates
  if next(M.watcher_handles) then M.stop_watchers() end

  _G.metadata.isBusy = false
  local project_root = vim.uv.cwd() -- Use dynamic CWD instead of hardcoded path
  local active_env = _G.metadata.active_env or 'default'

  local targets = {
    { -- watcher for platformio.ini
      name = 'ini',
      last_hash = '',
      path = vim.misc.joinPath(project_root, 'platformio.ini'),
      cb = function(self)
        local new_hash = get_hash(self.path) or ''
        if new_hash and new_hash ~= self.last_hash then
          self.last_hash = new_hash
          -- M.run_compiledb() -- Smart: Auto-update DB if config changes
          local pio = require('platformio.utils.pio')
          pio.run_sequence({
            cmnds = {
              'pio run -t build',
            },
            cb = pio.handlePiodb,
          })
        end
      end,
    },
    { -- watcher for ./.pio/build/projct.checksum
      name = 'checksum',
      path = vim.misc.joinPath(project_root, '.pio', 'build', 'project.checksum'), --checksum_path
      idedata_path = vim.misc.joinPath(project_root, '.pio/build', active_env, 'idedata.json'),--idedata.json path
      cb = function(self)
        local ok, current_checksum = vim.misc.readFile(self.path)

        -- Check if we should exit early
        if not ok or current_checksum == '' or current_checksum == _G.metadata.last_projectChecksum then
          return
        end

        _G.metadata.last_projectChecksum = current_checksum -- Update the state
        M.pio_refresh(function()
          vim.notify('PIO: Metadata synced from cache, checksum', vim.log.levels.INFO)
        end)
      end
    },
  }
  -- targets[1].last_hash = get_hash(targets[1].path) or ''

  for _, target in ipairs(targets) do
    --[[ wrap the callback in a small anonymous function,
        so it passes the target (self) back into it.]]
    local handle = watch_file(target.path, function() target.cb(target) end)
    if handle then  table.insert(M.watcher_handles, handle) end
  end
end

-- =============================================================================
-- stylua: ignore
-- INFO: 7.  Exported setup function
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
