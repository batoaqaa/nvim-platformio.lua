function M.pretty_print_json_string(json_str)
  -- 1. Convert JSON string to Lua table
  local ok, data = pcall(vim.json.decode, json_str)
  if not ok then
    print('Error: Invalid JSON string provided')
    return json_str
  end

  local insert = table.insert
  local buffer = {}

  local function format_item(item, current_level)
    local indent = string.rep('  ', current_level)
    local next_indent = string.rep('  ', current_level + 1)

    if type(item) == 'table' then
      -- Check if empty table should be {} or []
      -- In Lua, an empty table from vim.json.decode is ambiguous,
      -- but usually, we treat it as an array for compile_commands.json
      local is_array = #item > 0 or (next(item) == nil and true)
      local opener = is_array and '[' or '{'
      local closer = is_array and ']' or '}'

      insert(buffer, opener .. '\n')
      local first = true

      -- Use pairs for objects, ipairs for arrays
      local iterator = is_array and ipairs(item) or pairs(item)
      for k, v in iterator do
        if not first then
          insert(buffer, ',\n')
        end
        insert(buffer, next_indent)
        if not is_array then
          insert(buffer, '"' .. k .. '": ')
        end
        format_item(v, current_level + 1)
        first = false
      end
      insert(buffer, '\n' .. indent .. closer)
    elseif type(item) == 'string' then
      -- JSON escaping
      insert(buffer, '"' .. item:gsub('\\', '\\\\'):gsub('"', '\\"') .. '"')
    else
      insert(buffer, tostring(item))
    end
  end

  format_item(data, 0)
  return table.concat(buffer)
end
