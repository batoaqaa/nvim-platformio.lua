local M = {}
local last_saved_hash = nil
local config_path = vim.fn.getcwd() .. '/.pioConfig.json'

-- -- Global metadata initialization
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

local default_metadata = {
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

-- 1. Optimized Save Function

-- Performance-proof: Uses guaranteed Vimscript sha256 via Lua bridge
local function get_safe_hash(data)
  -- sha256 is built into Neovim's core and never nil
  return vim.fn.sha256(data)
end

function M.save_project_config(quiet)
  if not _G.metadata or vim.fn.filereadable('platformio.ini') == 0 then
    return
  end

  local current_data = vim.json.encode(_G.metadata)
  local current_hash = get_safe_hash(current_data)

  -- Only write if data actually changed
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
  local path = vim.fn.getcwd() .. '/.project_config.json'
  local success = false

  -- 1. Try to read existing file
  if vim.fn.filereadable(path) == 1 then
    local file = io.open(path, 'r')
    if file then
      local content = file:read('*a')
      file:close()
      local ok, decoded = pcall(vim.json.decode, content)

      if ok and type(decoded) == 'table' then
        _G.metadata = decoded
        last_saved_hash = vim.fn.sha256(content)
        success = true
      end
    end
  end

  -- 2. If no file OR read failed, initialize defaults AND save to disk
  if not success then
    -- Use vim.deepcopy to prevent reference bugs
    _G.metadata = vim.deepcopy(default_metadata)

    -- Immediately persist the defaults so the file exists
    local encoded = vim.json.encode(_G.metadata)
    local file = io.open(path, 'w')
    if file then
      file:write(encoded)
      file:close()
      last_saved_hash = vim.fn.sha256(encoded)

      -- Only notify if we are actually in a PlatformIO project
      if vim.fn.filereadable('platformio.ini') == 1 then
        vim.notify('Created new .project_config.json', vim.log.levels.INFO, { title = 'PlatformIO' })
      end
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
