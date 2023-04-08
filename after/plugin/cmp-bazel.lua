local Job = require("plenary.job")
local cmp = require("cmp")

local source = {}

source.new = function()
	local self = setmetatable({}, { __index = source })
	return self
end

source.get_trigger_characters = function()
	return { ":", "/", '"' }
end

source.is_available = function()
	return vim.bo.filetype == "bzl"
end

local function ends_with_colon(target)
	return vim.regex(":$"):match_str(target)
end

local function file_exists(name)
	local f = io.open(name, "r")
	if f ~= nil then
		io.close(f)
		return true
	else
		return false
	end
end

local function is_bazel_package(dirname, package)
	return file_exists(dirname .. "/" .. package .. "/BUILD")
		or file_exists(dirname .. "/" .. package .. "/BUILD.bazel")
end

local function is_not_hidden(name)
	return name:sub(1, 1) ~= "."
end

local function get_currently_typed_label(current_line_to_cursor)
	local target_column = vim.regex("//"):match_str(current_line_to_cursor)
	if not target_column then
		return nil
	end
	return string.sub(current_line_to_cursor, target_column + 3)
end

local function complete_dir(dir, items)
	table.insert(items, {
		label = dir,
		insertText = dir .. "/",
		kind = cmp.lsp.CompletionItemKind.Folder,
	})
end

local function complete_package(package, items)
	table.insert(items, {
		label = package .. ":",
		kind = cmp.lsp.CompletionItemKind.Module,
	})
end

local function complete_file(name, items)
	table.insert(items, {
		label = name,
		insertText = name .. '",',
		kind = cmp.lsp.CompletionItemKind.File,
	})
end

local function get_bazel_workspace(bufnr)
	local buf_dir = vim.fn.expand(("#%d:p:h"):format(bufnr))
	local workspace = buf_dir
	while 1 do
		if vim.fn.filereadable(workspace .. "/WORKSPACE") == 1 then
			break
		end
		if workspace == "/" then
			return buf_dir
		end
		workspace = vim.fn.fnamemodify(workspace, ":h")
	end
	return workspace
end

local function get_dir(workspace, target)
	local index = string.find(target, "/[^/]*$")
	if not index or index < 2 then
		return workspace
	end
	return workspace .. "/" .. string.sub(target, 1, index)
end

local function get_sub_dir_of_packages(bufnr, typed_text)
	local buf_dir = vim.fn.expand(("#%d:p:h"):format(bufnr))
	local index = string.find(typed_text, "/[^/]*$")
	if not index then
		return buf_dir
	end
	return buf_dir .. "/" .. string.sub(typed_text, 1, index)
end

local function quotation_mark_closed(text_after_first_quotation_mark)
	return vim.regex('"'):match_str(text_after_first_quotation_mark)
end

local function get_text_after_first_quotation_mark(line)
	local index = vim.regex('"'):match_str(line)
	if not index then
		return nil
	end
	return string.sub(line, index + 2)
end

source._complete_from_filesystem = function(_, dir, cmp_callback, ft_callback)
	local fs, err = vim.loop.fs_scandir(dir)
	if err then
		return cmp_callback()
	end

	local items = {}

	while true do
		local name, type, e = vim.loop.fs_scandir_next(fs)
		if e then
			return cmp_callback()
		end
		if not name then
			break
		end

		-- Create items
		if is_not_hidden(name) then
			ft_callback(dir, name, type, items)
		end
	end
	cmp_callback(items)
end

source._complete_directories = function(self, workspace, label, cmp_callback)
	local directory_callback = function(dir, name, type, items)
		if type == "directory" then
			complete_dir(name, items)
			if is_bazel_package(dir, name) then
				complete_package(name, items)
			end
		end
	end
	self:_complete_from_filesystem(get_dir(workspace, label), cmp_callback, directory_callback)
end

source._complete_package_files = function(self, text, bufnr, cmp_callback)
	local files_callback = function(_, name, type, items)
		if type == "directory" then
			complete_dir(name, items)
		elseif type == "file" then
			complete_file(name, items)
		end
	end
	self:_complete_from_filesystem(get_sub_dir_of_packages(bufnr, text), cmp_callback, files_callback)
end

source._complete_bazel_labels = function(_, workspace, label, callback)
	Job:new({
		"bazel",
		"query",
		"--keep_going",
		"--noshow_progress",
		"--output=label",
		"kind('rule', '//" .. label .. "*')",
		cwd = workspace,
		on_exit = function(job)
			local result = job:result()
			local items = {}
			for _, item in ipairs(result) do
				table.insert(items, { label = item .. '",', kind = cmp.lsp.CompletionItemKind.Field })
			end
			callback({ items = items, isIncomplete = false })
		end,
	}):start()
end

source.complete = function(self, params, callback)
	local text = get_text_after_first_quotation_mark(params.context.cursor_before_line)
	if not text or quotation_mark_closed(text) then
		return callback()
	end

	local label = get_currently_typed_label(params.context.cursor_before_line)
	if not label then
		return self:_complete_package_files(text, params.context.bufnr, callback)
	end
	local workspace = get_bazel_workspace(params.context.bufnr)
	if ends_with_colon(label) then
		self:_complete_bazel_labels(workspace, label, callback)
	else
		self:_complete_directories(workspace, label, callback)
	end
end

require("cmp").register_source("bazel", source.new())
