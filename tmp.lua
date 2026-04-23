-- Detect OS and Home directory dynamically
local is_windows = vim.loop.os_uname().version:find('Windows')
local home = os.getenv('HOME') or os.getenv('USERPROFILE')
local username = os.getenv('USERNAME') or os.getenv('USER')

-- Build a list of common compiler paths
local drivers = {
  'C:/Program Files/LLVM/bin/*', -- Windows Clang
  'C:/msys64/*/bin/*', -- Windows MinGW (MSYS2)
  home .. '/.platformio/packages/*/bin/*', -- PlatformIO (Both OS)
  '/usr/bin/*', -- Linux standard
  '/usr/local/bin/*', -- Linux local
}

require('lspconfig').clangd.setup({
  cmd = {
    'clangd',
    '--background-index',
    '--clang-tidy',
    '--offset-encoding=utf-16',
    -- Combine all paths into one comma-separated string
    '--query-driver=' .. table.concat(drivers, ','),
  },
  -- Other standard config options...
})
