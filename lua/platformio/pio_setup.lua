local misc = require('platformio.utils.misc')
local lsp = require('platformio.utils.lsp')

-- INFO: 1. The Core PIO Manager & Generic Extractor
--This manages the data cache and navigates your specific nested-list JSON structure.
-- stylua: ignore
local pio_manager = (function()
  local cache = nil

  --  INFO: 1 Generic extractor for nested structure: { { "name", { {"k","v"}, ... } }, ... }
  local function find_in_data(data, section_name, key_name)
    if not data or type(data) ~= 'table' then return nil end

    -- INFO:  1.0 SPECIFIC SEARCH: Look for a specific section (e.g., "platformio")
    if section_name then
      for _, section in ipairs(data) do
        if type(section) == 'table' and #section >= 2 then
          local s_id = section[1]
          local s_body = section[2]
          if s_id == section_name and type(s_body) == "table" then
            for _, kv in ipairs(s_body) do
             if type(kv) == "table" and #kv >= 2 and kv[1] == key_name then
               local val = kv[2]
               if val ~= nil and val ~= '' and (type(val) ~= 'table' or #val > 0) then
                 return val
                end
              end
            end
          end
        end
      end
    end

    -- INFO:  1.1 FALLBACK SEARCH (If we reach here, Step 1 failed or was skipped)
    local fallback_env_found = nil
    for _, section in ipairs(data) do
      if type(section) == 'table' and #section >= 2 then
        local s_id = section[1]
        local s_body = section[2]
        -- Look for hardware envs like [env:seeed_xiao_esp32c3], skipping generic [env]
        if type(s_id) == 'string' and s_id:find('^env:') then
          fallback_env_found = s_id:match('^env:(.+)')

          -- If we were looking for default_envs, we just found our fallback
          if key_name == 'default_envs' then
            vim.schedule(function()
              vim.notify("PIO: 'default_envs' empty. Falling back to: " .. fallback_env_found, vim.log.levels.INFO)
            end)
            return fallback_env_found
          end

          -- If looking for a key (like 'platform') inside this fallback env
          if type(s_body) == 'table' then
            for _, kv in ipairs(s_body) do
              if type(kv) == 'table' and #kv >= 2 and kv[1] == key_name then
                local val = kv[2]
                if val ~= nil and val ~= '' and (type(val) ~= 'table' or #val > 0) then
                  vim.schedule(function()
                    vim.notify("PIO: Using '" .. key_name .. "' from fallback env: " .. fallback_env_found, vim.log.levels.INFO)
                  end)
                  return val
                end
              end
            end
          end
        end
      end
    end

    -- INFO:  1.2 FINAL ERROR If even fallback fails
    if key_name == 'platform' or key_name == 'packages_dir' then
      vim.schedule(function()
        vim.notify("PIO: Critical key '" .. key_name .. "' not found anywhere!", vim.log.levels.INFO)
      end)
    end
    return nil
  end
  ------------------------------------------------------------------------------------------

  --  INFO: 2. Asynchronous Refresh
  local function refresh(callback)
    -- Using vim.system to detect if the command exists
    vim.system({ 'pio', 'project', 'config', '--json-output' }, { text = true }, function(obj)
      if obj.code ~= 0 then
        -- Schedule notification to avoid error in the system callback thread
        vim.schedule(function()
          if obj.code == 127 then
            vim.notify("PIO Manager: 'pio' command not found. Ensure PlatformIO Core is installed.", vim.log.levels.ERROR)
          else
            vim.notify('PIO Manager: Failed to fetch config (Error ' .. obj.code .. ')', vim.log.levels.WARN)
          end
        end)
        return
      end
      local ok, decoded = pcall(vim.json.decode, obj.stdout)
      if ok and decoded then
        cache = decoded
        if not cache or type(cache) ~= 'table' then
          print('no cahce')
        else
          print('cahced ok')
        end
        if callback then vim.schedule(callback) end
      end
    end)
  end
  return {
    refresh = refresh,
    get = function(s, k)
      return find_in_data(cache, s, k)
    end,
  }
end)()

------------------------------------------------------------------------------------------------------
-- INFO: 2. Generic Toolchain & Sysroot Logic. These functions identify where the compiler and its C++ headers live.
-- Gets the compiler glob for clangd --query-driver
-- stylua: ignore
function _G.get_pio_toolchain_pattern()
  local active_env = vim.g.pio_active_env or pio_manager.get("platformio", "default_envs")
                    -- or pio_manager.get(nil, "default_envs")

  -- Handle default_envs being a list/table
  if type(active_env) == 'table' then active_env = active_env[1] end

  local target_env = active_env and ('env:' .. active_env) or nil
  local platform = pio_manager.get(target_env, 'platform')
  local packages_dir = pio_manager.get('platformio', 'packages_dir') or (os.getenv('HOME') or os.getenv('USERPROFILE') .. '/.platformio/packages')

  if not platform then return '/**/bin/*' end

  -- Sync call for toolchain name
  local p_handle = io.popen('pio platform show ' .. platform .. ' --json-output')
  if not p_handle then return '/**/bin/*' end

  local p_json = p_handle:read('*all')
  p_handle:close()
  local arch_glob = '/**/bin/*'
  local p_ok, p_data = pcall(vim.json.decode, p_json)
  if p_ok and p_data and type(p_data.packages) == 'table' then
    for pkg_name, _ in pairs(p_data.packages) do
      if type(pkg_name) == 'string' and pkg_name:find('^toolchain%-') then
        local arch = pkg_name:gsub('toolchain%-', ''):gsub('gcc%-?', '')
        arch_glob = '/**/bin/*' .. arch .. '*'
        break
      end
    end
  end
  -- local final = (packages_dir:gsub('\\', '/') .. arch_glob):gsub('//+', '/')
  local final = packages_dir .. arch_glob
  print('toolchain 5: final=' .. final)
  return (misc.normalize_path(final))
  -- return vim.fn.has('win32') == 1 and final:gsub('/', '\\') or final
end

-- INFO: 3. Patches compile_commands.json with --sysroot to fix <algorithm>
-- Helper to generate the compilation database
-- stylua: ignore
local function pio_generate_db()
  -- This runs in the background so it doesn't freeze Neovim
  vim.system({ 'pio', 'run', '-t', 'compiledb' }, { text = true }, function(obj)
    if obj.code ~= 0 then return end
    print('pio_generate_db 0')
    local pattern = _G.get_pio_toolchain_pattern()
    local toolchain_root = pattern:match('(.*toolchain%-[^/\\]+)')
    if not toolchain_root or vim.fn.isdirectory(toolchain_root) == 0 then
      return
    end

    -- Find subdirectory containing 'include' (the sysroot)
    local sysroot_path = nil
    local subdirs = vim.fn.getcompletion(toolchain_root .. '/*', 'dir')
    for _, dir in ipairs(subdirs) do
      if vim.fn.isdirectory(dir .. '/include') == 1 then
        sysroot_path = dir:gsub('\\', '/')
        break
      end
    end
    if sysroot_path then
      local db_path = vim.fn.getcwd() .. '/compile_commands.json'
      local f = io.open(db_path, 'r')
      if not f then return end
      local content = f:read('*all')
      f:close()

      -- patch sysroot
      local patched = content:gsub('("-i")', '"--sysroot=' .. sysroot_path .. '", %1')
      local out = io.open(db_path, 'w')
      if out then
        out:write(patched)
        out:close()
        vim.schedule(function() vim.notify('PIO: DB & Sysroot Patched') end)
      end
    end
  end)
end

------------------------------------------------------------------------------------------------------
-- INFO: 4. Automation & File Watcher
--This handles the background synchronization when you save your project.
local debounce_timer = vim.uv.new_timer()
-- stylua: ignore
local function start_pio_watcher()
  local path = vim.fn.getcwd() .. '/platformio.ini'
  if vim.fn.filereadable(path) == 0 then return end

  local w = vim.uv.new_fs_event()
  if not w then return end

  w:start(
    path, {},
    vim.schedule_wrap(function(err, _, events)
      if err or not events.change then return end

      -- 1. Stop any existing timer (cancel previous "half-finished" events)
      if debounce_timer then
        debounce_timer:stop()

        -- 2. Start a 500ms window. Logic only runs if NO more events happen in this time.
        debounce_timer:start( 500, 0,
          vim.schedule_wrap(function()
            vim.notify('PIO: Config change detected. Refreshing...', vim.log.levels.INFO)

            pio_manager.refresh(function()
              pio_generate_db()
              -- 3. Only restart LSP if the pattern actually changed or DB was updated
              lsp.lsp_restart('clangd')
            end)
          end)
        )
      end
    end)
  )
end

------------------------------------------------------------------------------------------------------
-- INFO: 6.  Exported setup function
return {
  init = function()
    local config = require('platformio').config
    if config.lspClangd.enabled == true then
      vim.notify('PIO setup initialize', vim.log.levels.INFO)
      ----------------------------------------------------------------------------------------
      -- INFO: create clangd required files
      -----------------------------------------------------------------------------------------
      local boilerplate_gen = require('platformio.boilerplate').boilerplate_gen
      boilerplate_gen([[platformio.ini]], vim.g.platformioRootDir)

      boilerplate_gen([[.clangd]], vim.g.platformioRootDir)
      boilerplate_gen([[.clangd]], require('platformio.utils.pio').get_pio_dir('core')) --vim.env.PLATFORMIO_CORE_DIR)
      -- boilerplate_gen([[.clangd]], vim.fn.stdpath('data'))
      -- boilerplate_gen([[.clangd]], vim.env.XDG_CONFIG_HOME .. '/clangd', 'config.yaml')

      -- boilerplate_gen([[.clangd_cmd]], vim.g.platformioRootDir)

      boilerplate_gen([[.clang-format]], vim.g.platformioRootDir)

      boilerplate_gen([[.stylua.toml]], vim.g.platformioRootDir)
      -- boilerplate_gen([[enable_toolchain.py]], vim.g.platformioRootDir)
      -- boilerplate_gen([[generate_compile_commands.py]], vim.g.platformioRootDir)
      ---------------------------------------------------------------------------------

      -- vim.api.nvim_echo({ { 'lspClangd true', 'Info' } }, true, {})
      require('platformio.lspConfig.clangd')
      if config.lspClangd.attach.enabled then
        require('platformio.lspConfig.attach')
      end
      if vim.fn.filereadable(vim.fn.getcwd() .. '/platformio.ini') == 1 then
        pio_manager.refresh(function()
          pio_generate_db()
          start_pio_watcher()
        end)
      end
    end
  end,
}
