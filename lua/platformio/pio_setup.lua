local misc = require('platformio.utils.misc')
local lsp = require('platformio.utils.lsp')

-- lua/pio_setup.lua
-- This module manages PlatformIO project integration, LSP toolchain detection,
-- and automatic sysroot patching for standard library headers (<algorithm>, etc.)

local debounce_timer = vim.uv.new_timer()

local pio_manager = (function()
  local cache = nil -- Stores the decoded platformio.ini JSON structure

  -- HELPER: Navigates the specific nested list format used by 'pio project config --json-output'
  -- The format is typically: { { "section_name", { {"key", "value"}, ... } }, ... }
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

  -- ASYNC REFRESH: Fetches the latest config from PlatformIO CLI
  local function refresh(callback)
    vim.schedule(function()
      vim.notify('PIO: Fetching Config...', vim.log.levels.INFO)
    end)
    local function execute_pio(attempts)
      -- Use Neovim's async system call to prevent UI freezing
      vim.system({ 'pio', 'project', 'config', '--json-output' }, { text = true }, function(obj)
        -- Error Checking: obj.code 0 means success
        if obj.code == 0 and obj.stdout then
          local ok, decoded = pcall(vim.json.decode, obj.stdout)
          if ok and decoded then
            cache = decoded
            if callback then
              vim.schedule(callback)
            end
            return
          end
        end

        -- RETRY LOGIC: Handles "Error 1" (file busy) or temporary syntax errors during save
        if attempts > 0 then
          vim.defer_fn(function()
            execute_pio(attempts - 1)
          end, 500)
        else
          vim.schedule(function()
            if obj.code ~= 0 then
              vim.notify('PIO: Config Error. Check platformio.ini syntax.', vim.log.levels.WARN)
            end
          end)
        end
      end)
    end
    execute_pio(1)
  end

  return {
    refresh = refresh,
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
      end
      return res
    end,
  }
end)()

-- LSP HELPER: Returns the glob pattern for clangd's --query-driver
-- e.g., C:\Users\tom\.platformio\packages\toolchain-riscv32-esp\bin\*
function _G.get_pio_toolchain_pattern()
  local ok_env, active_env = pcall(function()
    return vim.g.pio_active_env or pio_manager.get('platformio', 'default_envs')
  end)
  if not ok_env or not active_env then
    return '/**/bin/*'
  end

  local target_env = 'env:' .. active_env
  local platform = pio_manager.get(target_env, 'platform')
  -- Determine the packages directory (Windows vs Linux/Mac home folders)
  local packages_dir = pio_manager.get('platformio', 'packages_dir') or (os.getenv('USERPROFILE') or os.getenv('HOME') .. '/.platformio/packages')

  if not platform then
    return '/**/bin/*'
  end

  -- Use pio platform show to find which toolchain packages are associated with the platform
  local p_handle = io.popen('pio platform show ' .. platform .. ' --json-output')
  if not p_handle then
    return '/**/bin/*'
  end
  local raw_json = p_handle:read('*all')
  p_handle:close()

  local p_ok, p_data = pcall(vim.json.decode, raw_json)
  if not p_ok or not p_data or not p_data.packages then
    return '/**/bin/*'
  end

  local toolchain_folder = ''
  for _, pkg in ipairs(p_data.packages) do
    -- Skip ULP (low power) toolchains and find the primary one for the architecture
    if pkg.name and pkg.name:find('^toolchain%-') and not pkg.name:find('ulp') then
      local check_path = (packages_dir .. '/' .. pkg.name):gsub('\\', '/')
      if vim.fn.isdirectory(check_path) == 1 then
        toolchain_folder = pkg.name
        -- Verification: Match the toolchain name against the compiler used in compile_commands.json
        local db_path = vim.uv.cwd() .. '/compile_commands.json'
        local f = io.open(db_path, 'r')
        if f then
          local head = f:read(2048) -- Read enough to find the compiler path
          f:close()
          -- If the DB mentions "riscv32-esp", we ensure we picked the matching folder
          if head and head:find(pkg.name:gsub('toolchain%-', '')) then
            break
          end
        end
      end
    end
  end

  if toolchain_folder == '' then
    return '/**/bin/*'
  end

  local final = packages_dir .. toolchain_folder
  print('toolchain 5: final=' .. final)
  -- Normalize paths for the OS and ensure backslashes for Windows if needed
  return (misc.normalize_path(final))
  -- return vim.fn.has('win32') == 1 and final:gsub('/', '\\') or final
end

-- DATABASE PATCHER: Generates compile_commands.json and injects the --sysroot flag
local function pio_generate_db()
  vim.schedule(function()
    vim.notify('PIO: Generating Compile Database...', vim.log.levels.INFO)
  end)
  vim.system({ 'pio', 'run', '-t', 'compiledb' }, { text = true }, function(obj)
    if obj.code ~= 0 then
      return
    end

    -- Isolate the toolchain root from the pattern (e.g. .../toolchain-riscv32-esp)
    local pattern = _G.get_pio_toolchain_pattern()
    local toolchain_root = pattern:match('(.-toolchain%-[^/\\]+)')
    if not toolchain_root or vim.fn.isdirectory(toolchain_root) == 0 then
      return
    end

    -- FIND SYSROOT: Locate the internal folder that contains the /include directory
    -- This folder is necessary for clangd to find standard C++ headers like <algorithm>
    local sysroot_path = nil
    local subdirs = vim.fn.getcompletion(toolchain_root .. '/*', 'dir')
    for _, dir in ipairs(subdirs) do
      if vim.fn.isdirectory(dir .. '/include') == 1 then
        sysroot_path = dir:gsub('\\', '/')
        break
      end
    end

    if sysroot_path then
      local db_path = vim.uv.cwd() .. '/compile_commands.json'
      local f = io.open(db_path, 'r')
      if not f then
        return
      end
      local content = f:read('*all')
      f:close()

      -- Inject the --sysroot flag into every command in the JSON file
      if content and content ~= '' then
        local patched = content:gsub('("-i")', '"--sysroot=' .. sysroot_path .. '", %1')
        local out = io.open(db_path, 'w')
        if out then
          out:write(patched)
          out:close()
          vim.schedule(function()
            vim.notify('PIO: Sync Complete!', vim.log.levels.INFO)
          end)
        end
      end
    end
  end)
end

-- FILE WATCHER: Listens for changes in platformio.ini to trigger auto-sync
local function start_pio_watcher()
  local path = vim.uv.cwd() .. '/platformio.ini'
  if vim.fn.filereadable(path) == 0 then
    return
  end

  local w = vim.uv.new_fs_event()
  if not w then
    return
  end
  w:start(
    path,
    {},
    vim.schedule_wrap(function(err, _, events)
      if err or not events or not events.change then
        return
      end

      if debounce_timer then
        -- DEBOUNCE: Stops and restarts the timer to ensure we only sync ONCE after typing stops
        debounce_timer:stop()
        debounce_timer:start(
          500,
          0,
          vim.schedule_wrap(function()
            pio_manager.refresh(function()
              pio_generate_db()
              lsp.lsp_restart('clangd')
              vim.notify('PIO: Syncing Environment...')
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
      if vim.fn.filereadable(vim.uv.cwd() .. '/platformio.ini') == 1 then
        pio_manager.refresh(function()
          pio_generate_db()
          start_pio_watcher()
        end)
      end
    end
  end,
}
