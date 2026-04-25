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

  -- 1. Flags (We'll default IDE to atom or similar if not using vim specifically)
  local sample_flag = wizard_data.sample == 'true' and ' --sample-code' or ''

  local init_cmd = string.format('pio project init --board %s -O "framework=%s"%s', wizard_data.board_id, wizard_data.framework, sample_flag)

  -- 2. Build command list based on Selection
  local commands = { init_cmd }
  if wizard_data.use_compiledb then
    table.insert(commands, 'pio run -t compiledb')
  end

  print('Running ' .. #commands .. ' commands...')

  pio.run_sequence({
    cmnds = commands,
    cb = pio.handlePioinit,
  })
end

-- --- PICKERS (In Order of Execution) ---

local function dialog_opts(title, width)
  return require('telescope.themes').get_dropdown({
    prompt_title = title,
    layout_config = {
      width = width or 0.4, -- Adjust width (0.4 = 40% of screen)
      height = 0.2, -- Small height for few choices
    },
    previewer = false, -- Hide preview for simple choices
  })
end
-- STEP 4: Sample (True/False)
local function pick_sample()
  local opts = dialog_opts('Include Sample Code?', 0.3)
  pickers
    .new(opts, {
      finder = finders.new_table({ results = { 'true', 'false' } }),
      sorter = telescope_conf.generic_sorter(opts),
      attach_mappings = function(prompt_bufnr)
        actions.select_default:replace(function()
          local selection = action_state.get_selected_entry()
          actions.close(prompt_bufnr)
          wizard_data.sample = selection[1]
          finalize_setup()
        end)
        return true
      end,
    })
    :find()
end

-- STEP 3: Framework (From Board Data)

-- STEP 3: Framework Selection (Small Dialog)
local function pick_framework(board_details)
  -- Use dropdown theme to keep the window small and centered
  local opts = require('telescope.themes').get_dropdown({
    prompt_title = 'Select Framework (' .. board_details.id .. ')',
    layout_config = {
      width = 0.4, -- 40% of screen width
      height = 0.25, -- Small height for few choices
    },
    previewer = false, -- No preview needed for framework names
  })

  pickers
    .new(opts, {
      finder = finders.new_table({
        results = board_details['frameworks'],
      }),
      sorter = telescope_conf.generic_sorter(opts),
      attach_mappings = function(prompt_bufnr)
        actions.select_default:replace(function()
          local selection = action_state.get_selected_entry()
          actions.close(prompt_bufnr)
          -- selection is a simple string in this case
          wizard_data.framework = selection[1]
          pick_sample()
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
  local opts = require('telescope.themes').get_dropdown({
    prompt_title = 'Generate Compilation Database (LSP)?',
    layout_config = { width = 0.4, height = 0.2 },
    previewer = false,
  })

  pickers
    .new(opts, {
      finder = finders.new_table({ results = { 'true', 'false' } }),
      sorter = telescope_conf.generic_sorter(opts),
      attach_mappings = function(prompt_bufnr)
        actions.select_default:replace(function()
          local selection = action_state.get_selected_entry()
          actions.close(prompt_bufnr)
          -- Save the boolean for the final step
          wizard_data.use_compiledb = (selection[1] == 'true')
          pick_board(json_data)
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
