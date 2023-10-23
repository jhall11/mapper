local Util = require "util"
local info = Util.info
local debug = Util.debug
local format = string.format

local Room = {}
Room.__index = Room

function Room.new()
	local ret = setmetatable({}, Room)
	ret.name = nil
	ret.num = nil
	ret.exits = {}
	ret.pos = {}
	ret.moving = false
	ret.label = " "
	ret.environment = " "
	ret.area = " "
	return ret
end

function Room.load(obj)
	local ret = setmetatable({}, Room)
	ret.name = obj.name
	ret.num = obj.num
	ret.exits = obj.exits
	ret.pos = obj.pos
	ret.moving = obj.moving or false
	ret.label = obj.label or " "
	ret.environment = obj.environment or " "
	ret.area = obj.area or " "
	return ret
end

function Room:save()
	return {
		name=self.name,
		num=self.num,
		exits=self.exits,
		moving=self.moving,
		pos=self.pos,
		label=self.label,
		environment=self.environment,
		area=self.area,
	}
end

function Room:set_name(name)
	info("ROOM", format("Setting name to '%s'", name))
	self.name = name
end

function Room:get_name()
	return self.name
end

function Room:set_num(num)
	info("ROOM", format("Setting num to '%s'", num))
	self.num = num
end

function Room:get_num()
	return self.num
end

function Room:set_label(label)
	info("ROOM", format("Setting label to '%s'", label))
	self.label = label
end

function Room:remove_label()
	self.label = " "
end

function Room:add_exit(dir, area, pos)
	local ndir = Util.parse_exit(dir)
	if not self.exits[ndir] then
		info("ROOM", format("Adding exit '%s'", ndir))
		self.exits[ndir] = {}
	end
	self.exits[ndir].area=area
	self.exits[ndir].pos=pos
end

function Room:add_exit_cmd(dir, cmd)
	local ndir = Util.parse_exit(dir)
	info("ROOM", format("Setting command '%s' for '%s'", cmd, ndir))
	if not self.exits[ndir] then
		self.exits[ndir] = {}
	end
	self.exits[ndir].cmd=cmd
end

function Room:get_exit_cmd(dir)
	local ndir = Util.parse_exit(dir)
	if self.exits[ndir] then
		if self.exits[ndir].cmd then
			return self.exits[ndir].cmd, true
		else
			return ndir, false
		end
	end
	return dir, false
end

function Room:set_exit_door(dir, door)
	local ndir = Util.parse_exit(dir)
	info("ROOM", format("Marking '%s' as door", ndir))

	if not self.exits[ndir] then
		self.exits[ndir] = {}
	end
	self.exits[ndir].door = door
end

function Room:is_exit_door(dir)
	local ndir = Util.parse_exit(dir)
	if self.exits[ndir] then
		return self.exits[ndir].door
	end
	return false
end


function Room:set_moving(moving)
	info("ROOM", "Marking room as 'moving'")
	self.moving = moving
end

function Room:is_moving()
	return self.moving or false
end

function Room:add_undiscovered_exit(dir)
	local ndir = Util.parse_exit(dir)
	if not self.exits[ndir] then
		self.exits[ndir] = {}
	end
end

function Room:rename_area(old_name, new_name)
	for _,exit in pairs(self.exits) do
		if exit.area == old_name then
			exit.area = new_name
		end
	end
end


function Room:parse_json(room_json)
	if self.num ~= room_json.num then
		debug("ROOM", format("trying to update room with json, but room nums don't match"))
		return
	end
	for k,v in pairs(room_json) do
		if k == 'exits' then
			self:parse_exits(v)
		else
			if self[k] == nil or self[k] == " " then
				self[k] = v
			else
				debug("ROOM", format("Trying to update %s but its already set", k))
			end
		end
	end
end

function Room:parse_exits(exits_json)
	for dir, num in pairs(exits_json) do
		local ndir, vec, rdir = Util.parse_exit(dir)
		if ndir == "" then
			ndir = dir
		end
		if not self.exits[ndir] then
			info("ROOM", format("Adding exit '%s'", ndir))
			self.exits[ndir] = {}
			self.exits[ndir].num = num
			self.exits[ndir].dir = dir
			self.exits[ndir].pos = vec
		end
	end
end

function Room:leads_to(num)
	for ndir ,exit in pairs(self.exits) do
		if exit.num == num then
			return ndir
		end
	end
end


return Room
