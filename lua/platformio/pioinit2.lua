local pickers = require('telescope.pickers')
local finders = require('telescope.finders')
local actions = require('telescope.actions')
local action_state = require('telescope.actions.state')
local previewers = require('telescope.previewers')
local telescope_conf = require('telescope.config').values

local wizard_data = {}

-- Final Step: Command Construction & Execution
local function finalize_setup()
  local pio = require('platformio.utils.pio')

  -- 1. Determine IDE flag: --ide vim enables LSP support for Neovim
  local ide_flag = wizard_data.use_ide and ' --ide vim' or ''

  -- 2. Determine Sample flag: --sample-code generates boilerplate
  local sample_flag = wizard_data.sample == 'true' and ' --sample-code' or ''

  -- 3. Construct the full init command
  local init_cmd = string.format('pio project init --board %s %s -O "framework=%s"%s', wizard_data.board_id, ide_flag, wizard_data.framework, sample_flag)

  print('Executing: ' .. init_cmd)

  pio.run_sequence({
    cmnds = {
      init_cmd,
      'pio run -t compiledb', -- Essential to generate compile_commands.json for LSP
    },
    cb = pio.handlePioinit,
  })
end

-- --- PICKERS (In Order of Execution) ---

-- STEP 4: Sample (True/False)
local function pick_sample()
  pickers
    .new({}, {
      prompt_title = 'Include Sample Code?',
      finder = finders.new_table({ results = { 'true', 'false' } }),
      sorter = telescope_conf.generic_sorter({}),
      attach_mappings = function(prompt_bufnr)
        actions.select_default:replace(function()
          local selection = action_state.get_selected_entry()
          actions.close(prompt_bufnr)
          wizard_data.sample = selection[1] -- Capture result
          finalize_setup()
        end)
        return true
      end,
    })
    :find()
end

-- STEP 3: Framework (From Board Data)
local function pick_framework(board_details)
  pickers
    .new({}, {
      prompt_title = 'Select Framework (' .. board_details.id .. ')',
      finder = finders.new_table({ results = board_details['frameworks'] }),
      sorter = telescope_conf.generic_sorter({}),
      attach_mappings = function(prompt_bufnr)
        actions.select_default:replace(function()
          local selection = action_state.get_selected_entry()
          actions.close(prompt_bufnr)
          wizard_data.framework = selection[1]
          pick_sample() -- Next step
        end)
        return true
      end,
    })
    :find()
end

-- STEP 2: Board (with Buffer Previewer)
local function pick_board(json_data)
  pickers
    .new({}, {
      prompt_title = 'Select Board',
      finder = finders.new_table({
        results = json_data,
        entry_maker = function(entry)
          return {
            value = entry,
            display = entry.name or entry.id,
            ordinal = (entry.name or '') .. ' ' .. (entry.id or ''),
          }
        end,
      }),
      previewer = previewers.new_buffer_previewer({
        title = 'Board Details',
        define_preview = function(self, entry)
          local content = vim.split(vim.inspect(entry.value), '\n')
          vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, content)
          vim.api.nvim_set_option_value('filetype', 'lua', { buf = self.state.bufnr })
        end,
      }),
      sorter = telescope_conf.generic_sorter({}),
      attach_mappings = function(prompt_bufnr)
        actions.select_default:replace(function()
          local selection = action_state.get_selected_entry()
          actions.close(prompt_bufnr)
          wizard_data.board_id = selection.value.id
          pick_framework(selection.value) -- Next step
        end)
        return true
      end,
    })
    :find()
end

-- STEP 1: IDE (True/False)
local function start_pio_wizard(json_data)
  pickers
    .new({}, {
      prompt_title = 'Setup for Neovim IDE?',
      finder = finders.new_table({ results = { 'true', 'false' } }),
      sorter = telescope_conf.generic_sorter({}),
      attach_mappings = function(prompt_bufnr)
        actions.select_default:replace(function()
          local selection = action_state.get_selected_entry()
          actions.close(prompt_bufnr)
          wizard_data.use_ide = (selection[1] == 'true')
          pick_board(json_data) -- Next step
        end)
        return true
      end,
    })
    :find()
end

local function launch_pio_project_wizard()
  print('Fetching board data from PlatformIO...')

  -- 1. Get board data from PIO CLI in JSON format
  -- The '--json-output' flag ensures we get structured data
  local handle = io.popen('pio boards --json-output')
  if not handle then
    return
  end

  local result = handle:read('*a')
  handle:close()

  -- 2. Decode the JSON string into a Lua table
  local ok, json_data = pcall(vim.json.decode, result)
  if not ok or not json_data then
    print('Error: Could not parse PlatformIO board data.')
    return
  end

  -- 3. Start the wizard we built previously
  start_pio_wizard(json_data)
end

-- Export the function so it's accessible via require()
return {
  launch = launch_pio_project_wizard,
}
