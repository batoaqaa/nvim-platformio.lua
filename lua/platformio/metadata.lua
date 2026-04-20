local M = {}

_G.get_pio_status = function()
  if _G.metadata and _G.metadata.active_env ~= '' then
    return ' [   ' .. _G.metadata.active_env .. '] '
  end
  return ''
end
-- Move the %#PioStatus# and %* outside of the curly braces
vim.o.statusline = '%f %m %r %= %#PioStatus#%{v:lua._G.get_pio_status()}%* %y %p%% %l:%c'

-- 1. Internal State & Defaults
local last_saved_hash = ''
local config_path = vim.fs.joinpath(vim.uv.cwd(), '.project_config.json')

local _raw_metadata = {
  isBusy = false,
  envs = {},
  active_env = '',
  default_envs = {},
  core_dir = '',
  packages_dir = '',
  platforms_dir = '',
  query_driver = '',
  cc_compiler = '',
  triplet = '',
  toolchain_root = '',
  sysroot = '',
  fallbackFlags = {},
  dbTrigger = false,
}

-- 2. The Reactive Proxy Wrapper
-- Any write to _G.metadata.key = val triggers this logic
_G.metadata = setmetatable({}, {
  __index = _raw_metadata,
  __newindex = function(_, key, value)
    if _raw_metadata[key] == value then
      return
    end -- Performance check
    _raw_metadata[key] = value

    -- Trigger background actions
    vim.schedule(function()
      M.save_project_config(true)
      if key == 'toolchain_root' then
        vim.notify('Env: ' .. value, vim.log.levels.INFO, { title = 'PlatformIO', render = 'compact' })
        pcall(function()
          if _raw_metadata.dbTrigger then
            vim.notify('Env: dbTrigger', vim.log.levels.INFO, { title = 'PlatformIO', render = 'compact' })
            local dbFix = require('platformio.utils.pio').compile_commandsFix
            dbFix()
            _raw_metadata.dbTrigger = false
          else
            local LspRestart = require('platformio.utils.lsp').lsp_restart
            LspRestart('clangd')
            vim.notify('Env: LspRestart', vim.log.levels.INFO, { title = 'PlatformIO', render = 'compact' })
          end
        end)
      end
      -- if key == 'active_env' then
      --   vim.notify('Env: ' .. value, vim.log.levels.INFO, { title = 'PlatformIO', render = 'compact' })
      --   pcall(function()
      --     vim.cmd('LspRestart clangd')
      --   end)
      -- end
    end)
  end,
})

-- 3. Save Logic (Uses sha256 for stability)
function M.save_project_config(quiet)
  if vim.fn.filereadable('platformio.ini') == 0 then
    return
  end

  local current_data = vim.json.encode(_raw_metadata)
  local current_hash = vim.fn.sha256(current_data)

  if current_hash ~= last_saved_hash then
    local file = io.open(config_path, 'w')
    if file then
      file:write(current_data)
      file:close()
      last_saved_hash = current_hash
      if not quiet then
        vim.notify('Config synced', vim.log.levels.INFO, { title = 'PlatformIO' })
      end
    end
  end
end

-- 4. Load Logic (Populates proxy safely)
function M.load_project_config()
  if vim.fn.filereadable(config_path) == 1 then
    local file = io.open(config_path, 'r')
    if file then
      local content = file:read('*a')
      file:close()
      local ok, decoded = pcall(vim.json.decode, content)
      if ok and type(decoded) == 'table' then
        -- We update _raw_metadata directly to avoid triggering
        -- 50+ notifications/restarts during the initial load loop
        for k, v in pairs(decoded) do
          _raw_metadata[k] = v
        end
        last_saved_hash = vim.fn.sha256(content)
        return
      end
    end
  end
  -- If no file, initialize hash with defaults
  last_saved_hash = vim.fn.sha256(vim.json.encode(_raw_metadata))
end

-- 5. Helper for ToggleTerm / Commands
function M.run_command(cmd_str)
  -- Mute watcher logic would go here if needed
  require('toggleterm').exec(cmd_str)
end

-- 6. Initialization
M.load_project_config()

-- Auto-save on exit even if no manual changes were made
vim.api.nvim_create_autocmd('VimLeavePre', {
  callback = function()
    M.save_project_config(true)
  end,
})

return M
