--[[
	
	Sht

	Session management

--]]

local naughty 		= require("naughty")
local awful 		= require("awful")
local helpers		= require("lain.helpers")
local cjson			= require("cjson")
local session_path 	= "session.txt"

local clients_restore_cache = {}

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

local function save() 
	clients = {}
	pids = {}

	-- Iterate clients
	for _, c in ipairs(client.get()) do
		-- Check for valid PID
		if c.pid then
			-- Check for duplicate pid
			if not pids[c.pid] then
				pids[c.pid] = true

				-- Construct pid file path
				local cmdFile = "/proc/" .. c.pid .. "/cmdline"

				-- Check for cmdline file
				if helpers.file_exists(cmdFile) then
					-- Extract needed information
					local state = {
						pid = c.pid,
						instance = c.instance,
						class = c.class,
						screen = c.screen.index,
						tags = (function() 
									local tags = {}
									for k,t in pairs(c:tags()) do
										table.insert(tags, t.index)
									end

									return tags 
								end)(),
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
						floating = c.floating,
						size_hints = c.size_hints
					}
				
					-- Extract cmdline (we need to use xargs as spaces are replaced by NULs)
					-- Consider that popen is sync but we need the data now and the command is fast
					local command = "xargs -0 < " .. cmdFile
					local handle = io.popen(command)
					local cmdline = string.gsub(handle:read("*a"), "\n", "")
					handle:close()

					cmdline = strsplit(" ", cmdline)
					state.cmd = cmdline[1]
					state.cmd_args = table.concat(cmdline, " ", 2)

					-- Save client
					table.insert(clients, state)
				else
					naughty.notify({text = "Cannot save client \"" .. c.name .. "\"! NO PID FILE (" .. c.pid .. ")!"})
				end
			end
		else
			naughty.notify({text = "Cannot save client \"" .. c.name .. "\"! NO PID!"})
		end
	end

	-- Serialize clients
	local file = io.open(session_path, "w")
	file:write(cjson.encode(clients))
	file:close()
end

local function spawn(restoredata, screens)
	-- Spawn process
	local new_pid = awful.spawn({restoredata.cmd, restoredata.cmd_args}, true, function(c) naughty.notify({text = c.pid}) end)

	clients_restore_cache[new_pid] = { ["1"] = restoredata, ["2"] = screens }

	-- Set layout rules for new client
	table.insert(awful.rules.rules,
				{ 
					rule = { pid = new_pid },
					callback = function(c)
						local restoredata = clients_restore_cache[c.pid]["1"]
						local screens = clients_restore_cache[c.pid]["2"]

						c:move_to_screen(screens[restoredata.screen].screen)
						c:tags((function()
							local tags = {}

							for _,t in pairs(restoredata.tags) do
								table.insert(tags, screens[restoredata.screen].tags[t])
							end

							return tags
						end)())

						c.floating = restoredata.floating
						c.fullscreen = restoredata.fullscreen
						c.minimized = restoredata.minimized
						c.maximized = restoredata.maximized
						c.maximized_vertical = restoredata.maximized_vertical
						c.maximized_horizontal = restoredata.maximized_horizontal
						c.hidden = restoredata.hidden
						c.visible = restoredata.visible
						c.opacity = restoredata.opacity
						c.ontop = restoredata.ontop
						c.above = restoredata.above
						c.below = restoredata.below
						c.sticky = restoredata.sticky
						c.geometry = restoredata.geometry
						c.size_hints = size_hints

						table.remove(clients_restore_cache, c.pid)
					end
				})
end

local function restore()
	if helpers.file_exists(session_path) then
		-- Deserialize table
		local json = helpers.first_line(session_path)
		local clients = cjson.decode(json)

		-- Create sorted screen and tags table
		local screens = {}

		for s in screen do
			local tags = {}

			for k,t in pairs(s.tags) do
				tags[t.index] = t
			end

			screens[s.index] = {
				screen = s,
				tags = tags
			}
		end

		-- Iterate client states and call spwan
		for i,c in ipairs(clients) do
			naughty.notify({text = "Restoring \"" .. c.cmd .. " " .. c.cmd_args .. "\""})
			spawn(c, screens)
		end
	end
end

-- Create and return session object
session = {
	save = save,
	restore = restore
}

return session