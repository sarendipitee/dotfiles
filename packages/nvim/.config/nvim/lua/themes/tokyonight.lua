local config = require("config.theme")
local name = "tokyonight"

---@class Colorscheme
local tokyonight = {
  "folke/tokyonight.nvim",
  lazy = config.theme ~= name,
  priority = 1000,
  opts = function()
    vim.g.lualine_theme = name
    return {
      style = "night",
      transparent = config.transparent,
      terminal_colors = true,
      -- styles = {
      --   keywords = "italic",
      --   functions = {},
      --   variables = {},
      --   sidebars = "dark",
      --   floats = "dark",
      -- },
      sidebars = config.sidebars,
      day_brightness = 0.3,
      hide_inactive_statusline = false,
      dim_inactive = false,
      lualine_bold = true,
      on_highlights = function(hl, c)
        hl.NotifyBackground = { bg = c.bg, fg = c.fg }
        -- hl.Cursor = { fg = c.black, bg = c.fg }
        local prompt = "#2d3149"
        hl.TelescopeNormal = {
          bg = c.bg_dark,
          fg = c.fg_dark,
        }
        hl.TelescopeBorder = {
          bg = c.bg_dark,
          fg = c.bg_dark,
        }
        hl.TelescopePromptNormal = {
          bg = prompt,
        }
        hl.TelescopePromptBorder = {
          bg = prompt,
          fg = prompt,
        }
        hl.TelescopePromptTitle = {
          bg = prompt,
          fg = prompt,
        }
        hl.TelescopePreviewTitle = {
          bg = c.bg_dark,
          fg = c.bg_dark,
        }
        hl.TelescopeResultsTitle = {
          bg = c.bg_dark,
          fg = c.bg_dark,
        }
      end,
      on_colors = function(colors)
        -- colors.border = '#7aa2f7'
        colors.bg = "#0f111a"
      end,
    }
  end,
  config = function(_, opts)
    require("tokyonight").setup(opts)
    require("tokyonight").load()
    vim.api.nvim_set_hl(0, "LspInlayHint", { fg = "#454f70" })
  end,
}

tokyonight.set = function() end

return tokyonight
