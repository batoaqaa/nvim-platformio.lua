-- pick a temp root
local tmp = vim.loop.os_tmpdir() .. "/nvim-temp"

vim.env.XDG_DATA_HOME = tmp .. "/data"
vim.env.XDG_CACHE_HOME = tmp .. "/cache"
vim.env.XDG_STATE_HOME = tmp .. "/state"

-- disable netrw at the very start of your init.lua
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

-- optionally enable 24-bit colour
vim.opt.termguicolors = true

vim.opt["number"] = true
vim.opt.tabstop = 2 -- Number of spaces tabs count for
vim.opt.softtabstop = 2
vim.opt.shiftround = true -- Round indent
vim.opt.shiftwidth = 2 -- Size of an indent
vim.opt.smartindent = true -- Insert indents automatically
vim.opt.expandtab = true -- Use spaces instead of tabs

vim.g.have_nerd_font = true
vim.g.mapleader = " "
vim.g.maplocalleader = " "

vim.keymap.set("n", "<leader>e", "<cmd>NvimTreeToggle<CR>", { desc = "NvimTreeToggle" })
vim.keymap.set("n", "\\", "<cmd>NvimTreeToggle<CR>", { desc = "NvimTreeToggle" })

-- Keybinds to make split navigation easier.
--  Use CTRL+<hjkl> to switch between windows
vim.keymap.set("n", "<C-h>", "<C-w><C-h>", { desc = "Move focus to the left window" })
vim.keymap.set("n", "<C-l>", "<C-w><C-l>", { desc = "Move focus to the right window" })
vim.keymap.set("n", "<C-j>", "<C-w><C-j>", { desc = "Move focus to the lower window" })
vim.keymap.set("n", "<C-k>", "<C-w><C-k>", { desc = "Move focus to the upper window" })
----------------------------------------------------------------------------------------

local lazypath = vim.env.XDG_DATA_HOME .. "/lazy/lazy.nvim"

if not (vim.uv or vim.loop).fs_stat(lazypath) then
	vim.fn.system({
		"git",
		"clone",
		"--filter=blob:none",
		"https://github.com/folke/lazy.nvim.git",
		"--branch=stable",
		lazypath,
	})
end

vim.opt.rtp:prepend(lazypath)

