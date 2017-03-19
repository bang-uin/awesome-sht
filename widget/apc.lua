
--[[
												                        
	 Sht        
												                        
--]]

local newtimer   = require("lain.helpers").newtimer
local async      = require("lain.helpers").async
local focused    = require("awful.screen").focused
local naughty    = require("naughty")
local wibox      = require("wibox")

-- APC infos
-- sht.widget.apc

local function factory(args)
    local apc       = { widget = wibox.widget.textbox() }
    local args      = args or {}
    local timeout   = args.timeout or 300
    local followtag = args.followtag or false
    local settings  = args.settings or function() end
    local full_out  = "N/A"

    apc_now = {
        perc        = "N/A",
        time_left   = "N/A"
    }    

    function apc.show(t_out)
        apc.hide()

        local preset = {
            sceen = (apc.followtag and focused()) or 1
        }
        
        if not apc.full_out then
            apc.update()
        end

        apc.notification = naughty.notify({
            text    = apc.full_out,
            timeout = t_out,
            preset  = preset
        })
    end

    function apc.hide()
        if apc.notification then
            naughty.destroy(apc.notification)
            apc.notification = nil
        end
    end

    function apc.attach(obj)
        obj:connect_signal("mouse::enter", function()
            apc.show(0)
        end)
        obj:connect_signal("mouse::leave", function()
            apc.hide()
        end)
    end

    function apc.update()                
        async("/sbin/apcaccess -u", function(stdout)
            apc.full_out = stdout
        end)

        async("/sbin/apcaccess -p BCHARGE -u", function(stdout)
            apc_now.perc = string.gsub(stdout, "\n", "")

            async("/sbin/apcaccess -p TIMELEFT -u", function(stdout)
                apc_now.time_left = string.gsub(stdout, "\n", "")

                widget = apc.widget
                settings()
            end)
        end)               
    end

    apc.attach(apc.widget)

    newtimer("apc", timeout, apc.update)

    return apc
end

return factory
