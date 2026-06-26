-- Neovim helper for zsh-snippets.
--
-- Opened by the zsh plugin on a scratch file containing a snippet's raw
-- content (e.g. `kill -9 <id>`). Each `<placeholder>` is converted to a
-- LuaSnip jump node so the user can fill them in with the usual jump
-- keybindings. On `:wq` the buffer text is written back to the scratch
-- file, which the zsh side reads into the prompt.
--
-- This module is discovered by adding the plugin directory to nvim's
-- 'runtimepath' (the zsh side does that via `+set runtimepath+=...`),
-- so `require("zsh-snippets")` resolves to this file.

local M = {}

local function load_luasnip()
	local ok, mod = pcall(require, "luasnip")
	if ok then
		return true, mod
	end
	-- Best effort: trigger a lazy-loaded LuaSnip (lazy.nvim) and retry.
	if package.loaded.lazy then
		pcall(function() require("lazy").load({ plugins = { "LuaSnip" } }) end)
		return pcall(require, "luasnip")
	end
	return false, nil
end

local ls_ok, ls = load_luasnip()
M.luasnip_available = ls_ok

--- Convert `<name>` placeholders to LSP `${n:name}` tabstops.
--- Returns the converted string and the number of placeholders found.
local function to_lsp(body)
	local count = 0
	-- One or more chars, none of them `<`, `>` or whitespace.
	local converted = body:gsub("<([^<>%s]+)>", function(name)
		count = count + 1
		return "${" .. count .. ":" .. name .. "}"
	end)
	return converted, count
end

--- Entry point invoked from the command line:
---   nvim <file> "+lua require('zsh-snippets').edit()"
function M.edit()
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	local content = table.concat(lines, "\n")

	-- Light-touch UX: shell highlighting, no swap/backup clutter.
	vim.bo.filetype = "sh"
	vim.opt_local.swapfile = false
	vim.opt_local.backup = false
	vim.opt_local.writebackup = false

	local lsp_body, n = to_lsp(content)

	if not M.luasnip_available then
		vim.api.nvim_echo({
			{ "zsh-snippets: luasnippet not found; edit freely, then :wq.\n", "WarningMsg" },
		}, true, {})
		return
	end
	if n == 0 then
		return -- no placeholders, nothing to jump through
	end

	-- Clear the buffer so lsp_expand lays the snippet down from row 1.
	vim.api.nvim_buf_set_lines(0, 0, -1, false, {})

	-- Defer the expand so `startinsert` settles before LuaSnip places the
	-- cursor at the first tabstop. pcall guards against malformed bodies.
	vim.schedule(function()
		vim.cmd("startinsert")
		local ok, err = pcall(require("luasnip").lsp_expand, lsp_body)
		if not ok then
			-- Fallback: drop the LSP-syntax text verbatim so the user can edit.
			vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split(lsp_body, "\n"))
			vim.api.nvim_echo({
				{ "zsh-snippets: luasnip expand failed: " .. tostring(err) .. "\n", "WarningMsg" },
			}, true, {})
		end
	end)

	vim.api.nvim_echo({
		{ "zsh-snippets: fill the placeholders, then ", "Normal" },
		{ ":wq", "Special" },
		{ " to send the command back to the shell.", "Normal" },
	}, true, {})
end

return M
