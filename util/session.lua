--[[
	
	Sht

	Session management

--]]

local naughty 		= require("naughty")
local awful 		= require("awful")
local helpers		= require("lain.helpers")
local cjson			= require("cjson")

local session_path 	= "session.txt"
local restoredata_cache = {}
local start_id_cache = {}
local client_map = {}

local function dump(o)
   if type(o) == 'table' then
      local s = '{ \n'
      for k,v in pairs(o) do
         if type(k) ~= 'number' then k = '"'..k..'"' end
         s = s .. '['..k..'] = ' .. dump(v) .. '\n'
      end
      return s .. '} \n'
   else
      return tostring(o)
   end
end

-- Split text into a list consisting of the strings in text,
-- separated by strings matching delimiter (which may be a pattern). 
-- example: strsplit(",%s*", "Anna, Bob, Charlie,Dolores")
local function strsplit(delimiter, text)
	local list = {}
	local pos = 1
	
	if string.find("", delimiter, 1) then -- this would result in endless loops
		error("delimiter matches empty string!")
	end

	while 1 do
		local first, last = string.find(text, delimiter, pos)
		if first then -- found?
			table.insert(list, string.sub(text, pos, first-1))
			pos = last+1
		else
			table.insert(list, string.sub(text, pos))
			break
	  	end
	end

	return list
end

function pairsByKeys (t, f)
    local a = {}
    for n in pairs(t) do table.insert(a, n) end
    table.sort(a, f)
    local i = 0      -- iterator variable
    local iter = function ()   -- iterator function
        i = i + 1
        if a[i] == nil then return nil
        else return a[i], t[a[i]]
        end
    end
    return iter
end

local function save() 
	local screens = {}
	local pids = {}

    -- Iterate screen, tags and clients (json -> screens -> tags -> clients)

    -- Iterate screens
    for s in screen do
        local screen = {
            index = s.index,
            tags = {}
        }

        -- Iterate tags
        for _,t in pairs(s.tags) do
            local tag_clients = t:clients()

            -- Skip empty tags
            if next(tag_clients) ~= nil then
                local tag = {
                    name = t.name,
                    layout = awful.layout.getname(t.layout),
                    clients = {}
                }

                screen.tags[t.index] = tag

                -- Iterate clients
                for i,c in pairsByKeys(tag_clients) do
                    -- Check for valid PID
                    if c.pid then
                        -- Check for duplicate pid
                        if not pids[c.pid] then
                            pids[c.pid] = true

                            --[[
                                Construct pid file path
                                Rely on proc filesystem to make sure the program runs in our space
                            --]]
                            local cmdFile = "/proc/" .. c.pid .. "/cmdline"

                            -- Check for cmdline file
                            if helpers.file_exists(cmdFile) then
                                -- Extract needed information
                                local client = {
                                    pid = c.pid,
                                    tag_index = i,
                                    geometry = c:geometry(),
                                    minimized = c.minimized,
                                    hidden = c.hidden,
                                    visible = c.visible,
                                    opacity = c.opacity,
                                    ontop = c.ontop,
                                    above = c.above,
                                    below = c.below,
                                    fullscreen = c.fullscreen,
                                    maximized = c.maximized,
                                    maximized_vertical = c.maximized_vertical,
                                    maximized_horizontal = c.maximized_horizontal,
                                    sticky = c.sticky,
                                    floating = c.floating
                                }

                                --[[
                                    Extract cmdline (we need to use xargs as spaces are replaced by NULs)
                                    Consider that popen is sync but we need the data now and the command is fast
                                --]]
                                local command = "xargs -0 < " .. cmdFile
                                local handle = io.popen(command)
                                local cmdline = string.gsub(handle:read("*a"), "\n", "")
                                handle:close()

                                cmdline = strsplit(" ", cmdline)
                                client.cmd = cmdline[1]

                                if table.getn(cmdline) > 1 then
                                    client.cmd_args = table.concat(cmdline, " ", 2)
                                end

                                -- Save client
                                tag.clients[client.tag_index] = client
                                print(client.cmd .. " " .. client.tag_index)
                            else
                                naughty.notify({text = "Cannot save client \"" .. c.name .. "\"! NO PID FILE (" .. c.pid .. ")!"})
                            end
                        end
                    else
                        naughty.notify({text = "Cannot save client \"" .. c.name .. "\"! NO PID!"})
                    end
                end
            end
        end

        screens[screen.index] = screen
    end

	-- Serialize clients
	local file = io.open(session_path, "w")
	file:write(cjson.encode(screens))
	file:close()
