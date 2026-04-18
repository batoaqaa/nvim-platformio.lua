local M = {}

-- INFO:
-- =============================================================================
-- UNIVERSAL TOOLCHAIN DETECTION
-- =============================================================================
--- stylua: ignore
function M.get_sysroot_triplet(cc_compiler)
  local bin_path = vim.fn.fnamemodify(cc_compiler, ':h')
  -- Early exit if path is nil or not a directory
  if not bin_path or vim.fn.isdirectory(bin_path) == 0 then
    return nil
  end

  -- Normalize backslashes to forward slashes for cross-platform consistency
  bin_path = bin_path:gsub('\\', '/')
  local files = vim.fn.readdir(bin_path)
  local triplet = nil

  -- Loop through files to find the compiler and extract the triplet
  for _, name in ipairs(files) do
    -- Pattern: ^(.*) matches triplet, %- matches dash, g[c%+][c%+] matches gcc/g++
    local match = name:match('^(.*)%-g[c%+][c%+]')
    if match then
      triplet = match
      break
    end
  end

  -- Return nil if no compiler was found in the bin directory
  if not triplet then
    return nil
  end

  -- toolchain_root is the parent of the 'bin' folder
  local toolchain_root = vim.fn.fnamemodify(bin_path, ':h')
  -- sysroot folder is expected to have the same name as the triplet
  local sysroot = toolchain_root .. '/' .. triplet

  -- vim.notify('triplet= ' .. triplet, vim.log.levels.INFO)
  -- Only return data if the sysroot folder actually exists on disk
  if vim.fn.isdirectory(sysroot) == 1 then
    return {
      triplet = triplet,
      sysroot = sysroot,
      toolchain_root = toolchain_root,
      query_driver = bin_path .. '/' .. triplet .. '-*',
    }
  end
  return nil
end

--- stylua: ignore
function M.lsp_restart(name)
  -- vim.schedule_wrap(function()
  vim.notify('LSP restart.', vim.log.levels.WARN)

  local status, data = pcall(M.get_sysroot_triplet, _G.metadata.cc_compiler)
  if status and data and data.triplet and data.triplet ~= '' then
    _G.metadata.triplet = data.triplet
    _G.metadata.sysroot = data.sysroot
    _G.metadata.query_driver = data.query_driver
    _G.metadata.toolchain = data.toolchain_root
  end

  local clangConfig = _G.get_clangd_config()
  -- print(vim.inspect(clangConfig))
  vim.lsp.config(name, clangConfig)
  vim.lsp.enable(name, false)
  vim.lsp.enable(name, true)
  vim.cmd('checktime')
  -- end)
end

return M
