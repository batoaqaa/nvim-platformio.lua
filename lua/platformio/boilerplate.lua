local M = {}
local uv = vim.loop

local boilerplate = {}

boilerplate['arduino'] = {

  -- local platformioRootDir = vim.fs.root(vim.fn.getcwd(), { 'platformio.ini' }) -- cwd and parents
  src_path = vim.fn.getcwd() .. 'src',
  filename = 'main.cpp',
  content = [[
#include <Arduino.h>

void setup() {

}

void loop() {

}
]],
}

boilerplate['.clangd'] = {
  src_path = vim.fn.getcwd(),
  filename = '.clangd',
  content = [[
CompileFlags:
  Remove: [
      -misc-definitions-in-headers,
      -fno-tree-switch-conversion,
      -mtext-section-literals,
      -mlong-calls,
      -mlongcalls,
      -fstrict-volatile-bitfields,
      -free*,
      -fipa-pta*,
      -march=*,
      -mabi=*,
      -mcpu=*,
    ]
Diagnostics:
  Suppress: [
      "misc-definitions-in-headers",
      "pp_including_mainfile_in_preamble",
      "misc-unused-using-decls",
      "unused-includes",
    ]
  ClangTidy:
    Remove: [
        readability-*,
        cert-err58-cpp,
        llvmlibc-*,
        fuchsia-*,
        hicpp-avoid-c-arrays,
        cppcoreguidelines-*,
        llvm-*,
        google-*,
        bugprone-*,
        hicpp-vararg,
        modernize-*,
      ]

]],
}

function M.boilerplate_gen(framework)
  print('here')
  local entry = boilerplate[framework]
  if not entry then
    return
  end

  local src_path = entry.src_path
  local stat = uv.fs_stat(src_path)

  if not stat or stat.type ~= 'directory' then
    return
  end

  local handle = uv.fs_scandir(src_path)
  if handle then
    while true do
      local name = uv.fs_scandir_next(handle)
      if not name then
        break
      end
      if name ~= '.' and name ~= '..' then
        return
      end
    end
  end

  local file_path = src_path .. '/' .. entry.filename
  local fd = uv.fs_open(file_path, 'w', 420)
  if not fd then
    return
  end
  print(entry.content)
  uv.fs_write(fd, entry.content)
  uv.fs_close(fd)
end

return M
