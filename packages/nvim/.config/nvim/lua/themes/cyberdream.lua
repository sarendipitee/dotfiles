local config = require("config.theme")
local name = "cyberdream"

return {
  "scottmckendry/cyberdream.nvim",
  lazy = config.theme ~= name,
  priority = 1000,
  opts = {
    transparent = false,
    italic_comments = true,
    terminal_colors = true,
    theme = {
      variant = "auto",
    },
  },
  config = function(_, opts)
    require("cyberdream").setup(opts)
    require("cyberdream").load()
  end,
}
