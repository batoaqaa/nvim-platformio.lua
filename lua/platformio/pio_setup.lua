local misc = require('platformio.utils.misc')
--1. The Core PIO Manager & Generic Extractor
--This manages the data cache and navigates your specific nested-list JSON structure.
--- stylua: ignore
local pio_manager = (function()
  local cache = nil

  -- Generic extractor for nested structure: { { "name", { {"k","v"}, ... } }, ... }
  local function find_in_data(data, section_name, key_name)
    if not data or type(data) ~= 'table' then
      return nil
    end
    for _, section in ipairs(data) do
      if type(section) == 'table' and #section >= 2 then
        local section_id = section[1]
        local section_body = section[2]

        -- Match specific section or fallback to first "env:" found
        local match_section = (not section_name and type(section_id) == 'string' and section_id:find('^env:')) or (section_id == section_name)
        if match_section and type(section_body) == 'table' then
          for _, kv in ipairs(section_body) do
            if type(kv) == 'table' and #kv >= 2 and kv[1] == key_name then
              return kv[2]
            end
          end
        end
      end
    end
    return nil
  end

  local function refresh(callback)
    -- Using vim.system to detect if the command exists
    vim.system({ 'pio', 'project', 'config', '--json-output' }, { text = true }, function(obj)
      if obj.code == 0 then
        local ok, decoded = pcall(vim.json.decode, obj.stdout)
        if ok and decoded then
          cache = decoded
          if callback then
            vim.schedule(callback)
          end
        end
      else
        -- Schedule notification to avoid error in the system callback thread
        vim.schedule(function()
          if obj.code == 127 then
            vim.notify("PIO Manager: 'pio' command not found. Ensure PlatformIO Core is installed.", vim.log.levels.ERROR)
          else
            vim.notify('PIO Manager: Failed to fetch config (Error ' .. obj.code .. ')', vim.log.levels.WARN)
          end
        end)
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

--2. Generic Toolchain & Sysroot Logic. These functions identify where the compiler and its C++ headers live.
-- Gets the compiler glob for clangd --query-driver
function _G.get_pio_toolchain_pattern()
  print('toolchain 0:')
  local active_env = vim.g.pio_active_env or pio_manager.get('platformio', 'default_envs')

  print('toolchain 1:')
  -- Handle default_envs being a list/table
  if type(active_env) == 'table' then
    active_env = active_env[1]
  end
  print('toolchain 2:')
  local target_env = active_env and ('env:' .. active_env) or nil
  local platform = pio_manager.get(target_env, 'platform')
  local packages_dir = pio_manager.get('platformio', 'packages_dir') or (os.getenv('HOME') or os.getenv('USERPROFILE') .. '/.platformio/packages')
  if not platform then
    return '/**/bin/*'
  end

  print('toolchain 3:')
  -- Sync call for toolchain name
  local p_handle = io.popen('pio platform show ' .. platform .. ' --json-output')
  if not p_handle then
    return '/**/bin/*'
  end

  print('toolchain 4:')
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
  print('toolchain 5:')
  -- local final = (packages_dir:gsub('\\', '/') .. arch_glob):gsub('//+', '/')
  local final = packages_dir .. arch_glob
  return (misc.normalize_path(final))
  -- return vim.fn.has('win32') == 1 and final:gsub('/', '\\') or final
end

--3. Patches compile_commands.json with --sysroot to fix <algorithm>
-- Helper to generate the compilation database
local function pio_generate_db()
  -- This runs in the background so it doesn't freeze Neovim
  vim.system({ 'pio', 'run', '-t', 'compiledb' }, { text = true }, function(obj)
    if obj.code ~= 0 then
      return
    end
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
      if not f then
        return
      end
      local content = f:read('*all')
      f:close()

      -- patch sysroot
      local patched = content:gsub('("-i")', '"--sysroot=' .. sysroot_path .. '", %1')
      local out = io.open(db_path, 'w')
      if out then
        out:write(patched)
        out:close()
        vim.schedule(function()
          vim.notify('PIO: DB & Sysroot Patched')
        end)
      end
    end
  end)
end

--4. Automation & File Watcher
--This handles the background synchronization when you save your project.
local function start_pio_watcher()
  local path = vim.fn.getcwd() .. '/platformio.ini'
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
      if err then
        vim.notify('PIO Auto-Sync error', vim.log.levels.ERROR)
        w:stop()
        return
      end
      if events.change then
        pio_manager.refresh(function()
          pio_generate_db()
          vim.cmd('LspRestart clangd')
          vim.notify('PIO Auto-Sync Complete', vim.log.levels.INFO)
        end)
      end
    end)
  )
end

-- Exported setup function
return {
  init = function()
    if vim.fn.filereadable(vim.fn.getcwd() .. '/platformio.ini') == 1 then
      pio_manager.refresh(function()
        pio_generate_db()
        start_pio_watcher()
      end)
    end
  end,
}

-- -- init.lua
--
-- -- 1. Load the PIO logic
-- local pio = require("pio_setup")
-- pio.init()
--
-- -- 2. Your LSP Setup
-- require('lspconfig').clangd.setup({
--     cmd = {
--         "clangd",
--         "--background-index",
--         -- It calls the global function defined in pio_setup.lua
--         "--query-driver=" .. _G.get_pio_toolchain_pattern(),
--         "--header-insertion=never"
--     },
-- })
