return {
  "ojroques/nvim-osc52",
  config = function()
    local osc52 = require("osc52")
    osc52.setup({
      silent = true,
      trim = false,
    })

    -- Route the +/* registers through OSC 52 so yanks/pastes reach the
    -- host clipboard when editing inside an SSH session.
    if vim.env.SSH_TTY or vim.env.SSH_CONNECTION then
      vim.g.clipboard = {
        name = "osc52",
        copy = {
          ["+"] = osc52.copy,
          ["*"] = osc52.copy,
        },
        paste = {
          ["+"] = osc52.paste,
          ["*"] = osc52.paste,
        },
      }
    end
  end,
}
