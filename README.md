# cmp-bazel

nvim-cmp source for bazel target completion and package files.

# Setup

```lua
require'cmp'.setup {
  sources = {
    { name = 'bazel' }
  }
}
```
or with lazy.nvim
```lua
  {
    "hrsh7th/nvim-cmp",
    dependencies = { "alexander-born/cmp-bazel" },
    opts = function(_, opts)
      opts.sources = require("cmp").config.sources(vim.list_extend(opts.sources, { { name = "bazel" } }))
    end,
  },
```


