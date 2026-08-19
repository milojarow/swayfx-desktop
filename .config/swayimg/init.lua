---@diagnostic disable: undefined-global
-- Disable info overlay (file/format/size/scale shown on open)
-- The text layer reappears whenever a new image loads; emptying the
-- block schemes keeps it from rendering anything regardless of timeout.
swayimg.viewer.set_text("topleft", {})
swayimg.viewer.set_text("topright", {})
swayimg.viewer.set_text("bottomleft", {})
swayimg.viewer.set_text("bottomright", {})
