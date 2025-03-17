-- local blink = require("blink-cmp")
return {
  {
    "saghen/blink.cmp",
    enabled = true,
    opts = {
      completion = { list = { selection = { preselect = false, auto_insert = false } } },
      keymap = {
        preset = "enter",
        ["<Tab>"] = { "select_next", "fallback" },
        ["<S-Tab>"] = { "select_prev", "fallback" },
        ["<Up>"] = { "select_prev", "fallback" },
        ["<Down>"] = { "select_next", "fallback" },
        ["<C-k>"] = { "select_prev" },
        ["<C-j>"] = { "select_next" },
        ["<C-u>"] = { "select_prev", "fallback" },
        ["<C-d>"] = { "select_next", "fallback" },
        -- TODO figure out how make this work :|
        ["<S-Space>"] = { "show", "show_documentation", "hide_documentation" },
      },
    },
  },
}
