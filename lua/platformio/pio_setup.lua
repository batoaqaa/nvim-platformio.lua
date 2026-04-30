M = {}

-- local lsp_restart = require('platformio.lspConfig.tools').lsp_restart
local boilerplate = require('platformio.boilerplate')
local boilerplate_gen = boilerplate.boilerplate_gen



-- local debounce_timer = vim.uv.new_timer()
-- =============================================================================
-- stylua: ignore
function M.pio_refresh(callback, from)
  local msg = (type(from)=='string' and from ~= '') and from or 'PIO: '
  vim.notify(msg ..'Config sync ...', vim.log.levels.INFO)

  local function on_done(active_env)
    if active_env then
      vim.pio.fetch_metadata(callback, active_env, from, 1)
    end
  end
  vim.pio.fetch_config(on_done, from)
end

-- =============================================================================
-- INFO:
-- 1. Helper: Unified hashing for change detection
local function get_hash(path)
  if vim.fn.filereadable(path) == 0 then
    return nil
  end
  -- local ok, data = pcall(vim.fn.readfile, path) -- readfile is safer than io.open
  -- return ok and vim.fn.sha256(table.concat(data, '\n')) or nil
  local ok, data = vim.misc.readFile(path) -- readfile is safer than io.open
  return (ok and type(data) == 'string' and data ~= '') and vim.fn.sha256(data) or ''
end

