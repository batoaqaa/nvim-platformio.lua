M = {}

M.metadata = {
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

-- stylua: ignore
local function GetActivePioEnv()
  local file = io.open('platformio.ini', 'r')
  if not file then
    M.metadata.active_env = ''
    return nil
  end

  local first_env = nil
  for line in file:lines() do
    -- 1. Try to find the explicit default_envs first
    local default = line:match('^default_envs%s*=%s*(%S+)')
    if default then
      file:close()
      return default
    end

    -- 2. Capture the first [env:NAME] we see as a fallback
    if not first_env then
      first_env = line:match('^%[env:(%S+)%]')
    end
  end

  file:close()
  -- Return the first env found if no default was explicitly set
  return first_env
end

-- INFO: 1. The Core PIO Manager & Generic Extractor
local pio_manager = (function()
  local cache = nil -- Stores the decoded platformio.ini JSON structure

  -- INFO:
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

  -- INFO:
  -- ASYNC REFRESH: Fetches the latest config from PlatformIO CLI
  local function refresh(callback)
    vim.schedule(function()
      vim.notify('PIO: Fetching Config...', vim.log.levels.INFO)
    end)
    -- INFO:
    local function execute_pio(attempts)
      if not M.metadata.active_env or M.metadata.active_env == '' then
        vim.schedule(function()
          vim.notify('PIO: no env: found, add board first', vim.log.levels.ERROR)
        end)
        return
      end
      vim.system({ 'pio', 'project', 'metadata', '-e', M.metadata.active_env, '--json-output' }, { text = true }, function(obj)
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
        -- Error Checking: obj.code 0 means success
        if obj.code == 0 and obj.stdout then
          local ok, raw_data = pcall(vim.json.decode, obj.stdout)
          if ok and raw_data then
            local _, env = next(raw_data)
            if not env then
              return
            end
            local fallback_flags = {}
            -- 1. Process Includes
            if env.includes then
              for category, paths in pairs(env.includes) do
                -- If it's a toolchain path, use -isystem to suppress warnings
                -- and tell clangd these are standard libraries
                local flag = (category == 'toolchain') and '-isystem' or '-I'

                for _, path in ipairs(paths) do
                  table.insert(fallback_flags, flag .. path)
                end
              end
            end
            -- 2. Process Defines
            if env.defines then
              for _, define in ipairs(env.defines) do
                table.insert(fallback_flags, '-D' .. define)
              end
            end
            M.metadata = {
              driver_path = env.cc_path:match('(.*[/\\])') .. '/*' or '**',
              cc_path = env.cc_path or '',
              fallback_flags = fallback_flags,
            }
            -- M.metadata = decoded
            if callback then
              vim.schedule(callback)
            end
          else
            vim.schedule(function()
              vim.notify('PIO: Syncing Environment failed')
            end)
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
      -- Use Neovim's async system call to prevent UI freezing
      -- vim.system({ 'pio', 'project', 'config', '--json-output' }, { text = true }, function(obj)
      --   -- Error Checking: obj.code 0 means success
      --   if obj.code == 0 and obj.stdout then
      --     local ok, decoded = pcall(vim.json.decode, obj.stdout)
      --     if ok and decoded then
      --       cache = decoded
      --       vim.schedule(function()
      --         if not cache or type(cache) ~= 'table' then
      --           vim.notify('PIO: Fetching Config failed. Check platformio.ini syntax.', vim.log.levels.INFO)
      --         else
      --           vim.notify('PIO: Fetching Config successful', vim.log.levels.INFO)
      --         end
      --       end)
      --       if callback then
      --         vim.schedule(callback)
      --       end
      --       return
      --     end
      --   end
      --
      --   -- RETRY LOGIC: Handles "Error 1" (file busy) or temporary syntax errors during save
      --   if attempts > 0 then
      --     vim.defer_fn(function()
      --       execute_pio(attempts - 1)
      --     end, 500)
      --   else
      --     vim.schedule(function()
      --       if obj.code ~= 0 then
      --         vim.notify('PIO: Config Error. Check platformio.ini syntax.', vim.log.levels.WARN)
      --       end
      --     end)
      --   end
      -- end)
    end
    execute_pio(1)
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
  print(vim.inspect(M.metadata))
  return (misc.normalize_path(final))
  -- return M.metadata.driver_path
  -- return pio_info
end

-- INFO:
-- LSP HELPER: Returns the glob pattern for clangd's --query-driver
-- e.g., C:\Users\tom\.platformio\packages\toolchain-riscv32-esp\bin\*
function _G.get_pio_toolchain_pattern()
  return M.metadata.driver_path
  -- local ok_env, active_env = pcall(function()
  --   return vim.g.pio_active_env or pio_manager.get('platformio', 'default_envs')
  -- end)
  -- if not ok_env or not active_env then
  --   return '/**/bin/*'
  -- end
  --
  -- local target_env = 'env:' .. active_env
  -- local platform = pio_manager.get(target_env, 'platform')
  -- -- Determine the packages directory (Windows vs Linux/Mac home folders)
  -- local packages_dir = pio_manager.get('platformio', 'packages_dir') or (os.getenv('USERPROFILE') or os.getenv('HOME') .. '/.platformio/packages')
  --
  -- if not platform then
  --   return '/**/bin/*'
  -- end
  --
  -- -- Use pio platform show to find which toolchain packages are associated with the platform
  -- local p_handle = io.popen('pio platform show ' .. platform .. ' --json-output')
  -- if not p_handle then
  --   return '/**/bin/*'
  -- end
  -- local raw_json = p_handle:read('*all')
  -- p_handle:close()
  --
  -- local p_ok, p_data = pcall(vim.json.decode, raw_json)
  -- if not p_ok or not p_data or not p_data.packages then
  --   return '/**/bin/*'
  -- end
  --
  -- local toolchain_folder = ''
  -- for _, pkg in ipairs(p_data.packages) do
  --   -- Skip ULP (low power) toolchains and find the primary one for the architecture
  --   if pkg.name and pkg.name:find('^toolchain%-') and not pkg.name:find('ulp') then
  --     local check_path = (packages_dir .. '/' .. pkg.name):gsub('\\', '/')
  --     if vim.fn.isdirectory(check_path) == 1 then
  --       toolchain_folder = pkg.name
  --       -- Verification: Match the toolchain name against the compiler used in compile_commands.json
  --       local db_path = vim.uv.cwd() .. '/compile_commands.json'
  --       local f = io.open(db_path, 'r')
  --       if f then
  --         local head = f:read(2048) -- Read enough to find the compiler path
  --         f:close()
  --         -- If the DB mentions "riscv32-esp", we ensure we picked the matching folder
  --         if head and head:find(pkg.name:gsub('toolchain%-', '')) then
  --           break
  --         end
  --       end
  --     end
  --   end
  -- end
  --
  -- if toolchain_folder == '' then
  --   return '/**/bin/*'
  -- end
  --
  -- local final = packages_dir .. toolchain_folder
  -- print('get_pio_toolchain 5: final=' .. final)
  -- -- Normalize paths for the OS and ensure backslashes for Windows if needed
  -- return (misc.normalize_path(final))
  -- return vim.fn.has('win32') == 1 and final:gsub('/', '\\') or final
end

-- INFO:
-- FILE WATCHER: Listens for changes in platformio.ini to trigger auto-sync
-- stylua: ignore
local function start_pio_watcher()
  local platformioini = vim.uv.cwd() .. '/platformio.ini'
  if vim.fn.filereadable(platformioini) == 0 then return end

  local w = vim.uv.new_fs_event()
  if not w then return end
  w:start(
    platformioini, {},
    vim.schedule_wrap(function(err, _, events)
      if err or not events or not events.change then
        return
      end

      if debounce_timer then
        -- 1. Stop any existing timer (cancel previous "half-finished" events)
        debounce_timer:stop()

        -- 2. Start a 500ms window. Logic only runs if NO more events happen in this time.
        debounce_timer:start(
          500,
          0,
          vim.schedule_wrap(function()
            M.metadata.active_env = GetActivePioEnv()
            pio_manager.refresh(function()

              vim.schedule(function()
                boilerplate_gen([[.clangd_cmd]], vim.g.platformioRootDir)
                pio_generate_db()
                lsp.lsp_restart('clangd')
                vim.notify('PIO: Syncing Environment successful')
              end)
              -- if M.metadata.active_env then
              --   pio_generate_db()
              --   start_pio_watcher()
              -- end
              -- local board_env = pio_manager.get('platformio', 'default_envs')
              -- if board_env then
              --   vim.system({ 'pio', 'project', 'metadata', '-e', board_env, '--json-output' }, { text = true }, function(obj)
              --     -- Error Checking: obj.code 0 means success
              --     if obj.code == 0 and obj.stdout then
              --       local ok, raw_data = pcall(vim.json.decode, obj.stdout)
              --       if ok and raw_data then
              --         local _, env = next(raw_data)
              --         if not env then
              --           return
              --         end
              --         local fallback_flags = {}
              --         -- 1. Process Includes
              --         if env.includes then
              --           for category, paths in pairs(env.includes) do
              --             -- If it's a toolchain path, use -isystem to suppress warnings
              --             -- and tell clangd these are standard libraries
              --             local flag = (category == 'toolchain') and '-isystem' or '-I'
              --
              --             for _, path in ipairs(paths) do
              --               table.insert(fallback_flags, flag .. path)
              --             end
              --           end
              --         end
              --         -- 2. Process Defines
              --         if env.defines then
              --           for _, define in ipairs(env.defines) do
              --             table.insert(fallback_flags, '-D' .. define)
              --           end
              --         end
              --         M.metadata = {
              --           driver_path = env.cc_path:match('(.*[/\\])') .. '/*' or '**',
              --           cc_path = env.cc_path or '',
              --           fallback_flags = fallback_flags,
              --         }
              --         -- M.metadata = decoded
              --         vim.schedule(function()
              --           pio_generate_db()
              --           lsp.lsp_restart('clangd')
              --           vim.notify('PIO: Syncing Environment successful')
              --         end)
              --       else
              --         vim.schedule(function()
              --           vim.notify('PIO: Syncing Environment failed')
              --         end)
              --       end
              --     end
              --   end)
              -- end
            end)
          end)
        )
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

    -- if vim.fn.filereadable(vim.uv.cwd() .. '/platformio.ini') == 1 then
    -- M.metadata.active_env = GetActivePioEnv()
    pio_manager.refresh(function()
      vim.schedule(function()
        boilerplate_gen([[.clangd_cmd]], vim.g.platformioRootDir)
        pio_generate_db()
        lsp.lsp_restart('clangd')
        vim.notify('PIO: Syncing Environment successful')
      end)
      -- We check if we have data inside the refresh callback
      -- local env = pio_manager.get('platformio', 'default_envs')
      -- if M.metadata.active_env then
      --   boilerplate_gen([[.clangd_cmd]], vim.g.platformioRootDir)
      --   pio_generate_db()
      --   lsp.lsp_restart('clangd')
      --   start_pio_watcher()
      -- end
      -- pio_generate_db()
      start_pio_watcher()
    end)
    -- end
  end
end

-- local pio = require('pio_utils')
--
-- require('lspconfig').clangd.setup({
--     on_new_config = function(new_config, _)
--         if pio.data then
--             new_config.cmd = { "clangd", "--query-driver=" .. pio.data.cc_path }
--             new_config.init_options = { fallbackFlags = pio.data.fallback_flags }
--         end
--     end
-- })
return M
