local function get_metadata(attempts, env)
  local meta = _G.metadata
  local active_env = env or meta.active_env
  if not active_env or active_env == '' then
    return
  end

  -- Set up file paths
  local build_dir = vim.misc.joinPath(vim.uv.cwd(), '.pio', 'build', active_env)
  local checksum_path = vim.misc.joinPath(build_dir, 'project.checksum')
  local idedata_path = vim.misc.joinPath(build_dir, 'idedata.json')

  ---------------------------------------------------------
  -- INTERNAL PROCESSOR: Applies parsed data to _G.metadata
  ---------------------------------------------------------
  local function apply_metadata(data, checksum)
    if not data then
      return false
    end

    local norm = function(p)
      return vim.misc.normalizePath(p) or ''
    end

    local quote_map = function(list, prefix)
      local res = {}
      for _, v in ipairs(list or {}) do
        local val = prefix and (prefix .. norm(v)) or v
        table.insert(res, string.format('%q', val))
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
    meta.last_checksum = checksum
    pcall(M.get_sysroot_triplet, meta.cc_compiler)

    if callback then
      callback()
    end
    return true
  end

  ---------------------------------------------------------
  -- STEP 1: Fast Checksum Check
  ---------------------------------------------------------
  local current_checksum = vim.misc.readFile(checksum_path)
  if current_checksum and current_checksum ~= '' then
    if current_checksum == meta.last_checksum then
      return
    end -- Already updated

    -- STEP 2: Cache Path (idedata.json exists and checksum changed)
    local content = vim.misc.readFile(idedata_path)
    if content then
      local ok, decoded = pcall(vim.json.decode, content)
      if ok and apply_metadata(decoded, current_checksum) then
        vim.notify('PIO: Metadata synced from cache', vim.log.levels.INFO)
        return
      end
    end
  end

  ---------------------------------------------------------
  -- STEP 3: Auto-Initialize (If files are missing)
  ---------------------------------------------------------
  if not current_checksum then
    vim.notify('PIO: Initializing project metadata...', vim.log.levels.WARN)
    vim.system({ 'pio', 'run', '-t', 'idedata', '-e', active_env }, { text = true }, function(obj)
      vim.schedule(function()
        if obj.code == 0 then
          get_metadata(attempts, active_env) -- Recursive call after files created
        else
          vim.notify('PIO: Initialization failed. Build project manually.', vim.log.levels.ERROR)
        end
      end)
    end)
    return
  end

  ---------------------------------------------------------
  -- STEP 4: Standard CLI Fallback (The Slow Path)
  ---------------------------------------------------------
  vim.notify('PIO: Fetching fresh metadata...', vim.log.levels.INFO)
  vim.system({ 'pio', 'project', 'metadata', '-e', active_env, '--json-output' }, { text = true }, function(obj)
    vim.schedule(function()
      if obj.code ~= 0 then
        if attempts > 0 then
          vim.defer_fn(function()
            get_metadata(attempts - 1, env)
          end, 500)
          return
        end
        return vim.notify('PIO Metadata Error: ' .. (obj.stderr or 'Unknown'), vim.log.levels.WARN)
      end

      local ok, raw_data = pcall(vim.json.decode, obj.stdout or '')
      local _, data = next(raw_data or {})

      if ok and apply_metadata(data, current_checksum) then
        vim.notify('PIO: Metadata sync successful', vim.log.levels.INFO)
      else
        vim.notify('PIO: Failed to parse metadata output', vim.log.levels.WARN)
      end
    end)
  end)
end
