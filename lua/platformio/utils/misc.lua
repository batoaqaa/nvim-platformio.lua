---@class platformio.utils.misc

local M = {}

M.is_windows = jit.os == 'Windows'

M.devNul = M.is_windows and ' 2>./nul' or ' 2>/dev/null'
-- M.extra = 'printf \'\\\\n\\\\033[0;33mPlease Press ENTER to continue \\\\033[0m\'; read'
-- M.extra = ' && echo . && echo . && echo Please Press ENTER to continue'

------------------------------------------------------
--INFO:
--- stylua: ignore
function M.delete_file(path)
  local file = vim.fn.fnamemodify(path, ':t')
  if vim.fn.filereadable(path) == 1 then
    local success = vim.fn.delete(path)

    if success == 0 then
      vim.notify('PlatformIO: ' .. file .. ' file removed', vim.log.levels.INFO)
    else
      vim.notify('PlatformIO: Failed to delete ' .. file, vim.log.levels.ERROR)
    end
  else
    vim.notify('PlatformIO: ' .. file .. ' file not found', vim.log.levels.WARN)
  end
end

------------------------------------------------------
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
  -- Stack stores: { val = item, lvl = depth, stage = "start"|"items", keys = {}, index = 0 }
  local stack = { { val = root_data, lvl = 0, stage = 'start' } }

  local function get_indent(lvl) return string.rep('  ', lvl) end

  while #stack > 0 do
    local curr = stack[#stack]
    local val, lvl = curr.val, curr.lvl
    local indent = get_indent(lvl)

    if type(val) == 'table' then
      -- 1. Determine if Array or Object
      local is_array = false

      -- Check if it's explicitly marked as an array by the Neovim parser
      local mt = getmetatable(val)
      if mt and mt.__jsontype == 'array' then
        is_array = true
      -- If not marked, check if it has indexed items or is literally an empty table
      elseif #val > 0 or next(val) == nil then
        is_array = true
      end

      if curr.stage == 'start' then
        table.insert(buffer, (is_array and '[' or '{') .. '\n')
        curr.stage = 'items'
        curr.keys = {}

        -- 2. Collect and Sort Keys (CRITICAL for SHA256 stability)
        if is_array then for i = 1, #val do table.insert(curr.keys, i) end
        else
          for k in pairs(val) do table.insert(curr.keys, k) end
          table.sort(curr.keys, function(a, b) return tostring(a) < tostring(b) end)
        end
        curr.total = #curr.keys
        curr.cursor = 1 -- Point to the first key
      elseif curr.stage == 'items' then
        if curr.cursor <= curr.total then
          local key = curr.keys[curr.cursor]
          local item = val[key]

          -- Add comma for all but the first item
          if curr.cursor > 1 then table.insert(buffer, ',\n') end

          table.insert(buffer, get_indent(lvl + 1))
          if not is_array then table.insert(buffer, '"' .. tostring(key) .. '": ') end

          curr.cursor = curr.cursor + 1
          -- Push next item to process
          table.insert(stack, { val = item, lvl = lvl + 1, stage = 'start' })
        else
          -- 3. Close the block
          table.insert(buffer, '\n' .. indent .. (is_array and ']' or '}'))
          table.remove(stack)
        end
      end
    else
      -- 4. Primitives (String, Number, Bool, Nil)
      local output = ''
      if val == nil or val == vim.NIL then output = 'null'
      elseif type(val) == 'boolean' then output = tostring(val)
      elseif type(val) == 'string' then
        -- Normalize Windows paths to Unix for cross-platform checksums
        output = '"' .. val:gsub('\\', '/'):gsub('"', '\\"') .. '"'
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
  local buffer = {}

  local function format_item(item, current_level)
    local insert = table.insert
    local indent = string.rep('  ', current_level)
    local next_indent = string.rep('  ', current_level + 1)

    if type(item) == 'table' then
      -- 1. TRULY EMPTY CHECK
      if next(item) == nil then
        -- In PIO metadata, most empty fields are intended to be arrays []
        -- But we use {} as a safe JSON default for generic tables.
        insert(buffer, '{}')
        return
      end

      -- 2. DETERMINE IF ARRAY OR OBJECT
      -- A table is an array if it has a value at index 1
      local is_array = item[1] ~= nil
      local opener = is_array and '[' or '{'
      local closer = is_array and ']' or '}'

      insert(buffer, opener .. '\n')

      -- 3. SORT KEYS (Crucial for consistent SHA256 hashes)
      local keys = {}
      for k in pairs(item) do table.insert(keys, k) end
      if not is_array then table.sort(keys) end

      local first = true
      for _, k in ipairs(keys) do
        local v = item[k]
        if not first then insert(buffer, ',\n') end
        insert(buffer, next_indent)

        if not is_array then insert(buffer, '"' .. tostring(k) .. '": ') end

        format_item(v, current_level + 1)
        first = false
      end
      insert(buffer, '\n' .. indent .. closer)
    elseif type(item) == 'string' then
      -- Escape backslashes for Windows paths and quotes
      insert(buffer, '"' .. item:gsub('[\\]+', '/'):gsub('"', '\\"') .. '"')
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
---@param path string
function M.readFile(path)
  local uv = vim.uv or vim.loop

  -- 1. Check if file exists before opening to avoid "noisy" errors
  local stat = uv.fs_stat(path)
  if not stat then return false, 'File does not exist' end

  -- 2. Open the file
  local fd, err = uv.fs_open(path, 'r', 438)
  if not fd then return false, err end

  -- 3. Read the content (using stat.size from our check above)
  local content, read_err = uv.fs_read(fd, stat.size, 0)
  uv.fs_close(fd)

  if read_err then return false, read_err end

  return true, content
end

------------------------------------------------------
-- function M.writeFile(path, data, opts)
--   local uv = vim.uv or vim.loop
--
--   opts = opts or {overwrite = true, mkdir = true}
--
--   -- 1. Check if file exists and handle overwrite flag
--   local stat = uv.fs_stat(path)
--   if stat and opts.overwrite == false then
--     return false, 'writeFile: File already exists and overwrite is disabled'
--   end
--
--   -- 2. Ensure folder exists (mkdir -p logic)
--   if opts.mkdir ~= false then
--     local parent = vim.fn.fnamemodify(path, ':h')
--     if not stat or stat.type ~= 'directory' then
--       -- Using vim.fn.mkdir is easier for recursive creation
--       vim.fn.mkdir(parent, 'p', '0700')
--     end
--   end
--
--   -- 3. Open file for writing
--   local fd, err = uv.fs_open(path, 'w', 438)
--   if not fd then return false, 'writeFile: Open error: ' .. (err or 'unknown') end
--
--   -- 4. Write data
--   local success, write_err = uv.fs_write(fd, data, 0)
--
--   -- 5. ALWAYS close
--   uv.fs_close(fd)
--
--   if not success then return false, 'writeFile: Write error: ' .. write_err end
--
--   return true, 'writeFile: complete'
-- end

--INFO:
-- Example
-- local ok, err = writeFiile(path, json)
-- if ok then print("Write complete!") end
-- stylua: ignore
---@param path string
---@param data string
---@param opts table
function M.writeFile(path, data, opts)
  local uv = vim.uv or vim.loop

  -- opts.overwrite: boolean (default true)
  -- opts.mkdir: boolean (default true)
  opts = opts or { overwrite = true, mkdir = true }

  local stat = uv.fs_stat(path)
  -- 1. Overwrite protection
  if opts.overwrite == false and stat then
    return false, 'writeFile: File already exists'
  end

  -- 2. Recursive directory creation
  if opts.mkdir ~= false then
    local parent = vim.fn.fnamemodify(path, ':h')
    if not stat or stat.type ~= 'directory' then
      vim.fn.mkdir(parent, 'p', '0700')
    end
  end

  --[[
      Octal	Decimal	Permission
      0700	  448	    Owner only (Full)
      0755	  493	    Owner (Full), Others (Read/Execute)
      0666	  438	    Everyone (Read/Write) - Not recommended for folders
     'w' truncates existing, 'wx' fails if exists (extra safety)
  ]]
  -- 3. Open for writing ('w' flag truncates automatically)
  local fd, err = uv.fs_open(path, 'w', 438)
  if not fd then return false, 'writeFile: Open error: ' .. (err or 'unknown') end

  -- 4. Robust Write Loop
  -- Loop ensures all data is written even if it takes multiple chunks
  local offset = 0
  while offset < #data do
    local bytes_written, w_err = uv.fs_write(fd, data:sub(offset + 1), offset)
    if w_err then
      uv.fs_close(fd)
      return false, 'writeFile: Write error: ' .. w_err
    end
    offset = offset + bytes_written
  end

  -- 5. Force Sync (Crucial for your project.checksum watcher)
  uv.fs_fsync(fd)
  uv.fs_close(fd)

  return true, 'Success'
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
