return {
  {
    "echasnovski/mini.comment",
    lazy = false,
    config = function()
      local key = "<D-/>"
      require("mini.comment").setup({
        mappings = {
          comment = key,
          comment_visual = key,
          comment_line = key,
        },
      })
    end,
  },
}
