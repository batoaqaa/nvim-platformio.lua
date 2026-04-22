local M = {}

local pio = require('platformio.utils.pio')
local frames = { '⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏' }
local frame_idx = 1

function M.get_pio_status()
  local meta = _G.metadata
  if not meta then
    return ''
  end

  -- Accessing meta.active_env triggers __index automatically in Lua
  local active = meta.active_env or ''
  if active == '' then
    return ''
  end

  if M.is_busy then
    local icon = frames[frame_idx]
    frame_idx = (frame_idx % #frames) + 1
    return string.format(' [ %s %s ] ', icon, active)
  end
  return string.format(' [ %s ] ', active)
end
-- _G.get_pio_status = function()
--   -- Add a manual check for the metatable if it exists
--   local val = _G.metadata and _G.metadata.active_env
--   if val and val ~= '' then
--     return ' [   ' .. val .. '] '
--   end
--   return ''
-- end
-- _G.get_pio_status = function()
--   if _G.metadata and _G.metadata.active_env ~= '' then
--     return ' [   ' .. _G.metadata.active_env .. '] '
--   end
--   return ''
-- end
-- Move the %#PioStatus# and %* outside of the curly braces
-- vim.o.statusline = '%f %m %r %= %#PioStatus#%{v:lua.get_pio_status()}%* %y %p%% %l:%c'

-- The Statusline Getter (used by the UI)
-- function M.get_pio_status()
--   -- Using pcall ensures that if 'require' or 'metadata' fails,
--   -- the statusline just shows nothing instead of throwing an error.
--   local ok, status = pcall(function()
--     if _G.metadata and _G.metadata.active_env and _G.metadata.active_env ~= '' then
--       return string.format(' [ %s ] ', _G.metadata.active_env)
--     end
--     return ''
--   end)
--   return ok and status or ''
-- end
-------------------------------------------------------------------------------------------------------
local last_saved_hash = ''
local config_path = vim.fs.joinpath(vim.uv.cwd(), '.project_config.json')

--INFO:
-- 1. Internal State & Defaults
local _pio_metadata = {
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
  __index = _pio_metadata,
  __newindex = function(_, key, value)
    if _pio_metadata[key] == value then
      return
    end -- Performance check
    _pio_metadata[key] = value

    -- Trigger background actions
    vim.schedule(function()
      M.save_project_config(true)
      if key == 'toolchain_root' then
        vim.notify('Env: ' .. value, vim.log.levels.INFO, { title = 'PlatformIO', render = 'compact' })
        pcall(function()
          if _pio_metadata.dbTrigger then
            vim.notify('Env: dbTrigger', vim.log.levels.INFO, { title = 'PlatformIO', render = 'compact' })
            local dbFix = pio.compile_commandsFix
            dbFix()
            _pio_metadata.dbTrigger = false
          else
            local LspRestart = require('platformio.utils.lsp').lsp_restart
            LspRestart('clangd')
            vim.notify('Env: LspRestart', vim.log.levels.INFO, { title = 'PlatformIO', render = 'compact' })
          end
        end)
      elseif key == 'active_env' then
        -- Force global statusline so it doesn't get pushed around by Trouble or splits
        vim.o.laststatus = 3
      end
    end)
  end,
})

--INFO:
-- 3. Save Logic (Uses sha256 for stability)
function M.save_project_config(quiet)
  if vim.fn.filereadable('platformio.ini') == 0 then
    return
  end
  -- local json_data = pio.pretty_json(_pio_metadata)
  local ok, json_data = pcall(vim.json.encode, _pio_metadata)
  if not ok then
    print('Error encoding JSON: ' .. json_data)
    return
  end
  local pretty_json = vim.misc.pretty_print(json_data)
  local current_hash = vim.fn.sha256(pretty_json)

  --   file:write(pio.jsonFormat(json_data))
  if current_hash ~= last_saved_hash then
    -- local status = vim.fn.writefile({ json_data }, config_path)
    local status, _ = vim.misc.writeFile({ json_data }, config_path)
    if status == 0 then
      last_saved_hash = current_hash
      if not quiet then
        vim.notify('Config synced', vim.log.levels.INFO, { title = 'PlatformIO' })
      end
    else
      vim.notify('Could not open file for writing')
    end
  end
end

--INFO:
-- 4. Load Logic (Populates proxy safely)
function M.load_project_config()
  -- if vim.fn.filereadable(config_path) == 1 then
  --   local file = io.open(config_path, 'r')
  --   if file then
  --     local content = file:read('*a')
  --     file:close()
  --     local ok, decoded = pcall(vim.json.decode, content)
  --     if ok and type(decoded) == 'table' then
  --       -- We update _pio_metadata directly to avoid triggering
  --       -- 50+ notifications/restarts during the initial load loop
  --       for k, v in pairs(decoded) do
  --         _pio_metadata[k] = v
  --       end
  --       last_saved_hash = vim.fn.sha256(content)
  --       return
  --     end
  --   end
  -- end
  if vim.fn.filereadable(config_path) == 1 then
    local json_data = vim.misc.readFile(config_path)
    if json_data then
      local ok, table_data = pcall(vim.json.decode, json_data)
      if ok and type(table_data) == 'table' then
        -- We update _pio_metadata directly to avoid triggering
        -- 50+ notifications/restarts during the initial load loop
        for k, v in pairs(table_data) do
          _pio_metadata[k] = v
        end
        last_saved_hash = vim.fn.sha256(json_data)
        return
      end
    end
  end
  -- If no file, initialize hash with defaults
  last_saved_hash = vim.fn.sha256(vim.json.encode(_pio_metadata))
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