end


local function apply_layout()
    local sscreens = {}
    local tags = {}

    -- Create sorted screen and tags table
    for s in screen do
        sscreens[s.index] = s
    end

    for _,s in pairs(restoredata_cache) do
        -- Get real screen
        local screen = sscreens[s.index]

        for _,t in pairs(s.tags) do
            -- Get and save real tag
            local tag = awful.tag.find_by_name(screen, t.name)
            tags[t.name] = tag

            -- Set tag layout
            print(t.layout)
            --awful.layout.set(t.layout, tag)

            -- Move clients to their screen and tag
            for _,c in pairs(t.clients) do
                -- Get real client
                local ac = client_map[c.startup_id]

                if ac ~= nil then
                    ac:move_to_screen(screen)
                    ac:tags({ tag })
                    ac.floating = c.floating
                end
            end
        end
    end

    for _,s in pairs(restoredata_cache) do
        for _,t in pairs(s.tags) do
            -- Get real tag
            local tag = tags[t.name]

            -- Sort, place and relayout clients
            for _,c in pairsByKeys(t.clients) do
                -- Get real client
                local ac = client_map[c.startup_id]

                if ac ~= nil then
                    print(c.cmd .. " " .. c.tag_index)

                    if ac.floating then
                        ac:geometry(c.geometry)
                    else
                        ac:swap(tag:clients()[c.tag_index])
                    end

                    ac.fullscreen = c.fullscreen
                    ac.minimized = c.minimized
                    ac.maximized = c.maximized
                    ac.maximized_vertical = c.maximized_vertical
                    ac.maximized_horizontal = c.maximized_horizontal
                    ac.hidden = c.hidden
                    ac.visible = c.visible
                    ac.opacity = c.opacity
                    ac.ontop = c.ontop
                    ac.above = c.above
                    ac.below = c.below
                    ac.sticky = c.sticky

                    client_map[c.startup_id] = nil
                end
            end
        end
    end

    -- Cleanup
    client_map = {}
    restoredata_cache = {}
    start_id_cache = {}
end

local function client_appeared(c)
    -- Check for valid pid
    if c.pid ~= nil then
        -- Extract start id
        local envFile = "/proc/" .. c.pid .. "/environ"
        local command = "xargs -0 < " .. envFile
        local handle = io.popen(command)
        --local s = string.match(handle:read("*a"), session_startup_id_prefix .. "=%d+")
        local s = string.match(handle:read("*a"), "DESKTOP_STARTUP_ID=[%w%d%p]+")
        handle:close()

        -- Transfer data
        if start_id_cache[s] ~= nil then
            client_map[s] = c
            start_id_cache[s] = nil
        end

        -- Apply layout if it is our last element
        if next(start_id_cache) == nil then
            client.disconnect_signal("manage", client_appeared)
            apply_layout()
        end
    end
end

local function restore()
	if helpers.file_exists(session_path) then
		-- Deserialize table
		local json = helpers.first_line(session_path)
        restoredata_cache = cjson.decode(json)

        if restoredata_cache ~= nil and next(restoredata_cache) ~= nil then
		    -- Iterate client states and call spwan
            client.connect_signal("manage", client_appeared)

            -- Iterate screen, tags and clients (json -> screens -> tags -> clients)
            for _,s in pairs(restoredata_cache) do
                for _,t in ipairs(s.tags) do
                    for _,c in pairs(t.clients) do
                        -- naughty.notify({text = "Restoring \"" .. c.cmd .. " " .. c.cmd_args .. "\""})

                        -- Spawn process
                        local _, s = awful.spawn({c.cmd, c.cmd_args})

                        if s ~= nil then
                            s = "DESKTOP_STARTUP_ID=" .. s
                            c.startup_id = s
                            start_id_cache[c.startup_id] = true
                        end
                    end
                end
            end
        else
            naughty.notify({text = "Session is empty" })
        end
	end
end

-- Create and return session object
session = {
	save = save,
	restore = restore
}

return session