-- =============================================================================
-- stylua: ignore
--INFO:
-- 1.run_compiledb
function M.run_compiledb(target)
  -- 1. Prevent overlapping builds
  if target.isBusy then return end
  target.isBusy = true
  _G.metadata.isBusy = true


  -- local pio = require('platformio.utils.pio')
  -- pio.run_sequence({
  --   cmnds = {
  --     'pio run -t compiledb -e ' .. vim.misc.get_active__env(),
  --   },
  --   cb = function (result)
  --     pio.handlePiodb(target, result)
  --   end
  -- })

  local env = vim.misc.get_active__env()
  -- if env and env ~= '' then
    vim.notify('PIO platformio.ini change: update ...', vim.log.levels.INFO, { title = 'PlatformIO' })
    -- vim.schedule(function()
    vim.system({ 'pio', 'run', '-t', 'compiledb', '-s', '-e', env }, { text = true }, function(obj)
      -- vim.system({ 'pio', 'run', '-t', 'compiledb' }, { detach = true, text = true }, function(obj)
      vim.schedule(function()
        target.isBusy = false

        if obj.code == 0 then
          -- vim.notify('DB Updated Successfully', vim.log.levels.INFO, { title = 'PlatformIO' })
          -- Trigger refresh (LSP restart, etc.)
          -- vim.schedule(function ()
          -- M.pio_refresh(function()
          vim.notify('PIO platformio.ini change: Update Success', vim.log.levels.INFO, { title = 'PlatformIO' })
          -- end, 'PIO platformio.ini  change: ')
          -- end)
        else
          local err = (obj.stderr and obj.stderr ~= '') and obj.stderr or 'Check PIO logs'
          vim.notify('PIO Build Failed: ' .. err, vim.log.levels.ERROR, { title = 'PlatformIO' })
        end
        _G.metadata.isBusy = false
      end)
    end)
    -- end)
  -- end
end

-- =============================================================================
--INFO:
-- Ensure this is at the TOP of your file, outside any functions
local uv = vim.uv or vim.loop
M.watcher_handles = {}
local debounce_timer = uv.new_timer()
local last_mtime = 0

-- =============================================================================
-- stylua: ignore
--INFO:
-- 2.stop_watchers 
function M.stop_watchers()
  if not M.watcher_handles or (type(M.watcher_handles) ~= 'table') then M.watcher_handles = {} return end

  for _, handle in ipairs(M.watcher_handles) do
    if handle and not handle:is_closing() then
      handle:stop()
      handle:close() -- CRITICAL: This allows Neovim to quit instantly
    end
  end
  M.watcher_handles = {}
end

-- =============================================================================
-- stylua: ignore
--INFO:
-- 3.watcher cleanup
function M.cleanup()
  M.stop_watchers()
  if debounce_timer and not debounce_timer:is_closing() then
    debounce_timer:stop()
    debounce_timer:close()
  end
end
-- =============================================================================
--INFO:
-- Force cleanup when leaving Neovim to prevent :qa lag
vim.api.nvim_create_autocmd('VimLeavePre', {
  callback = function()
    M.cleanup()
  end,
})

-- stylua: ignore
-- 3. MAIN WATCHER: Efficient Folder Monitoring
local function watch_file(target, callback)
  local folder_path = target.path:match('(.*[/\\])')
  local target_filename = target.path:match('[^/\\]+$')

  local handle = uv.new_fs_event()
  if not handle then return end

  handle:start(folder_path, {}, function(err, filename)
    if err then return end

    -- Early Exit Filters
    if target.isBusy or (filename and filename ~= target_filename) then return end

    -- local f = io.open(target.path, "r")
    -- if f then f:close()
    -- else return end -- Not readable (protected, locked, or missing)

    if not uv.fs_access(target.path, 'R') then return end

    -- Protected Execution
    local ok, result = pcall(function()
      local stat = uv.fs_stat(target.path)
      if not stat or stat.mtime.sec <= last_mtime then return end

      vim.schedule(function()
        if debounce_timer then
          debounce_timer:stop()
          local retries = 0
          local max_retries = 15 -- 15 seconds max wait

          local function attempt_callback()
            -- Check if busy (checks both local M and global _G)
            if target.isBusy then --or (_G.metadata and _G.metadata.isBusy) then
              if retries < max_retries then
                retries = retries + 1
                debounce_timer:start(1000, 0, vim.schedule_wrap(attempt_callback))
                return
              end
              vim.notify('PIO: Sync timed out (busy)', vim.log.levels.ERROR)
              return
            end

            -- Final validation & run
            local final_stat = uv.fs_stat(target.path)
            if final_stat and final_stat.mtime.sec > last_mtime then
              last_mtime = final_stat.mtime.sec
              callback(target)
            end
          end

          debounce_timer:start(1000, 0, vim.schedule_wrap(attempt_callback))
        end
      end)
    end)

    if not ok then
      vim.schedule(function()
        vim.notify('PIO Watcher Error: ' .. tostring(result), vim.log.levels.ERROR)
      end)
    end
  end)

  table.insert(M.watcher_handles, handle)
  return handle
end
-- =============================================================================
-- stylua: ignore
--INFO:
-- 4. watch_file
-- stylua: ignore
-- local function watch_file(target, callback)
--   local handle = uv.new_fs_poll()
--   if not handle then return end
--
--   -- handle:start(target.path, 1000, function(err, stat)
--   --   if err or not stat then return end
--   --
--   --   if debounce_timer then
--   --     debounce_timer:stop()
--   --     -- Define the logic in a local variable so it can "call itself" for retries
--   --     local function attempt_callback()
--   --       if target.isBusy then
--   --         -- Retry in 1000ms if still busy
--   --         debounce_timer:start(1500, 0, vim.schedule_wrap(attempt_callback))
--   --         return
--   --       end
--   --
--   --       local filestat = uv.fs_stat(target.path)
--   --       if filestat and filestat.type == 'file' then callback(target) end
--   --     end
--   --     -- Initial start
--   --     debounce_timer:start(1500, 0, vim.schedule_wrap(attempt_callback))
--   --   end
--   -- end)
--
--   -- Poll every 1000ms. This is light on CPU and ignores "save noise".
--   -- handle:start(target.path, 1000, function(err, stat)
--   --   -- if err or not stat or (target and target.isBusy) then return end
--   --   if err or not stat then return end
--   --
--   --   -- 2. Debounce: Reset the timer on every event
--   --   -- Only after 500ms of "silence" will the actual callback run
--   --   if debounce_timer then
--   --     -- Stop any existing timer to "debounce"
--   --     if debounce_timer:is_active() then debounce_timer:stop() end
--   --     debounce_timer:start(500, 0, vim.schedule_wrap(function()
--   --       -- vim.schedule(function ()
--   --         local filestat = uv.fs_stat(target.path)
--   --         if filestat and filestat.type == 'file' then
--   --           callback(target)
--   --         end
--   --         -- if vim.loop.fs_stat(target.path) then callback(target) end
--   --       -- end)
--   --     end))
--   --   end
--   -- end)
--
--   table.insert(M.watcher_handles, handle)
--   return handle
-- end


-- =============================================================================
-- stylua: ignore
--INFO:
-- 5. start_watches
function M.start_watchers()
  -- Clean up any existing watchers first to prevent duplicates
  if next(M.watcher_handles) then M.stop_watchers() end

  local project_root = vim.uv.cwd() -- Use dynamic CWD instead of hardcoded path

  local targets = {
    { -- watcher for platformio.ini
      name = 'ini',
      isBusy = false,
      last_hash = '',
      path = vim.misc.joinPath(project_root, 'platformio.ini'),
      cb = function(self)
        if self.isBusy then return end
        local new_hash = get_hash(self.path) or ''
        if new_hash and new_hash ~= self.last_hash then
          self.last_hash = new_hash
          vim.schedule(function()
            M.run_compiledb(self) -- Smart: Auto-update DB if config changes
          end)
        end
      end,
    },
    { -- watcher for ./.pio/build/projct.checksum
      name = 'checksum',
      isBusy = false,
      path = vim.misc.joinPath(project_root, '.pio', 'build', 'project.checksum'), --checksum_path
      cb = function(self)
        if self.isBusy then return end
        local ok, current_checksum = vim.misc.readFile(self.path)
        -- Check if we should exit early
        if ok and type(current_checksum) == 'string' and current_checksum ~= '' then
          if current_checksum == _G.metadata.last_projectChecksum then
            return
          end

          self.isBusy = true
          vim.defer_fn(function ()
            M.pio_refresh(function()
              self.isBusy = false
              vim.notify('PIO checksum: Metadata synced', vim.log.levels.INFO)
            end, 'PIO checksum: ')
          end, 500)
        end
      end
    },
  }
  -- targets[1].last_hash = get_hash(targets[1].path) or ''

  for _, target in ipairs(targets) do
    --[[ wrap the callback in a small anonymous function,
        so it passes the target (self) back into it.]]
    watch_file(target, target.cb)
  end
end

-- =============================================================================
-- stylua: ignore
--INFO: 6.  Exported setup function
function M.init()
  local config = require('platformio').config
  if config.lspClangd.enabled == true then
    vim.notify('PIO start: initialize', vim.log.levels.INFO)

    -- activate meta save and upload and env switch
    local metadata = require('platformio.metadata')
    metadata.load_project_config()

    require('platformio.lspConfig.clangd')
    if config.lspClangd.attach.enabled then
      require('platformio.lspConfig.attach')
    end

    -- Always start the watcher so it can catch a future 'pio init'
    M.start_watchers()

    -- boilerplate_gen([[platformio.ini]], vim.g.platformioRootDir)
    -- If the file already exists, do an initial sync
    if vim.fn.filereadable(vim.uv.cwd() .. '/platformio.ini') == 1 then
      ----------------------------------------------------------------------------------------
      --INFO: create clangd required files
      -----------------------------------------------------------------------------------------
      boilerplate_gen([[.clangd]], vim.g.platformioRootDir)
      -- boilerplate_gen([[.clangd]], vim.fs.joinpath(vim.env.XDG_CONFIG_HOME, 'clangd'), 'config.yaml')
      -- boilerplate_gen([[.clangd]], _G.metadata.core_dir)
      boilerplate.core_dir = _G.metadata.core_dir
      boilerplate_gen([[.clang-format]], vim.g.platformioRootDir)
      ---------------------------------------------------------------------------------
      -- M.run_compiledb() -- Smart: Auto-update DB if config changes
      M.pio_refresh(function()
        -- vim.schedule(function()
        --   lsp_restart('clangd')
        -- end)
      end, 'PIO start: ')
    end
  end
end

return M
