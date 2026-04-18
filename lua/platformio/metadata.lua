-- -- Global metadata initialization
-- Load the PIO setup logic
-- if not _G.metadata then
--   _G.metadata = {
--     envs = {},
--     active_env = '',
--     default_envs = {},
--     core_dir = '',
--     packages_dir = '',
--     platforms_dir = '',
--     query_driver = '',
--     cc_compiler = '',
--     triplet = '',
--     toolchain = '',
--     sysroot = '',
--     fallbackFlags = {},
--   }
-- end
-- _G.metadata = _G.metadata
--   or {
--     envs = {},
--     active_env = '',
--     default_envs = {},
--     core_dir = '',
--     packages_dir = '',
--     platforms_dir = '',
--     query_driver = '',
--     cc_compiler = '',
--     triplet = '',
--     toolchain = '',
--     sysroot = '',
--     fallbackFlags = {},
--   }

local M = {}
local last_saved_hash = nil
local config_path = vim.fn.getcwd() .. '/.pioConfig.json'

-- This function ensures metadata is NEVER nil when you call it
local function get_meta()
  if not _G.metadata then
    _G.metadata = {
      envs = {},
      active_env = '',
      default_envs = {},
      core_dir = '',
      packages_dir = '',
      platforms_dir = '',
      query_driver = '',
      cc_compiler = '',
      triplet = '',
      toolchain = '',
      sysroot = '',
      fallbackFlags = {},
    }
  end
  -- return _G.metadata
end

-- 1. Optimized Save Function
function M.save_project_config(quiet)
  if not _G.metadata or vim.fn.filereadable('platformio.ini') == 0 then
    return
  end

  local current_data = vim.json.encode(_G.metadata)
  local current_hash = vim.hash(current_data) -- Inline hashing

  -- Only write to disk if data actually changed
  if current_hash ~= last_saved_hash then
    local file = io.open(config_path, 'w')
    if file then
      file:write(current_data)
      file:close()
      last_saved_hash = current_hash

      if not quiet then
        vim.notify('Project settings synced to disk', vim.log.levels.INFO, {
          title = 'PlatformIO',
          render = 'compact',
        })
      end
    end
  end
end

-- 2. Robust Load Function (Startup)
function M.load_project_config()
  if vim.fn.filereadable(config_path) == 1 then
    local file = io.open(config_path, 'r')
    if file then
      local content = file:read('*a')
      file:close()

      local ok, decoded = pcall(vim.json.decode, content)
      if ok and decoded then
        _G.metadata = decoded
        last_saved_hash = vim.hash(content)
        vim.notify('Environment: ' .. (_G.metadata.active_env or 'None'), vim.log.levels.INFO, { title = 'PlatformIO: .pioCongig.json Loaded' })
      else
        get_meta()
        vim.notify('Environment: ' .. (_G.metadata.active_env or 'None'), vim.log.levels.INFO, { title = 'PlatformIO: defautl Loaded' })
      end
    else
      get_meta()
      vim.notify('Environment: ' .. (_G.metadata.active_env or 'None'), vim.log.levels.INFO, { title = 'PlatformIO: defautl Loaded' })
    end
  end
end

-- 3. Environment Switcher UI
function M.switch_env()
  if not _G.metadata.envs or next(_G.metadata.envs) == nil then
    vim.notify('No environments found. Run PlatformIO Refresh first.', vim.log.levels.WARN)
    return
  end

  local options = vim.tbl_keys(_G.metadata.envs)
  table.sort(options)

  vim.ui.select(options, {
    prompt = 'Select PlatformIO Environment:',
    format_item = function(item)
      local indicator = (item == _G.metadata.active_env) and '● ' or '○ '
      return indicator .. item
    end,
  }, function(choice)
    if choice then
      _G.metadata.active_env = choice
      -- Save immediately on user selection
      M.save_project_config(false)
      -- Force LSP to pick up new fallbackFlags/defines
      vim.cmd('LspRestart clangd')
    end
  end)
end

return M
