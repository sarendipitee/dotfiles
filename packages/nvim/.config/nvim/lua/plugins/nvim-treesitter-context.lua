return {
  {
    "nvim-treesitter/nvim-treesitter-context",
    enabled = true,
    lazy = false,
    config = function()
      require("treesitter-context").setup({
        multiwindow = true,
        mode = "topline",
      })
      vim.cmd([[
				hi TreesitterContext guibg=none
				hi TreesitterContextLineNumberBottom gui=underline guisp=Grey
			]])
    end,
    keys = {
      {
        "<leader>t",
        function()
          require("treesitter-context").toggle()
        end,
        desc = "Toggle treesitter context",
      },
      {
        "U",
        function()
          require("treesitter-context").go_to_context(vim.v.count1)
        end,
        desc = "Jump <U>p to context",
      },
    },
  },
}
