local config = require("config.theme")
local name = "apprentice"

local spec = {
  "romainl/Apprentice",
  lazy = config.theme ~= name,
  priority = 1000,
}

return spec
