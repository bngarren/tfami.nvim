local View = require("tfami.view")

---@class Tfami
---@overload fun(opts?: Tfami.Config): integer -- win id
local M = setmetatable({}, {
	__call = function(M, ...)
		return M.open(...)
	end,
})

local H = {} -- helper

--- Module setup
---
--- @param opts table|nil Module config table. See |M.config|
function M.setup(opts)
	-- export module to global
	_G.Tfami = M

	opts = H.setup_config(opts)
	H.apply_config(opts)

	H.create_autocommands()

	H.create_user_commands()

	return true
end

---@class Tfami.Config

M.config = {}

-- Public API functions ==============================================================

---@class Tfami.OpenOpts
---@field position? string "split" | "float" (default: "float")

function M.open(opts)
	opts = opts or {}

	local position = opts.position or "float"

	if H.view and not H.view:is_open() then
		H.view = nil
	end

	if not H.view then
		H.view = View.new({
			position = position,
			on_close = function()
				H.view = nil
			end,
		})
	else
		-- View is already open
		if H.view:is_open() then
			if not H.view:has_focus() then
				H.view:focus()
			end
		else
			H.notify(vim.log.levels.DEBUG, "Hmm..View is already open, win=%s, buf=%s", H.view.win, H.view.buf)
		end
	end

	return H.view:open()
end

function M.close()
	if H.view then
		H.view:close()
		H.view = nil
	end
end

--- @param opts Tfami.OpenOpts
function M.toggle(opts)
	if H.view and H.view:is_open() then
		M.close()
	else
		M.open(opts)
	end
end

-- Utility functions =================================================================

-- Helper module =====================================================================

H.default_config = vim.deepcopy(M.config)

H.ns_id = {}

H.setup_config = function(config)
	config = vim.tbl_deep_extend("force", vim.deepcopy(H.default_config), config or {})

	-- validate here

	return config
end

H.apply_config = function(config)
	M.config = config

	-- make mappings...
end

H.create_autocommands = function()
	H.augroup = vim.api.nvim_create_augroup("Tfami", {})

	-- local au_cmd = function(event, pattern, callback, desc)
	-- 	vim.api.nvim_create_autocmd(event, { group = gr, pattern = pattern, callback = callback, desc = desc })
	-- end

	-- autocommands...
end

-- User commands ------------------------------------------
H.create_user_commands = function()
	vim.api.nvim_create_user_command("Tfami", H.dispatch_cmd, {
		nargs = "+",
		desc = "Tfami entrypoint: :Tfami <subcommand> [args] [key=value ...]",
		complete = H.complete_subcommands,
	})
end

H.subcommands = {
	open = {
		run = function(_, opts, _)
			M.open({ position = opts.position })
		end,
		desc = "Open Tfami",
	},
	close = {
		run = function(_, _, _)
			M.close()
		end,
		desc = "Close Tfami",
	},
	toggle = {
		run = function(_, opts, _)
			M.toggle({ position = opts.position })
		end,
		desc = "Toggle Tfami",
	},
}

function H.dispatch_cmd(input)
	local fargs = input.fargs
	local name = fargs[1]
	if not name then
		return H.error("Missing subcommand.")
	end

	local handler = H.subcommands[name]
	if not handler or not vim.is_callable(handler.run) then
		H.notify(vim.log.levels.INFO, "Unknown subcommand '%s'.", name)
	end

	local args, opts = H.command_parse_fargs(fargs, 2)
	handler.run(args, opts, input)
end

H.command_parse_fargs = function(fargs, from_idx)
	local args, opts = {}, {}
	for i = from_idx, #fargs do
		local token = H.expandcmd(fargs[i])
		-- key can include letters, digits, underscores, and dashes; value is anything after '='
		local k, v = token:match("^([%w_%-]+)=(.+)$")
		if k then
			opts[k] = v
		else
			table.insert(args, token)
		end
	end
	return args, opts
end

function H.complete_subcommands(arg_lead, cmdline, cursorpos)
	-- split the part of the cmdline up to the cursor
	local before = cmdline:sub(1, cursorpos)
	local parts = vim.split(before, "%s+", { trimempty = true })
	-- parts[1] = ":CodeAnchors", parts[2] = subcommand (maybe), parts[3+] = args
	if #parts <= 1 then
		-- complete subcommand names
		local seen, out = {}, {}
		local function add(name)
			if not seen[name] and name:find("^" .. vim.pesc(arg_lead)) then
				table.insert(out, name)
				seen[name] = true
			end
		end
		for name, _ in pairs(H.subcommands) do
			add(name)
		end
		table.sort(out)
		return out
	end

	-- delegate to subcommand completer if present
	local sub = parts[2]
	local entry = H.subcommands[sub]
	if entry and vim.is_callable(entry.complete) then
		return entry.complete(arg_lead, cmdline, cursorpos)
	end
	return {}
end

H.error = function(msg)
	error("(tfami) " .. msg, 0)
end

H.expandcmd = function(x)
	local ok, res = pcall(vim.fn.expandcmd, x)
	return ok and res or x
end

function H.notify(level, msg, ...)
	vim.notify("tfami: " .. string.format(msg, ...), level)
end

return M
