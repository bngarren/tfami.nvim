---@class Tfami.View
---@field win integer|nil Window handle
---@field buf integer|nil Buffer handle
---@field augroup integer Autocommand group
---@field on_close? fun(...): any On close callback
---@field opts Tfami.View.Config View configuration
local View = {}
View.__index = View

---@alias Tfami.WinPos "float" | "split"

---@class Tfami.View.Config
---@field position? Tfami.WinPos (default: "float")
---@field filetype? string Buffer filetype (default: "markdown")
---@field on_close? fun(...): any On close callback

---@class Tfami.View.WinConfig
---@field float? {width: number, height: number, border: string, title: string}
---@field split? {position: string, size: integer}

---@param opts? Tfami.View.Config
---@return Tfami.View
function View.new(opts)
	local self = setmetatable({}, View)
	self.opts = vim.tbl_deep_extend("force", {
		position = "float",
		filetype = "markdown",
	} --[[@as Tfami.View.Config]], opts or {})
	self.win = nil
	self.buf = nil
	self.augroup = vim.api.nvim_create_augroup("TfamiView", { clear = true })
	self.on_close = self.opts.on_close
	return self
end

---@return boolean
function View:is_open()
	return self.win ~= nil and vim.api.nvim_win_is_valid(self.win)
end

---@return integer|nil win Window handle or nil on failure
function View:open()
	if self:is_open() then
		return
	end

	self.buf = self:create_buffer()
	self.win = self:create_window(self.buf)

	if not self.win then
		return nil
	end

	-- setup window options and autocmds
	self:setup_window()
	self:setup_autocmds()

	return self.win
end

function View:close()
	if self.win and vim.api.nvim_win_is_valid(self.win) then
		vim.api.nvim_win_close(self.win, true)
	end
	self:cleanup()
end

function View:focus()
	vim.schedule(function()
		if self.win and vim.api.nvim_win_is_valid(self.win) then
			vim.api.nvim_set_current_win(self.win)
		end
	end)
end

function View:has_focus()
	return vim.api.nvim_get_current_buf() == self.buf
end

---@return integer buf
function View:create_buffer()
	local buf = vim.api.nvim_create_buf(false, true)

	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].buflisted = false
	vim.bo[buf].swapfile = false
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].filetype = self.opts.filetype

	return buf
end

---@param bufnr integer buffer to display
---@return integer|nil win window handle or nil on failure
function View:create_window(bufnr)
	if self.opts.position == "float" then
		return self:create_float_window(bufnr)
	else
		return self:create_split_window(bufnr)
	end
end

---@param bufnr integer buffer to display
---@return integer|nil win window handle or nil on failure
function View:create_float_window(bufnr)
	local ui = vim.api.nvim_list_uis()[1]
	if not ui then
		return nil
	end

	local width = math.min(60, math.floor(ui.width * 0.5))
	local height = math.min(20, math.floor(ui.height * 0.4))

	-- position relative to cursor
	local row = 1
	local col = 0

	-- enough space below cursor?
	local win_line = vim.fn.winline() -- cursor line in window (1-indexed)
	local win_height = vim.api.nvim_win_get_height(0)

	if win_line + height + 2 > win_height then
		-- not enough space below, place above
		row = -(height + 1)
	end

	local win_width = vim.api.nvim_win_get_width(0)
	local win_col = vim.fn.wincol() -- cursor column in window (1-indexed)

	if win_col + width > win_width then
		-- not enough space to the right, shift left
		col = -(width - (win_width - win_col))
	end

	local win_opts = {
		relative = "cursor",
		anchor = "NW",
		width = width,
		height = height,
		row = row,
		col = col,
		style = "minimal",
		border = { "╭", "─", "╮", "│", "╯", "─", "╰", "│" },
		title = { { " tf am i? ", "FloatTitle" } },
		title_pos = "center",
		zindex = 50,
	}

	return vim.api.nvim_open_win(bufnr, false, win_opts)
end

---@param bufnr integer buffer to display
---@return integer|nil win window handle or nil on failure
function View:create_split_window(bufnr)
	local win
	vim.api.nvim_win_call(0, function()
		vim.cmd("noautocmd silent noswapfile vertical rightbelow 80split")
		vim.api.nvim_win_set_buf(0, bufnr)
		win = vim.api.nvim_get_current_win()
	end)
	return win
end

function View:setup_window()
	if not self.win then
		return
	end

	vim.wo[self.win].number = false
	vim.wo[self.win].relativenumber = false
	vim.wo[self.win].signcolumn = "no"
	vim.wo[self.win].foldcolumn = "0"
	vim.wo[self.win].wrap = true
	vim.wo[self.win].cursorline = true
	vim.wo[self.win].conceallevel = 2
	vim.wo[self.win].concealcursor = "nc"
	vim.wo[self.win].winblend = 0
end

function View:setup_autocmds(opts)
	opts = opts or {}
	if not self.win then
		return
	end

	vim.api.nvim_create_autocmd("WinClosed", {
		group = self.augroup,
		pattern = tostring(self.win),
		once = true,
		callback = function()
			self:cleanup()
			if self.on_close and vim.is_callable(self.on_close) then
				self:on_close()
			end
		end,
	})
end

--- Set buffer content
---@param lines string[] Lines to set
function View:set_content(lines)
	local bufnr = self.buf
	if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
end

--- Get buffer content
---@return string[] lines Buffer lines
function View:get_content()
	local bufnr = self.buf
	if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
		return {}
	end
	return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
end

--- Append lines to buffer
---@param lines string[] Lines to append
function View:append_content(lines)
	local bufnr = self.buf
	if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end
	local current = self:get_content()
	vim.list_extend(current, lines)
	self:set_content(current)
end

--- Clear buffer content
function View:clear_content()
	self:set_content({})
end

function View:cleanup()
	if self.win then
		self.win = nil
	end

	-- clear and delete buffer
	-- NOTE: need wipeout here?
	if self.buf then
		if vim.api.nvim_buf_is_valid(self.buf) then
			vim.api.nvim_buf_delete(self.buf, { force = true })
		end
		self.buf = nil
	end
end

return View
