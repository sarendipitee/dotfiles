return {
  {
    "echasnovski/mini.align",
    version = "*",
    config = function()
      require("mini.align").setup()
    end,
  },
  {
    -- conflicts with blink-cmp
    "echasnovski/mini.pairs",
    version = "*",
    enabled = false,
  },
}
