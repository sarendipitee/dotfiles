-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here
--

-- don't automatically convert tabs to spaces
vim.opt.expandtab = false

-- don't "show"" hidden characters with ascii
vim.opt_global.list = false

-- don't highlight the entire current line
vim.opt_global.cursorline = false

-- show tabline only if needed
vim.opt.showtabline = 1

vim.opt.relativenumber = false

vim.diagnostic.config({
  -- Use the default configuration
  -- virtual_lines = true,
  virtual_text = { current_line = true },
})
