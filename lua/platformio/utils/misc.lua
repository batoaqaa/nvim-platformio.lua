local M = {}

M.is_windows = jit.os == 'Windows'

M.devNul = M.is_windows and ' 2>./nul' or ' 2>/dev/null'
-- M.extra = 'printf \'\\\\n\\\\033[0;33mPlease Press ENTER to continue \\\\033[0m\'; read'
-- M.extra = ' && echo . && echo . && echo Please Press ENTER to continue'

--INFO:
--  Version-Safe Path Joining (Fallback for Neovim < 0.10.0)
-- stylua: ignore
M.joinPath = vim.fs.joinpath or function(...)
  return table.concat({ ... }, '/'):gsub('//+', '/')
end
------------------------------------------------------
--INFO:
-- iterrative loop 48ms
-- stylua: ignore
function M.jsonFormat(root_data)
  local buffer = {}

  -- Force input into a table if it's just a single string
  local patterns = type(root_data) == "table" and root_data or { root_data }

  -- The stack stores: { value = current_item, level = depth, stage = "start"|"items" }
  local stack = { { val = patterns, lvl = 0, stage = 'start' } }

  local function get_indent(lvl) return string.rep('  ', lvl) end

  while #stack > 0 do
    local curr = stack[#stack]
    local val, lvl = curr.val, curr.lvl
    local indent = get_indent(lvl)

    if type(val) == 'table' then
      local is_array = (#val > 0 or next(val) == nil)

      if curr.stage == 'start' then
        table.insert(buffer, (is_array and '[' or '{') .. '\n')
        curr.stage = 'items'
        curr.keys = {}
        -- Collect keys to iterate deterministically
        if is_array then
          for i = #val, 1, -1 do table.insert(curr.keys, i) end
        else
          for k, _ in pairs(val) do table.insert(curr.keys, k) end
        end
        curr.index = #curr.keys
      elseif curr.stage == 'items' then
        if curr.index > 0 then
          local key = curr.keys[curr.index]
          local item = val[key]

          -- Add comma if not the first item
          if curr.index < #curr.keys then table.insert(buffer, ',\n') end

          table.insert(buffer, get_indent(lvl + 1))
          if not is_array then table.insert(buffer, '"' .. tostring(key) .. '": ') end

          curr.index = curr.index - 1
          -- Push next item to stack
          table.insert(stack, { val = item, lvl = lvl + 1, stage = 'start' })
        else
          -- No more items, close the block
          table.insert(buffer, '\n' .. indent .. (is_array and ']' or '}'))
          table.remove(stack)
        end
      end
    else
      -- Primitive values (String, Number, Bool)
      local output = ''
      if type(val) == 'string' then
        -- output = '"' .. val:gsub('\\', '\\\\'):gsub('"', '\\"') .. '"'
        output = '"' .. val:gsub('\\', '/'):gsub('"', '\\"') .. '"'
        -- output = '"' .. val:gsub('"', '\\"') .. '"'
      else output = tostring(val) end
      table.insert(buffer, output)
      table.remove(stack)
    end
  end
  return table.concat(buffer)
end

------------------------------------------------------
--INFO:
-- regex 100ms
-- stylua: ignore
function M.pretty_json(data)
  -- 1. Get a guaranteed valid JSON string from Neovim's core
  local json = vim.json.encode(data)

  -- 2. Use regex to inject newlines and indentation
  -- This is much faster than manual recursion in Lua
  local indent = '  '
  local level = 0

  -- Add newlines after { [ , and before } ]
  json = json:gsub('([%[%{%],])', '%1\n')
  json = json:gsub('([%]}])', '\n%1')

  local lines = {}
  for line in json:gmatch('[^\n]+') do
    line = line:gsub('^%s+', '') -- trim existing whitespace

    -- Decrease level if line starts with closing bracket
    if line:match('^[%]}]') then level = level - 1 end

    table.insert(lines, string.rep(indent, level) .. line)

    -- Increase level if line ends with opening bracket
    if line:match('[%[{]$') then level = level + 1 end
  end
  return table.concat(lines, '\n')
end

------------------------------------------------------
--INFO:
-- recursion 50ms
-- stylua: ignore
-- local function pretty_print(data) -- 48ms
function M.pretty_print(data) -- 48ms
  -- Force input into a table if it's just a single string
  local insert = table.insert
  local buffer = {}
  local function format_item(item, current_level)
    local indent = string.rep('  ', current_level)
    local next_indent = string.rep('  ', current_level + 1)
    if type(item) == 'table' then
      local is_array = #item > 0
      local opener = is_array and '[' or '{'
      local closer = is_array and ']' or '}'
      insert(buffer, opener .. '\n')
      local first = true
      for k, v in pairs(item) do
        if not first then insert(buffer, ',\n') end
        insert(buffer, next_indent)
        if not is_array then insert(buffer, '"' .. k .. '": ') end
        format_item(v, current_level + 1)
        first = false
      end
      insert(buffer, '\n' .. indent .. closer)
    elseif type(item) == 'string' then
      -- Basic escaping for the string content
      insert(buffer, '"' .. item:gsub('\\', '\\\\'):gsub('"', '\\"') .. '"')
    else insert(buffer, tostring(item)) end
  end
  format_item(data, 0)
  return table.concat(buffer)
end

------------------------------------------------------
--INFO:
-- Example Usage
-- local content = readFile("compile_commands.json")
-- if content then local data = vim.json.decode(content) end
-- stylua: ignore
function M.readFile(path)
  local uv = vim.uv or vim.loop -- Support older and newer Neovim versions

  -- 1. Open the file (r = read-only)
  -- 438 is the octal for 0666 (standard permissions)
  local fd, err = uv.fs_open(path, 'r', 438)
  if not fd or err then return nil, 'readFile: Open error: ' .. err end

  -- 2. Get file stats to find out how many bytes to read
  local stat, stat_err = uv.fs_fstat(fd)
  if not stat or stat_err then
    uv.fs_close(fd)
    return nil, 'readFile: Stat error: ' .. stat_err
  end

  -- 3. Read the entire content
  -- fd, length, offset
  local content, read_err = uv.fs_read(fd, stat.size, 0)

  -- 4. ALWAYS close the file descriptor
  uv.fs_close(fd)

  if read_err then return nil, 'readFile: Read error: ' .. read_err end

  return content
end

------------------------------------------------------
--INFO:
-- Example
-- local ok, err = writeFiile(path, json)
-- if ok then print("Write complete!") end
-- stylua: ignore
function M.writeFile(data, path)
  local uv = vim.uv or vim.loop

  -- 1. Open file for writing
  -- 'w' = open for writing (creates if doesn't exist, truncates if it does)
  -- 438 is octal 0666 (standard read/write permissions)
  local fd, err = uv.fs_open(path, 'w', 438)
  if not fd or err then return nil, 'writeFile: Open error: ' .. err end

  -- 2. Write the data
  -- fd, data, offset (0 to start at beginning)
  local _, write_err = uv.fs_write(fd, data, 0)

  -- 3. ALWAYS close the file descriptor
  uv.fs_close(fd)

  if write_err then return nil, 'writeFile: Write error: ' .. write_err end

  return true
end

------------------------------------------------------
--[[ 
Targets Windows paths, normalizes slashes, and fixes smashed PlatformIO paths.
Cleans and repairs compiler flags in a command string.
{ "-I", "-L", "-isystem", "-T", "-include" }
1. Library Paths
    -L: Specifies directories to search for library files (.a, .lib, .so).
        Example: -L"C:\Users\lib"
        -L"C:/Users/lib"
    -l (lowercase L): While usually just a name (like -lmath), it can sometimes be a direct path to a specific file.
2. Header Inclusion (Advanced)
    -isystem: Similar to -I, but treats the directory as a "system" header (suppresses warnings). PlatformIO uses this heavily for framework headers (Arduino/ESP-IDF).
    -include: Forces the compiler to include a specific file before anything else.
        Example: -include "C:\project\config.h"
    -iquote: Directories for headers wrapped in double quotes "".
3. Output and Debugging
    -o: The output path for the compiled object file or binary.
    -fdebug-prefix-map=: Used to make builds reproducible by mapping absolute paths to relative ones in the debug symbols.
4. Linker and Frameworks
    -T: Path to a linker script (very common in embedded/PlatformIO for memory mapping).
        Example: -T"C:\project\ld\esp32.ld"
    -F: (macOS/iOS) Path to search for frameworks.
]]
-- stylua: ignore
--- @param flags string: The raw command string (e.g., from compile_commands.json)
--- @return string: The cleaned command string
--INFO:
function M.normalizeFlags(flags)
  if not flags or flags == '' then
    return ''
  end

  --1. Identify flags that look like paths.
  -- Pattern explanation:
  --   %-      : Matches a literal hyphen (the start of a flag)
  --   %S*     : Matches zero or more non-space characters
  --   \\      : Matches a literal backslash (identifies it as a Windows path)
  --   %S*     : Matches the rest of the non-space characters in that flag
  local cleaned_cmd = flags:gsub('(%-%S-\\S*)', function(flag)
    --2. Normalize Slashes
    -- Replaces any number of backslashes (single \ or JSON-escaped \\) with one forward slash.
    -- Forward slashes are safer and more portable for compilers like GCC/Clang.
    flag = flag:gsub('[\\]+', '/')

    --3. Heal PlatformIO "Smashed" Paths
    -- Fixes the bug where PlatformIO expansions repeat the user home directory.
    -- Example: /Users/name/.platformiopackages/toolchain -> /.platformio/packages/toolchain
    flag = flag:gsub('/Users/[^/]+%.platformio/packages', '/.platformio/packages')

    return flag
  end)

  -- Return only the result string (discarding the replacement count)
  return cleaned_cmd
end

------------------------------------------------------
--INFO:
function M.normalizePath(path)
  -- return path:gsub('[\\]+', '/'):gsub('[//]+', '/')
  return path:gsub('[\\/]+', '/')
end

------------------------------------------------------
--INFO:
function M.strsplit(inputstr, del)
  local t = {}
  if type(inputstr) == 'string' and inputstr and inputstr ~= '' then
    for str in string.gmatch(inputstr, '([^' .. del .. ']+)') do
      table.insert(t, str)
    end
  end
  return t
end

------------------------------------------------------
--INFO:
function M.check_prefix(str, prefix)
  return str:sub(1, #prefix) == prefix
end

------------------------------------------------------
--INFO:
local function pathmul(n)
  return '..' .. string.rep('/..', n)
end

local paths = { '.', '..', pathmul(1), pathmul(2), pathmul(3), pathmul(4), pathmul(5) }

------------------------------------------------------
--INFO:
function M.file_exists(name)
  local f = io.open(name, 'r')
  if f ~= nil then
    io.close(f)
    return true
  else
    return false
  end
end

------------------------------------------------------
--INFO:
function M.set_platformioRootDir()
  if vim.g.platformioRootDir ~= nil then
    return
  end
  for _, path in pairs(paths) do
    if M.file_exists(path .. '/platformio.ini') then
      vim.g.platformioRootDir = path
      return
    end
  end
  vim.notify('Could not find platformio.ini, run :Pioinit to create a new project', vim.log.levels.ERROR)
end

------------------------------------------------------
--INFO:
function M.cd_pioini()
  -- M.set_platformioRootDir()
  vim.cmd('cd ' .. vim.g.platformioRootDir)
end

------------------------------------------------------
--INFO:
function M.pio_install_check()
  local handle = (jit.os == 'Windows') and assert(io.popen('where.exe pio 2>./nul')) or assert(io.popen('which pio 2>/dev/null'))
  local pio_path = assert(handle:read('*a'))
  handle:close()

  if #pio_path == 0 then
    vim.notify('Platformio not found in the path', vim.log.levels.ERROR)
    return false
  end
  return true
end

------------------------------------------------------
--INFO:
function M.async_shell_cmd(cmd, callback)
  local output = {}

  vim.fn.jobstart(cmd, {
    stdout_buffered = true,
    stderr_buffered = false,

    on_stdout = function(_, data)
      if data then
        for _, line in ipairs(data) do
          if line ~= '' then
            table.insert(output, line)
          end
        end
      end
    end,

    on_exit = function(_, code)
      callback(output, code)
    end,
  })
end

------------------------------------------------------
--INFO:
function M.shell_cmd_blocking(command)
  local handle = io.popen(command, 'r')
  if not handle then
    return nil, 'failed to run command'
  end

  local result = handle:read('*a')
  handle:close()

  return result
end

------------------------------------------------------
--INFO:
function M.gitignore_lsp_configs(config_file)
  local gitignore_path = vim.fs.joinpath(vim.g.platformioRootDir, '.gitignore')
  local file = io.open(gitignore_path, 'r')
  local pattern = '^%s*' .. vim.pesc(config_file) .. '%s*$'

  if file then
    for line in file:lines() do
      if line:match(pattern) then
        file:close()
        return
      end
    end
    file:close()
  end

  file = io.open(gitignore_path, 'a')
  if file then
    file:write(config_file .. '\n')
    file:close()
  end
end

return M
