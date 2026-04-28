local M = {}

-------------------------------------------------------------------------------------------------------
local last_saved_hash = ''

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
  includes_build = {},
  includes_compatlib = {},
  includes_toolchain = {},
  cc_path = '',
  cc_flags = {},
  cxx_path = '',
  cxx_flags = {},
  gdb_path = '',
  defines = {},
  triplet = '',
  toolchain_root = '',
  sysroot = '',
  fallbackFlags = {},
  dbTrigger = false,
  last_projectChecksum = '', -- Used to track changes
}
-- 2. The Reactive Proxy Wrapper
-- Any write to _G.metadata.key = val triggers this logic
_G.metadata = setmetatable({}, {
  __index = _pio_metadata,
  __newindex = function(_, key, value)
    if _pio_metadata[key] == value then
      -- print('Value is identical, returning...') -- DEBUG LINE
      return
    end -- Performance check
    -- print('Newindex attempt for: ' .. tostring(key)) -- DEBUG LINE
    _pio_metadata[key] = value

    -- Trigger background actions
    vim.schedule(function()
      -- M.save_project_config(true)
      if key == 'toolchain_root' then
        local binPath = value .. '/bin'
        local sep = (vim.fn.has('win32') == 1 and ';' or ':')
        vim.env.PATH = binPath .. sep .. vim.env.PATH
        vim.notify('Env: ' .. binPath .. ' added to path', vim.log.levels.INFO, { title = 'PlatformIO', render = 'compact' })
        -- vim.notify('Env: ' .. value, vim.log.levels.INFO, { title = 'PlatformIO', render = 'compact' })
        -- pcall(function()
        --   if _pio_metadata.dbTrigger then
        --     vim.notify('Env: dbTrigger', vim.log.levels.INFO, { title = 'PlatformIO', render = 'compact' })
        --     local dbFix = pio.compile_commandsFix
        --     local ok, _ = pcall(dbFix)
        --     if not ok then
        --       print('Env: dbTrigger, fail to call dbFix')
        --     end
        --     -- dbFix()
        --     _pio_metadata.dbTrigger = false
        --   else
        --     local LspRestart = require('platformio.lspConfigConfig.tools').lsp_restart
        --     LspRestart('clangd')
        --     vim.notify('Env: LspRestart', vim.log.levels.INFO, { title = 'PlatformIO', render = 'compact' })
        --   end
        -- end)
      elseif key == 'last_projectChecksum' then
      elseif key == 'active_env' then
      end
    end)
  end,
})

local config_path = vim.fs.joinpath(vim.uv.cwd(), '.project_config.json')
-- -- Add this temporary line in a file where you are coding:
-- ---@type platformio.utils.misc
-- local misc = vim.misc
--INFO:
-- 3. Save Logic (Uses sha256 for stability)
function M.save_project_config(quiet)
  -- 1. Generate the formatted string directly, pretty_print already returns a string!
  local ok, pretty_json = pcall(vim.misc.pretty_print, _pio_metadata)

  if not ok or not pretty_json then
    print('Error formatting metadata')
    return
  end

  local current_hash = vim.fn.sha256(pretty_json)

  -- 2. Only write if the content actually changed
  if current_hash ~= last_saved_hash then
    local status, err = vim.misc.writeFile(config_path, pretty_json, {})

    if status then
      last_saved_hash = current_hash
      if not quiet then
        vim.notify('Config synced', vim.log.levels.INFO, { title = 'PlatformIO' })
      end
    else
      vim.notify('Write failed: ' .. (err or 'unknown error'), vim.log.levels.ERROR)
    end
  end
end

-- function M.save_project_config(quiet)
--   if vim.fn.filereadable('platformio.ini') == 0 then
--     return
--   end
--   -- local json_data = pio.pretty_json(_pio_metadata)
--   local ok, json_data = pcall(vim.json.encode, _pio_metadata)
--   if not ok then
--     print('Error encoding JSON: ' .. json_data)
--     return
--   end
--   local pretty_json = vim.misc.pretty_print(json_data)
--   local current_hash = vim.fn.sha256(pretty_json)
--
--   --   file:write(pio.jsonFormat(json_data))
--   if current_hash ~= last_saved_hash then
--     -- local status = vim.fn.writefile({ json_data }, config_path)
--     local status, _ = vim.misc.writeFile(json_data, config_path, {})
--     if status == 0 then
--       last_saved_hash = current_hash
--       if not quiet then
--         vim.notify('Config synced', vim.log.levels.INFO, { title = 'PlatformIO' })
--       end
--     else
--       vim.notify('Could not open file for writing')
--     end
--   end
-- end

--INFO:
-- 4. Load Logic (Populates proxy safely)
function M.load_project_config()
  if vim.fn.filereadable(config_path) == 1 then
    local _, json_data = vim.misc.readFile(config_path)
    if json_data then
      local ok, table_data = pcall(vim.json.decode, json_data)
      if ok and type(table_data) == 'table' then
        -- We update _pio_metadata directly to avoid triggering
        -- 50+ notifications/restarts during the initial load loop
        for k, v in pairs(table_data) do
          _G.metadata[k] = v
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
