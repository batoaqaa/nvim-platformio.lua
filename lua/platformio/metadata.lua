-- 1. Initialize Global Table immediately (Prevents nil errors)
_G.metadata = _G.metadata
  or {
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

local M = {}
local last_saved_hash = ''
local config_path = vim.fn.getcwd() .. '/.project_config.json'

-- Helper: Performance-proof hashing using built-in Vimscript (never nil)
local function get_safe_hash(data)
  return vim.fn.sha256(data)
end

-- 2. Self-Healing Load & Auto-Create
function M.load_project_config()
  local success = false

  if vim.fn.filereadable(config_path) == 1 then
    local file = io.open(config_path, 'r')
    if file then
      local content = file:read('*a')
      file:close()
      local ok, decoded = pcall(vim.json.decode, content)
      if ok and type(decoded) == 'table' then
        _G.metadata = decoded
        last_saved_hash = get_safe_hash(content)
        success = true
      end
    end
  end

  -- If file is missing or corrupted, initialize and force-save
  if not success then
    -- Use the global table we initialized at the top
    local encoded = vim.json.encode(_G.metadata)
    local file = io.open(config_path, 'w')
    if file then
      file:write(encoded)
      file:close()
      last_saved_hash = get_safe_hash(encoded)
      if vim.fn.filereadable('platformio.ini') == 1 then
        vim.notify('New project config created', vim.log.levels.INFO, { title = 'PlatformIO' })
      end
    end
  end
end

-- 3. Performance-Proof Save (Hash Check)
function M.save_project_config(quiet)
  if not _G.metadata or vim.fn.filereadable('platformio.ini') == 0 then
    return
  end

  local current_data = vim.json.encode(_G.metadata)
  local current_hash = get_safe_hash(current_data)

  -- Only write if data actually changed since last load/save
  if current_hash ~= last_saved_hash then
    local file = io.open(config_path, 'w')
    if file then
      file:write(current_data)
      file:close()
      last_saved_hash = current_hash

      if not quiet then
        vim.notify('Settings synced to disk', vim.log.levels.INFO, {
          title = 'PlatformIO',
          render = 'compact',
        })
      end
    end
  end
end

-- 4. Fixed Status Function (Fixes line 472 error)
function M.show_status()
  -- Ensure we access the table, NOT call it
  local meta = _G.metadata
  local env = meta.active_env ~= '' and meta.active_env or 'None'

  vim.notify(string.format('Environment: %s\nTarget: %s', env, meta.triplet or 'Unknown'), vim.log.levels.INFO, { title = 'PlatformIO Status' })
end

local pio_group = vim.api.nvim_create_augroup('PioPersist', { clear = true })
vim.api.nvim_create_autocmd({ 'BufWritePost', 'VimLeavePre' }, {
  group = pio_group,
  callback = function()
    -- Pass 'true' to save silently in the background
    M.save_project_config(true)
  end,
  desc = 'Automatically save PlatformIO project metadata',
})

-- 5. Environment Switcher UI
function M.switch_env()
  -- 1. Safety check for metadata
  if not _G.metadata.envs or next(_G.metadata.envs) == nil then
    vim.notify('No environments found. Please refresh PlatformIO data.', vim.log.levels.WARN)
    return
  end

  -- 2. Prepare the list of environments
  local options = vim.tbl_keys(_G.metadata.envs)
  table.sort(options)

  -- 3. Open the selection UI
  vim.ui.select(options, {
    prompt = 'Select PlatformIO Environment:',
    format_item = function(item)
      local icon = (item == _G.metadata.active_env) and '   ' or '○ '
      return icon .. item
    end,
  }, function(choice)
    if choice then
      -- Update active environment
      _G.metadata.active_env = choice

      -- 4. Persist change to disk (silently)
      M.save_project_config(true)

      -- 5. Notify the user with the new board info
      local board = _G.metadata.envs[choice].board or 'unknown'
      vim.notify(string.format('Switched to %s\nBoard: %s', choice, board), vim.log.levels.INFO, { title = 'PlatformIO' })

      -- 6. RESTART LSP (Crucial for refreshing includes/defines)
      -- We wrap in pcall in case clangd isn't actually running yet
      pcall(function()
        vim.cmd('LspRestart clangd')
      end)
    end
  end)
end

-- -- Force LSP to pick up new fallbackFlags/defines
-- local lspTools = require('platformio.lsp.tools')
-- lspTools.lsp_restart()
-- 6. Keybindings
-- Switch Environment
vim.keymap.set('n', '<leader>\\e', function()
  M.switch_env()
end, { desc = 'Switch [E]nvironment' })

-- write
vim.keymap.set('n', '<leader>\\w', function()
  M.save_project_config(false)
end, { desc = 'config [W]rite' })

-- Manual Status Check
vim.keymap.set('n', '<leader>\\s', function()
  M.show_status()
end, { desc = 'config [S]tatus' })

return M
