--[[
  Rework of https://gist.github.com/zinozzino/6a40fa70d6e916661fdf
--]]

local newtimer     = require("lain.helpers").newtimer

local awful        = require("awful")
local beautiful    = require("beautiful")
local wibox        = require("wibox")

local math         = { modf   = math.modf,
                       floor  = math.floor }
local string       = { format = string.format,
                       match  = string.match,
                       gmatch = string.gmatch,
                       rep    = string.rep }

local tonumber     = tonumber

local setmetatable = setmetatable

-- Pulseaudio volume bar
local pulsebar = {
    default_sink = "",
    step    = 0.03,

    colors = {
        background = beautiful.bg_normal,
        mute       = "#EB8F8F",
        unmute     = "#A4CE8A"
    },

    mixer    = "pavucontrol",

    _current_level = 0,
    _muted         = false
}

local function factory(args)
    local args       = args or {}
    local timeout    = args.timeout or 5
    local settings   = args.settings or function() end

    pulsebar.cmd           = args.cmd or "pacmd"
    pulsebar.default_sink  = args.default_sink or pulsebar.default_sink
    pulsebar.step          = args.step or pulsebar.step
    pulsebar.colors        = args.colors or pulsebar.colors
    pulsebar.followmouse   = args.followmouse or false
    pulsebar.bar_size       = args.bar_size or 18

    pulsebar.text = wibox.widget.textbox()
    pulsebar.text.markup = "<span color=\"" .. pulsebar.colors.mute .. "\">N/A</span>"
    pulsebar.text.align = "center"
    pulsebar.text.valign = "center"

    pulsebar.widget = wibox.widget({
        pulsebar.text,
        layout = wibox.layout.stack
    })

    function pulsebar.update()
        -- Get mixer control contents
        local f = io.popen(pulsebar.cmd .. " dump")

        if f == nil then
            return false
        end    

        local out = f:read("*a")
        f:close()

        default_sink = string.match(out, "set%-default%-sink ([^\n]+)")

        if default_sink == nil then
            default_sink = ""
            pulsebar.default_sink = ""
            return false
        end

        pulsebar.default_sink = default_sink

        local volu
        for sink, value in string.gmatch(out, "set%-sink%-volume ([^%s]+) (0x%x+)") do
            if sink == default_sink then
                volu = tonumber(value) / 0x10000
            end
        end

        local mute
        for sink, value in string.gmatch(out, "set%-sink%-mute ([^%s]+) (%a+)") do
            if sink == default_sink then
                mute = value
            end
        end

        pulsebar._current_level = volu
        int = math.modf(pulsebar._current_level * pulsebar.bar_size)
        local color = pulsebar.colors.unmute

        if not mute and volu == 0 or mute == "yes"
        then
            pulsebar._muted = true
            color = pulsebar.colors.mute
        else
            pulsebar._muted = false
        end

        volume_now = {}
        volume_now.level = math.floor(volu * 100)
        volume_now.status = mute

        pulsebar.text.markup = "<span color=\"" .. color .. "\">["
                .. string.rep("|", int)
                .. string.rep(" ", pulsebar.bar_size - int)
                .. "]</span>"

        widget = pulsebar.widget

        settings()
    end

    function pulsebar.SetVolume(vol)
        if vol > 1 then
            vol = 1
        end

        if vol < 0 then
            vol = 0
        end

        vol = vol * 0x10000

        awful.spawn({pulsebar.cmd, "set-sink-volume " .. pulsebar.default_sink .. " " .. string.format("0x%x", math.floor(vol))})
        pulsebar.update()
    end

    function pulsebar.Up()
        pulsebar.SetVolume(pulsebar._current_level + pulsebar.step)
    end

    function pulsebar.Down()
       	pulsebar.SetVolume(pulsebar._current_level - pulsebar.step)
    end

    function pulsebar.ToggleMute()
        if pulsebar._muted then
            awful.spawn({pulsebar.cmd, "set-sink-mute " .. pulsebar.default_sink .. " 0"})
        else
            awful.spawn({pulsebar.cmd, "set-sink-mute " .. pulsebar.default_sink .. " 1"})
        end

       	pulsebar.update()
    end

    function pulsebar.LaunchMixer()
        awful.spawn({pulsebar.mixer})
    end

    pulsebar.text:buttons (awful.util.table.join (
          awful.button ({}, 1, function()
            pulsebar.ToggleMute()
          end),
          awful.button ({}, 3, function()
            pulsebar.LaunchMixer()
          end),
          awful.button ({}, 4, function()
            pulsebar.Up()
          end),
          awful.button ({}, 5, function()
            pulsebar.Down()
          end)
    ))

    timer_id = string.format("pulsebar-%s-%s", pulsebar.cmd, pulsebar.default_sink)

    newtimer(timer_id, timeout, pulsebar.update)

    return pulsebar
end

return setmetatable(pulsebar, { __call = function(_, ...) return factory(...) end })
