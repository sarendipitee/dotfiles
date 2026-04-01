return {
  {
    "nvim-mini/mini.align",
    version = "*",
    config = function()
      require("mini.align").setup()
    end,
  },
  {
    -- conflicts with blink-cmp
    "nvim-mini/mini.pairs",
    version = "*",
    enabled = false,
  },
}
