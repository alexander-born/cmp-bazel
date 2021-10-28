# cmp-bazel

nvim-cmp source for bazel target completion and package files.
Only works if nvim's current working directory is bazel workspace directory.

# Setup

```lua
require'cmp'.setup {
  sources = {
    { name = 'bazel' }
  }
}
```


