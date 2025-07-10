return {
  "stevearc/conform.nvim",
  event = { "BufWritePre" },
  cmd = { "ConformInfo" },
  keys = {},
  -- This will provide type hinting with LuaLS
  ---@module "conform"
  ---@type conform.setupOpts
  opts = {
    -- Define your formatters
    formatters_by_ft = {
      -- lua = { "stylua" },
      -- python = { "isort", "black" },
      javascript = { "biome", stop_after_first = true },
      javascriptreact = { "biome", stop_after_first = true },
      typescript = { "biome", stop_after_first = true },
      typescriptreact = { "biome", stop_after_first = true },
    },
  },
  -- init = function()
  --   -- If you want the formatexpr, here is the place to set it
  --   vim.o.formatexpr = "v:lua.require'conform'.formatexpr()"
  -- end,
}
