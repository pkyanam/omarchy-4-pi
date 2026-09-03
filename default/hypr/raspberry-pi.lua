local paths = require("default.hypr.paths")
local detector = paths.omarchy_path .. "/bin/omarchy-hw-raspberry-pi"

-- V3D is an integrated, resource-constrained GPU. Aquamarine documents this
-- switch for limited hardware where DRM buffer modifiers cause scan-out issues.
if o.shell_succeeds(o.shell_quote(detector)) then
  hl.env("AQ_NO_MODIFIERS", "1")
end
