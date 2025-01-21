return {
  "nanozuki/tabby.nvim",
  enabled = false,
  -- event = 'VimEnter', -- if you want lazy load, see below
  dependencies = "nvim-tree/nvim-web-devicons",
  config = function()
    -- configs...
    require("tabby").setup({
      -- preset = "active_wins_at_tail",
      preset = "tab_with_top_win",
    })
  end,
}
