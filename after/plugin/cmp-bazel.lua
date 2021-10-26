local Job = require "plenary.job"
local cmp = require "cmp"

local source = {}

source.new = function()
    local self = setmetatable({}, {__index = source})
    return self
end

source.get_trigger_characters = function()
    return {":", "/"}
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
    return file_exists(dirname .. "/" .. package .. "/BUILD") or file_exists(dirname .. "/" .. package .. "/BUILD.bazel")
end

local function is_not_hidden(name)
    return name:sub(1, 1) ~= "."
end

local function get_currently_typed_label(current_line_to_cursor)
    local target_column = vim.regex(("//")):match_str(current_line_to_cursor)
    if not target_column then
        return nil
    end
    return string.sub(current_line_to_cursor, target_column + 3)
end


local function complete_dir(dir, items)
    table.insert(
        items,
        {
            label = dir,
            insertText = dir .. "/",
            kind = cmp.lsp.CompletionItemKind.Folder
        }
    )
end

local function complete_package(package, items)
    table.insert(
        items,
        {
            label = package .. ":",
            kind = cmp.lsp.CompletionItemKind.Module
        }
    )
end

local function get_dir(target)
    local root_dir = vim.fn.getcwd()
    local index = string.find(target, "/[^/]*$")
    if not index or index < 2 then
        return root_dir
    end
    return root_dir .. "/" .. string.sub(target, 1, index)
end

source._complete_folders = function(_, target, callback)
    local dirname = get_dir(target)
    local fs, err = vim.loop.fs_scandir(dirname)
    if err then
        return callback()
    end

    local items = {}

    while true do
        local name, type, e = vim.loop.fs_scandir_next(fs)
        if e then
            return callback()
        end
        if not name then
            break
        end

        -- Create items
        if is_not_hidden(name) then
            if type == "directory" then
                complete_dir(name, items)
                if is_bazel_package(dirname, name) then
                    complete_package(name, items)
                end
            end
        end
    end
    callback(items)
end

source._complete_bazel_labels = function(_, target, callback)
    Job:new(
        {
            "bazel",
            "query",
            "--keep_going",
            "--noshow_progress",
            "--output=label",
            "kind('rule', '//" .. target .. "*')",
            on_exit = function(job)
                local result = job:result()
                local items = {}
                for _, item in ipairs(result) do
                    table.insert(items, {label = item .. '",', kind = cmp.lsp.CompletionItemKind.Field})
                end
                callback({items = items, isIncomplete = false})
            end
        }
    ):start()
end

source.complete = function(self, params, callback)
    local target = get_currently_typed_label(params.context.cursor_before_line)
    if not target then
        return callback()
    end
    if ends_with_colon(target) then
        self:_complete_bazel_labels(target, callback)
    else
        self:_complete_folders(target, callback)
    end
end

require("cmp").register_source("bazel", source.new())

