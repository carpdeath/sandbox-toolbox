local log = require("toolbox.core.log")
local M = {}
function M.install()
    local lifecycle = require("ModMenu.shell.lifecycle")
    local build = require("ModMenu.shell.build")
    local open, close, ensure = lifecycle.Open, lifecycle.Close, build.Ensure
    local startPoll = lifecycle.StartPoll
    lifecycle.StopPoll = function(_) end
    lifecycle.StartPoll = function(S)
        if S.pollHandle ~= nil then return end
        startPoll(S)
    end
    build.Ensure = function(S)
        log.debug("Ensure widgets begin")
        local done = log.timer("TIMING Ensure (create shell + all sections, 0 when already built)")
        local result = ensure(S)
        done()
        log.debug("Ensure widgets end")
        return result
    end
    lifecycle.Open = function(S, opts)
        log.debug("Open begin")
        local done = log.timer("TIMING Open total")
        open(S, opts)
        done()
        log.debug("Open end")
    end
    lifecycle.Close = function(S)
        local done = log.timer("TIMING Close total")
        close(S)
        require("toolbox.ui.window_drag").showTooltip(nil)
        done()
        log.debug("Closed; widget tree kept")
    end
end
return M
