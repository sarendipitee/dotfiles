return {
  "folke/snacks.nvim",
  ---@type snacks.Config
  opts = {
    indent = {
      enabled = false,
      only_scope = true, -- only show indent guides of the scope
      only_current = true, -- only show indent guides in the current window
    },
  },
}
