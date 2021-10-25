local Job = require "plenary.job"
local cmp = require'cmp'

local source = {}

source.new = function()
  local self = setmetatable({}, { __index = source })
  return self
end

source._get_dir = function(_, target)
    local root_dir = vim.fn.getcwd()
    local index = string.find(target, "/[^/]*$")
    if not index or index < 2 then return root_dir end
    return root_dir .. '/' .. string.sub(target, 1, index)
end

source.complete = function(self, params, callback)
    local target_column = vim.regex(('//')):match_str(params.context.cursor_before_line)
    if not target_column then return nil end
    local target = string.sub(params.context.cursor_before_line,  target_column + 3)
    local dir = self:_get_dir(target)

    if vim.regex(':$'):match_str(target) then
    Job
      :new({
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
            table.insert(items, { label = item .. '",', kind = cmp.lsp.CompletionItemKind.Field })
          end
          callback { items = items, isIncomplete = false}
        end,
      })
      :start()
    else
         self:_complete_folders(params, dir, params.offset, function(err, candidates)
           if err then
             return callback()
           end
           callback(candidates)
         end)
    end
end

local function file_exists(name)
   local f=io.open(name,"r")
   if f~=nil then io.close(f) return true else return false end
end

local function is_bazel_package(dirname, name)
    return file_exists(dirname .. '/' .. name .. '/BUILD') or file_exists(dirname .. '/' .. name .. '/BUILD.bazel')
end

source._complete_folders = function(_, params, dirname, offset, callback)
  local fs, err = vim.loop.fs_scandir(dirname)
  if err then
    return callback(err, nil)
  end

  local items = {}


  local include_hidden = string.sub(params.context.cursor_before_line, offset, offset) == '.'
  while true do
    local name, type, e = vim.loop.fs_scandir_next(fs)
    if e then
      return callback(type, nil)
    end
    if not name then
      break
    end

    local accept = false
    accept = accept or include_hidden
    accept = accept or name:sub(1, 1) ~= '.'

    -- Create items
    if accept then
      if type == 'directory' then
        table.insert(items, {
          word = name,
          label = name,
          insertText = name .. '/',
          kind = cmp.lsp.CompletionItemKind.Folder,
        })
        if is_bazel_package(dirname, name) then
            local package = name .. ':'
            table.insert(items, {
              word = package,
              label = package,
              insertText = package,
              kind = cmp.lsp.CompletionItemKind.Module,
            })
        end
      end
    end
  end
  callback(nil, items)
end

source.get_trigger_characters = function()
  return { ':', '/' }
end

source.is_available = function()
  return vim.bo.filetype == "bzl"
end

require("cmp").register_source("bazel", source.new())
