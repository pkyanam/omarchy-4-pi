local paths = require("default.hypr.paths")
local detector = paths.omarchy_path .. "/bin/omarchy-hw-raspberry-pi"

-- V3D is an integrated, resource-constrained GPU. Aquamarine documents this
-- switch for limited hardware where DRM buffer modifiers cause scan-out issues.
if o.shell_succeeds(o.shell_quote(detector)) then
  -- Keep floating/titlebar/dock behavior, but do not let mode changes silently
  -- restore shadows. Owners can still enable shadows in their own config.
  o.pi_conservative_graphics = true
  hl.env("AQ_NO_MODIFIERS", "1")
end
