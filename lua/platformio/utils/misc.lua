---@class platformio.utils.misc

local M = {}

M.is_windows = jit.os == 'Windows'

M.devNul = M.is_windows and ' 2>./nul' or ' 2>/dev/null'
-- M.extra = 'printf \'\\\\n\\\\033[0;33mPlease Press ENTER to continue \\\\033[0m\'; read'
-- M.extra = ' && echo . && echo . && echo Please Press ENTER to continue'

------------------------------------------------------
--INFO:
--- stylua: ignore
function M.showMessage(msg)
  local bufnr = vim.api.nvim_create_buf(false, true)
  local text = '  ' .. msg .. '  '
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '', text, '' })

  local width = #text + 2
  local height = 3

  -- Calculate center of the screen
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local opts = {
    relative = 'editor',
    row = row,
    col = col,
    width = width,
    height = height,
    style = 'minimal',
    border = 'double',
    focusable = false,
    zindex = 200, -- High zindex to stay above ToggleTerm
  }

  local win_id = vim.api.nvim_open_win(bufnr, false, opts)

  -- Apply a solid background so you can't see the terminal text through it
  vim.api.nvim_set_option_value('winhl', 'Normal:NormalFloat,FloatBorder:DiagnosticInfo', { scope = 'local', win = win_id })

  return win_id
end

function M.closeMessage(win_id)
  if win_id and vim.api.nvim_win_is_valid(win_id) then
    vim.api.nvim_win_close(win_id, true)
  end
end
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

  -- Full JSON Escape Table
  local escapes = {
    ['\\'] = '\\\\',
    ['"']  = '\\"',
    ['\b'] = '\\b',
    ['\f'] = '\\f',
    ['\n'] = '\\n',
    ['\r'] = '\\r',
    ['\t'] = '\\t',
  }

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
      elseif val == vim.empty_dict then output = '{}'
      elseif type(val) == 'boolean' then output = tostring(val)
      elseif type(val) == 'string' then
        -- A. Handle standard escapes (\n, \t, etc.)
        local s = val:gsub('[\\"\b\f\n\r\t]', escapes)

        -- B. Handle unprintable control characters (U+0000 to U+001F)
        s = s:gsub('[%z\1-\31]', function(c)
          return string.format('\\u%04x', string.byte(c))
        end)

        -- C. Normalize Windows paths to Unix for cross-platform SHA256 stability
        -- We flip double-backslashes (\\) resulting from the escape to (/)
        s = s:gsub('\\\\', '/')

        output = '"' .. s .. '"'
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
  local buffer = {}
  local insert = table.insert

  -- Table of standard JSON escape sequences
  local escapes = {
    ['\\'] = '\\\\',
    ['"']  = '\\"',
    ['\b'] = '\\b',
    ['\f'] = '\\f',
    ['\n'] = '\\n',
    ['\r'] = '\\r',
    ['\t'] = '\\t',
  }

  local function format_item(item, current_level)
    local indent = string.rep('  ', current_level)
    local next_indent = string.rep('  ', current_level + 1)

    -- 1. Handle Neovim-specific Nulls and Empty Objects
    -- vim.NIL represents a JSON 'null' (distinct from Lua nil)
    if item == nil or item == vim.NIL then
      insert(buffer, 'null')
      return
    elseif item == vim.empty_dict then
      insert(buffer, '{}')
      return
    end

    if type(item) == 'table' then
      -- 2. Determine if Table should be an Array [] or an Object {}
      local is_array = false
      local mt = getmetatable(item)

      -- If decoded by Neovim, it likely has a __jsontype marker
      if mt and mt.__jsontype == 'array' then is_array = true
      -- If not marked, treat as array if it has indexed items or is a plain empty table
      elseif #item > 0 or (next(item) == nil and mt == nil) then is_array = true end

      -- 3. Handle Empty Structures Immediately
      if next(item) == nil then
        insert(buffer, is_array and '[]' or '{}')
        return
      end

      local opener = is_array and '[' or '{'
      local closer = is_array and ']' or '}'
      insert(buffer, opener .. '\n')

      -- 4. Key Management & Sorting
      -- Sorting is mandatory for consistent SHA256 hashes across different systems
      local keys = {}
      for k in pairs(item) do insert(keys, k) end

      -- Sort object keys alphabetically
      if not is_array then table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
      -- Ensure array indices [1, 2, 3] are processed in order
      else table.sort(keys) end

      -- 5. Iterate through items
      for i, k in ipairs(keys) do
        local v = item[k]
        if i > 1 then insert(buffer, ',\n') end -- Standard JSON comma placement
        insert(buffer, next_indent)

        -- If it's an object, add the "key": prefix
        if not is_array then insert(buffer, '"' .. tostring(k) .. '": ') end

        -- Recurse for nested tables
        format_item(v, current_level + 1)
      end

      insert(buffer, '\n' .. indent .. closer)

    elseif type(item) == 'string' then
      -- 6. String Escaping & Path Normalization
      -- A. Apply standard escapes (newline, tab, etc.)
      local s = item:gsub('[\\"\b\f\n\r\t]', escapes)

      -- B. Convert unprintable control characters to \u00xx format
      s = s:gsub('[%z\1-\31]', function(c)
        return string.format('\\u%04x', string.byte(c))
      end)

      -- C. Normalize Windows paths to Unix style
      -- We flip double-backslashes (\\) to (/) so SHA256 matches across OSs
      s = s:gsub('\\\\', '/')

      insert(buffer, '"' .. s .. '"')

    elseif type(item) == 'boolean' or type(item) == 'number' then
      -- 7. Primitives
      insert(buffer, tostring(item))
    else
      -- 8. Fallback for anything else
      insert(buffer, '"' .. tostring(item) .. '"')
    end
  end

  -- Start recursion at level 0
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