----------------------------------------------------------------------------------------
local plugins = {
	-- {
	-- 	"saghen/blink.cmp",
	-- 	dependencies = { "rafamadriz/friendly-snippets" },
	-- 	version = "1.*",
	-- 	opts = {
	-- 		appearance = {
	-- 			use_nvim_cmp_as_default = false,
	-- 			nerd_font_variant = "mono",
	-- 		},
	-- 		completion = {
	-- 			accept = {
	-- 				auto_brackets = {
	-- 					enabled = true,
	-- 				},
	-- 			},
	-- 			menu = {
	-- 				draw = {
	-- 					treesitter = { "lsp" },
	-- 				},
	-- 			},
	-- 			documentation = {
	-- 				auto_show = true,
	-- 				auto_show_delay_ms = 200,
	-- 			},
	-- 			ghost_text = {
	-- 				enabled = vim.g.ai_cmp,
	-- 			},
	-- 		},
	-- 		sources = {
	-- 			default = { "lsp", "path", "snippets", "buffer" },
	-- 		},
	-- 		cmdline = {
	-- 			enabled = false,
	-- 			keymap = {
	-- 				preset = "cmdline",
	-- 				["<Right>"] = false,
	-- 				["<Left>"] = false,
	-- 			},
	-- 			sources = {
	-- 				default = { "lsp", "path", "snippets", "buffer" },
	-- 			},
	-- 			completion = {
	-- 				menu = {
	-- 					auto_show = true,
	-- 				},
	-- 				ghost_text = {
	-- 					enabled = true,
	-- 				},
	-- 			},
	-- 		},
	-- 		keymap = {
	-- 			preset = "super-tab",
	-- 			["<Tab>"] = { "insert_next" },
	-- 			["<S-Tab>"] = { "insert_prev" },
	-- 			["<CR>"] = { "select_and_accept" },
	-- 			["<C-e>"] = { "hide", "show" },
	-- 		},
	-- 	},
	-- },
	--
	-- -- LSP config
	-- {
	-- 	"mason-org/mason-lspconfig.nvim",
	-- 	opts = {},
	-- 	dependencies = {
	-- 		{
	-- 			"mason-org/mason.nvim",
	-- 			config = function()
	-- 				---------------------------------------------------------------------------------
	-- 				-- INFO: Mason packages install for lint and formater
	--
	-- 				local fok, fidget = pcall(require, "fidget")
	-- 				if fok then
	-- 					fidget.setup({})
	-- 				end
	--
	-- 				local tok, trouble = pcall(require, "trouble")
	-- 				if tok then
	-- 					trouble.setup({})
	-- 				end
	--
	-- 				-- mason.setup()
	-- 				local mason = require("mason")
	--
	-- 				mason.setup({
	-- 					PATH = "append",
	-- 					ui = {
	-- 						border = "single",
	-- 						icons = {
	-- 							package_installed = "✓",
	-- 							package_pending = "➜",
	-- 							package_uninstalled = "✗",
	-- 						},
	-- 					},
	-- 				})
	-- 				-- List of packages you want Mason to ensure are installed
	-- 				local ensure_installed = {
	-- 					"clang-format",
	-- 				}
	--
	-- 				-- Mason function to install or ensure formatters/linters are installed
	-- 				local mr = require("mason-registry")
	-- 				mr.refresh(function()
	-- 					for _, tool in ipairs(ensure_installed) do
	-- 						local ok, p = pcall(mr.get_package, tool)
	-- 						if ok and p then
	-- 							if not p:is_installed() then
	-- 								if not p:is_installing() then
	-- 									p:install({}, function(success, _)
	-- 										if not success then
	-- 											vim.defer_fn(function()
	-- 												vim.notify(tool .. " failed to install", vim.log.levels.ERROR)
	-- 											end, 0)
	-- 										end
	-- 									end)
	-- 								else
	-- 									vim.defer_fn(function()
	-- 										vim.notify(tool .. " already installed", vim.log.levels.WARN)
	-- 									end, 0)
	-- 								end
	-- 							end
	-- 						else
	-- 							vim.defer_fn(function()
	-- 								vim.notify("Failed to get package: " .. tool, vim.log.levels.WARN)
	-- 							end, 0)
	-- 						end
	-- 					end
	-- 				end)
	--
	-- 				require("mason-lspconfig").setup({
	-- 					ensure_installed = { "clangd" },
	-- 					-- automatic_enable = true, -- this will automatically enable LSP servers after install
	-- 				})
	--
	-- 				local cmd = {
	-- 					"clangd",
	-- 					"--all-scopes-completion",
	-- 					"--background-index",
	-- 					"--clang-tidy",
	-- 					"--compile_args_from=filesystem",
	-- 					"--compile-commands-dir=.", -- so this is in default directory (parent of /src) no need for it.
	-- 					"--enable-config",
	-- 					"--completion-parse=always",
	-- 					"--completion-style=detailed",
	-- 					"--header-insertion=iwyu",
	-- 					"--header-insertion-decorators",
	-- 					"-j=12",
	-- 					"--log=verbose", -- for debugging
	-- 					--   '--log=error',
	-- 					"--offset-encoding=utf-8",
	-- 					"--pch-storage=memory",
	-- 					"--pretty",
	-- 					"--query-driver=**",
	-- 					"--ranking-model=decision_forest",
	-- 				}
	--
	-- 				local path = vim.fn.getcwd()
	-- 				local fname = string.format("%s\\.clangd_cmd", path)
	-- 				if vim.fn.filereadable(fname) == 1 then
	-- 					local ok, result = pcall(vim.fn.readfile, fname)
	-- 					if ok then
	-- 						cmd = result
	-- 						-- print(vim.inspect(cmd))
	-- 					end
	-- 				end
	--
	-- 				local capabilities = vim.lsp.protocol.make_client_capabilities()
	-- 				local bok, _ = pcall(require, "blink")
	-- 				if bok then
	-- 					capabilities = vim.tbl_deep_extend(
	-- 						"force",
	-- 						capabilities,
	-- 						require("blink.cmp").get_lsp_capabilities({}, false)
	-- 					)
	-- 				end
	-- 				---@type vim.lsp.Config
	-- 				local clangd = {
	-- 					cmd = cmd,
	-- 					filetypes = { "c", "cpp", "objc", "objcpp", "cuda", "proto" },
	-- 					root_markers = {
	-- 						"CMakeLists.txt",
	-- 						".clangd",
	-- 						".clang-tidy",
	-- 						".clang-format",
	-- 						"compile_commands.json",
	-- 						"compile_flags.txt",
	-- 						"configure.ac",
	-- 						".git",
	-- 						vim.uv.cwd(),
	-- 					},
	-- 					capabilities = capabilities,
	-- 					workspace_required = true,
	-- 					single_file_support = true,
	-- 					init_options = {
	-- 						usePlaceholders = true,
	-- 						completeUnimported = true,
	-- 						fallback_flags = { "-std=c++17" },
	-- 						clangdFileStatus = true,
	-- 						compilationDatabasePath = vim.fn.getcwd(),
	-- 					},
	-- 				}
	-- 				vim.lsp.config("clangd", clangd)
	--
	-- 				----------------------
	-- 				local mok, mason_lspconfig = pcall(require, "mason-lspconfig")
	-- 				if mok then
	-- 					mason_lspconfig.setup({})
	-- 				end
	--
	-- 				----------------------------------------------------------------------------------
	-- 				-- INFO: LspAttach autocommand start
	-- 				vim.api.nvim_create_autocmd("LspAttach", {
	-- 					group = vim.api.nvim_create_augroup("platformio-lsp-attach", { clear = true }),
	-- 					--desc = 'LSP actions',
	-- 					callback = function(args)
	-- 						local client = assert(vim.lsp.get_client_by_id(args.data.client_id))
	-- 						local bufnr = args.buf
	--
	-- 						if client then
	-- 							-- vim.lsp.set_log_level 'trace'
	-- 							print("Attaching to: " .. client.name .. " attached to buffer " .. bufnr)
	-- 							------------------------------------------------------------------
	-- 							if client.name == "clangd" then
	-- 								vim.api.nvim_buf_create_user_command(0, "LspClangdSwitchSourceHeader", function()
	-- 									local method_name = "textDocument/switchSourceHeader"
	-- 									local params = vim.lsp.util.make_text_document_params(bufnr)
	-- 									client.request(method_name, params, function(err, result)
	-- 										if err then
	-- 											error(tostring(err))
	-- 										end
	-- 										if not result then
	-- 											vim.notify("corresponding file cannot be determined")
	-- 											return
	-- 										end
	-- 										vim.cmd.edit(vim.uri_to_fname(result))
	-- 									end, bufnr)
	-- 								end, { desc = "Switch between source/header" })
	-- 							end
	-- 							------------------------------------------------------------------
	-- 							--- Skip this if you are using blink
	-- 							if not bok then
	-- 								if client:supports_method("textDocument/completion", { bufnr = bufnr }) then
	-- 									vim.lsp.completion.enable(true, client.id, args.buf, { autotrigger = true })
	-- 								end
	-- 								vim.diagnostic.config({
	-- 									current_line = true,
	-- 									virtual_lines = {
	-- 										current_line = true,
	-- 									},
	-- 								})
	-- 								vim.cmd([[set completeopt+=noselect]])
	-- 							end
	--
	-- 							------------------------------------------------------------------
	-- 							if client.server_capabilities.documentHighlightProvider then
	-- 								local highlight_augroup =
	-- 									vim.api.nvim_create_augroup("kickstart-lsp-highlight", { clear = false })
	-- 								vim.api.nvim_create_autocmd({ "CursorHold", "CursorHoldI" }, {
	-- 									buffer = bufnr,
	-- 									group = highlight_augroup,
	-- 									callback = vim.lsp.buf.document_highlight,
	-- 								})
	-- 								--
	-- 								vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
	-- 									buffer = bufnr,
	-- 									group = highlight_augroup,
	-- 									callback = vim.lsp.buf.clear_references,
	-- 								})
	-- 								--
	-- 								vim.api.nvim_create_autocmd("LspDetach", {
	-- 									group = vim.api.nvim_create_augroup("kickstart-lsp-detach", { clear = true }),
	-- 									callback = function(event)
	-- 										vim.lsp.buf.clear_references()
	-- 										vim.api.nvim_clear_autocmds({
	-- 											group = "kickstart-lsp-highlight",
	-- 											buffer = event.buf,
	-- 										})
	-- 									end,
	-- 								})
	-- 								--
	-- 							end
	-- 							local bufkeymap = function(mode, lhs, rhs, desc)
	-- 								vim.keymap.set(mode, lhs, rhs, { buffer = bufnr, silent = true, desc = desc }) -- noremap by default
	-- 							end
	-- 							-- Disable defaults
	-- 							pcall(vim.keymap.del, "n", "gra")
	-- 							pcall(vim.keymap.del, "n", "gri")
	-- 							pcall(vim.keymap.del, "n", "grn")
	-- 							pcall(vim.keymap.del, "n", "grr")
	-- 							pcall(vim.keymap.del, "n", "gO")
	-- 							pcall(vim.keymap.del, "n", "K")
	-- 							--
	-- 							-- Quickfix list
	-- 							bufkeymap("n", "[q", vim.cmd.cprev, "Previous quickfix item")
	-- 							bufkeymap("n", "]q", vim.cmd.cnext, "Next quickfix item")
	--
	-- 							-- Diagnostic keymaps
	-- 							bufkeymap(
	-- 								"n",
	-- 								"[d",
	-- 								"<cmd>vim.diagnostic.goto_prev()<CR>",
	-- 								"Go to previous [d]iagnostic message"
	-- 							)
	-- 							bufkeymap(
	-- 								"n",
	-- 								"]d",
	-- 								"<cmd>vim.diagnostic.goto_next()<CR>",
	-- 								"Go to next [d]iagnostic message"
	-- 							)
	-- 							bufkeymap("n", "gle", vim.diagnostic.open_float, "Show diagnostic [e]rror messages")
	-- 							-- bufkeymap('n', 'gle', '<Cmd>Telescope diagnostics<CR>', 'Show diagnostic [e]rror messages')
	-- 							bufkeymap("n", "glq", vim.diagnostic.setloclist, "Open diagnostic [q]uickfix list")
	-- 							--
	-- 							-- stylua: ignore start
	-- 							-- << local trouble = require("trouble").toggle
	-- 							-- << bufkeymap('n', "<leader>tt", function() trouble() end, "Toggle Trouble")
	-- 							-- << bufkeymap('n', "<leader>tq", function() trouble("quickfix") end, "Quickfix List")
	-- 							-- << bufkeymap('n', "<leader>dr", function() trouble("lsp_references") end, "References")
	-- 							-- << bufkeymap('n', "<leader>dd", function() trouble("document_diagnostics") end, "Document Diagnostics")
	-- 							-- << bufkeymap('n', "<leader>dw", function() trouble("workspace_diagnostics") end, "Workspace Diagnostics")
	-- 							-- stylua: ignore end
	-- 							--
	-- 							if client.server_capabilities.hoverProvider then
	-- 								bufkeymap("n", "glk", vim.lsp.buf.hover, "Hover Documentation")
	-- 							end
	-- 							if client.server_capabilities.signatureHelpProvider then
	-- 								bufkeymap({ "i", "n" }, "gls", vim.lsp.buf.signature_help, "Show signature")
	-- 							end
	-- 							if client.server_capabilities.declarationProvider then
	-- 								bufkeymap("n", "glD", vim.lsp.buf.declaration, "Goto [D]eclaration")
	-- 							end
	-- 							if client.server_capabilities.definitionProvider then
	-- 								bufkeymap("n", "gld", vim.lsp.buf.definition, "Go to [d]efinition")
	-- 								-- bufkeymap('n', 'gld', '<Cmd>Telescope lsp_definitions<CR>', '[G]oto [D]efinition')
	-- 							end
	-- 							if client.server_capabilities.typeDefinitionProvider then
	-- 								bufkeymap("n", "glt", vim.lsp.buf.type_definition, "Goto [t]ype definition")
	-- 								-- bufkeymap('n', 'glt', '<Cmd>Telescope lsp_type_definitions<CR>', 'Goto [t]ype definition')
	-- 							end
	-- 							if client.server_capabilities.implementationProvider then
	-- 								bufkeymap("n", "gli", vim.lsp.buf.implementation, "Goto [i]mplementation")
	-- 								-- bufkeymap('n', 'gli', '<Cmd>Telescope lsp_implementations<CR>', 'Goto [i]mplementation')
	-- 							end
	--
	-- 							-- bufkeymap('n', 'glr', '<Plug>(CodeAction, implementation, rename, references)', 'CodeAction, implementation, rename, references')
	-- 							if client.server_capabilities.referencesProvider then
	-- 								-- bufkeymap('n', 'gr', vim.lsp.buf.references, 'List references')
	-- 								bufkeymap("n", "glr", "<cmd>Telescope lsp_references<CR>", "Goto [r]eferences")
	-- 								-- bufkeymap('n', 'glr', '<Cmd>Telescope lsp_references<CR>', '[G]oto [R]eferences')
	-- 							end
	-- 							if client.server_capabilities.renameProvider then
	-- 								-- bufkeymap('n', '<F2>', vim.lsp.buf.rename, 'Rename symbol')
	-- 								bufkeymap("n", "glR", vim.lsp.buf.rename, "[R]ename")
	-- 							end
	-- 							if client.server_capabilities.codeActionProvider then
	-- 								bufkeymap("n", "gla", vim.lsp.buf.code_action, "Code [a]ction")
	-- 							end
	--
	-- 							if client.server_capabilities.documentSymbolProvider then
	-- 								bufkeymap("n", "glwd", vim.lsp.buf.document_symbol, "[D]ocument symbols")
	-- 								-- bufkeymap('n', 'glwd', <Cmd>Telescope lsp_document_symbols<CR>, '[D]ocument [S]ymbols')
	-- 							end
	-- 							if client:supports_method("workspace/symbol") then
	-- 								-- if client.server_capabilities.workspaceSymbolProvider then
	-- 								bufkeymap("n", "glww", vim.lsp.buf.workspace_symbol, "List [w]orkspace symbols")
	-- 								-- bufkeymap('n', 'glww', require('telescope.builtin').lsp_dynamic_workspace_symbols, '[W]orkspace [S]ymbols')
	-- 							end
	-- 							if client.server_capabilities.workspace then
	-- 								bufkeymap("n", "glwa", vim.lsp.buf.add_workspace_folder, "Workspace [a]dd folder")
	-- 								bufkeymap(
	-- 									"n",
	-- 									"glwr",
	-- 									vim.lsp.buf.remove_workspace_folder,
	-- 									"Workspace [r]emove folder"
	-- 								)
	-- 								bufkeymap("n", "glwl", function()
	-- 									print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
	-- 								end, "[W]orkspace [L]ist folders")
	-- 							end
	-- 							--
	-- 							if client.supports_method("textDocument/switchSourceHeader") then
	-- 								bufkeymap(
	-- 									"n",
	-- 									"glws",
	-- 									"<cmd>LspClangdSwitchSourceHeader<cr>",
	-- 									"[S]witch Source/Header (C/C++)"
	-- 								)
	-- 							end
	--
	-- 							if client.supports_method("textDocument/formatting") then
	-- 								-- if client.server_capabilities.documentFormattingProvider then
	-- 								bufkeymap({ "n", "x" }, "glf", function()
	-- 									vim.lsp.buf.format({ bufnr = bufnr, async = true })
	-- 									-- require('conform').format({ bufnr = bufnr, async = true })
	-- 								end, "[f]ormat buffer")
	-- 							end
	-- 							--
	-- 							if client.server_capabilities.inlayHintProvider and vim.lsp.inlay_hint then
	-- 								bufkeymap("n", "glh", function()
	-- 									vim.lsp.inlay_hint.enable(
	-- 										not vim.lsp.inlay_hint.is_enabled({ bufnr = bufnr }),
	-- 										{ bufnr = bufnr }
	-- 									)
	-- 								end, "[h]ints toggle")
	-- 								------------------------------------------------------------------------------
	-- 							end
	-- 						end
	-- 						--
	-- 						vim.lsp.handlers["textDocument/publishDiagnostics"] =
	-- 							vim.lsp.with(vim.lsp.diagnostic.on_publish_diagnostics, {
	-- 								signs = true,
	-- 								underline = true,
	-- 								virtual_text = {
	-- 									spacing = 5,
	-- 									min = vim.diagnostic.severity.HINT,
	-- 								},
	-- 								update_in_insert = true,
	-- 							})
	-- 						--
	-- 						vim.cmd([[autocmd FileType * set formatoptions-=ro]])
	-- 						--
	-- 					end,
	-- 				})
	-- 				-- --> End LspAttach autocommand
	-- 			end,
	-- 		},
	-- 		{
	-- 			"folke/trouble.nvim",
	-- 			event = "LspAttach",
	-- 			opts = {
	-- 				focus = true,
	-- 				auto_open = false,
	-- 				auto_jump = false,
	-- 				auto_refresh = false,
	-- 			},
	-- 		},
	-- 		{ "j-hui/fidget.nvim", opts = {} }, -- status bottom right
	-- 	},
	-- },
	--
	{
		"nvim-tree/nvim-tree.lua",
		version = "*",
		lazy = false,
		dependencies = {
			"nvim-tree/nvim-web-devicons",
		},
		config = function()
			require("nvim-tree").setup({})
		end,
	},

	{
		"batoaqaa/nvim-platformio.lua",
		cond = function()
			-- local platformioRootDir = vim.fs.root(vim.fn.getcwd(), { 'platformio.ini' }) -- cwd and parents
			local platformioRootDir = (vim.fn.filereadable("platformio.ini") == 1) and vim.fn.getcwd() or nil
			if platformioRootDir and vim.fs.find(".pio", { path = platformioRootDir, type = "directory" })[1] then
				-- if platformio.ini file and .pio folder exist in cwd, enable plugin to install plugin (if not istalled) and load it.
				vim.g.platformioRootDir = platformioRootDir
			elseif (vim.uv or vim.loop).fs_stat(vim.fn.stdpath("data") .. "/lazy/nvim-platformio.lua") == nil then
				-- if nvim-platformio not installed, enable plugin to install it first time
				vim.g.platformioRootDir = vim.fn.getcwd()
			else -- if nvim-platformio.lua installed but disabled, create Pioinit command
				vim.api.nvim_create_user_command(
					"Pioinit",
					function() --available only if no platformio.ini and .pio in cwd
						vim.api.nvim_create_autocmd("User", {
							pattern = { "LazyRestore", "LazyLoad" },
							once = true,
							callback = function(args)
								if args.match == "LazyRestore" then
									require("lazy").load({ plugins = { "nvim-platformio.lua" } })
								elseif args.match == "LazyLoad" then
									vim.notify("PlatformIO loaded", vim.log.levels.INFO, { title = "PlatformIO" })
									vim.cmd("Pioinit")
								end
							end,
						})
						vim.g.platformioRootDir = vim.fn.getcwd()
						require("lazy").restore({ plguins = { "nvim-platformio.lua" }, show = false })
					end,
					{}
				)
			end
			return vim.g.platformioRootDir ~= nil
		end,
		dependencies = {
			{ "akinsho/toggleterm.nvim" },
			{ "nvim-telescope/telescope.nvim" },
			{ "nvim-telescope/telescope-ui-select.nvim" },
			{ "nvim-lua/plenary.nvim" },
			{ "folke/which-key.nvim" },
			{
				"mason-org/mason-lspconfig.nvim",
				dependencies = {
					{ "mason-org/mason.nvim" },
					{ "folke/trouble.nvim" },
					{ "j-hui/fidget.nvim" }, -- status bottom right
				},
			},
		},
	},
}
----------------------------------------------------------------------------------------

require("lazy").setup(plugins, {
	install = {
		missing = true,
	},
})
----------------------------------------------------------------------------------------

-- platformio config
local pioConfig = {
	lspClangd = {
		enabled = true,
		attach = {
			enabled = true,
			keymaps = true,
		},
	},
	-- menu_key = "<leader>\\", -- replace this menu key  to your convenience
	-- menu_name = "PlatformIO", -- replace this menu name to your convenience
	-- debug = false,
}
local pok, platformio = pcall(require, "platformio")
if pok then
	-- print("here" .. vim.inspect(pioConfig))
	platformio.setup(pioConfig)
end
