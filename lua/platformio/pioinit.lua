local M = {}

local pickers = require('telescope.pickers')
local finders = require('telescope.finders')
local telescope_conf = require('telescope.config').values
local actions = require('telescope.actions')
local action_state = require('telescope.actions.state')
local entry_display = require('telescope.pickers.entry_display')
local make_entry = require('telescope.make_entry')
local misc = require('platformio.utils.misc')
local previewers = require('telescope.previewers')

local boardentry_maker = function(opts)
  local displayer = entry_display.create({
    separator = '▏',
    items = {
      { width = 35 },
      { width = 20 },
      { width = 15 },
    },
  })

  local make_display = function(entry)
    return displayer({
      entry.value.name,
      entry.value.vendor,
      entry.value.platform,
    })
  end

  return function(entry)
    return make_entry.set_default_entry_mt({
      value = {
        id = entry.id,
        name = entry.name,
        vendor = entry.vendor,
        platform = entry.platform,
        data = entry,
      },
      ordinal = entry.name .. ' ' .. entry.vendor .. ' ' .. entry.platform,
      display = make_display,
    }, opts)
  end
end

-- stylua: ignore
local function pick_framework(board_details)
  local opts = {}
  pickers.new(opts, {
    prompt_title = 'frameworks',
    finder = finders.new_table({
      results = board_details['frameworks'],
    }),
    attach_mappings = function(prompt_bufnr, _)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()

        local pio = require('platformio.utils.pio')
        pio.selected_framework = selection[1]

        pio.run_sequence({
          {
            cmd = 'pio project init --board ' .. board_details['id'] .. ' -O "framework=' .. pio.selected_framework .. '"',
            cb = pio.handlePioinit,
          },
          -- {
          --   cmd = 'pio run -t compiledb',
          --   cb = pio.handleDb,
          -- },
        })
      end)
      return true
    end,
    sorter = telescope_conf.generic_sorter(opts),
  }):find()
end

-- stylua: ignore
local function pick_board(json_data)
  local opts = {}
  pickers.new(opts, {
    prompt_title = 'Boards',
    finder = finders.new_table({
      results = json_data,
      entry_maker = opts.entry_maker or boardentry_maker(opts),
    }),
    attach_mappings = function(prompt_bufnr, _)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        pick_framework(selection['value']['data'])
      end)
      return true
    end,
    previewer = previewers.new_buffer_previewer({
      title = 'Board Info',
      define_preview = function(self, entry, _)
        local json = misc.strsplit(vim.inspect(entry['value']['data']), '\n')
        local bufnr = self.state.bufnr
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, json)
        vim.api.nvim_set_option_value('filetype', 'lua', { buf = bufnr }) --fix deprecated function
        vim.defer_fn(function()
          local win = self.state.winid
          vim.api.nvim_set_option_value('wrap', true, { scope = 'local', win = win })
          vim.api.nvim_set_option_value('linebreak', true, { scope = 'local', win = win })
          vim.api.nvim_set_option_value('wrapmargin', 2, { buf = bufnr })
        end, 0)
      end,
    }),
    sorter = telescope_conf.generic_sorter(opts),
  }):find()
end

function M.pioinit()
  if not misc.pio_install_check() then
    return
  end

  -- Read stdout
  local command = 'pio boards --json-output'
  local handle = io.popen(command .. misc.devNul)
  if not handle then
    return
  end
  local json_str = handle:read('*a')
  handle:close()

  if #json_str == 0 then
    -- read stderr
    handle = io.popen(command .. ' 2>&1')
    if not handle then
      return
    end
    local command_output = handle:read('*a')
    handle:close()
    vim.notify('Some error occured while executing `' .. command .. "`', command output: \n", vim.log.levels.WARN)
    print(command_output)
    return
  end

  local json_data = vim.json.decode(json_str)
  pick_board(json_data)
end

return M
