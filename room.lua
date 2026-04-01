local Util = require "util"
local info = Util.info
local debug = Util.debug
local error = Util.error
local format = string.format

local Room = {}
Room.__index = Room

function Room:__tostring()
    local keys = function(t)
        local keyset={}
        local n=0
        if not t then return keyset end
        for k,_ in pairs(t) do
            n=n+1
            keyset[n]=k
        end
        return keyset
    end
    local name = self.name or ""
    local num = self.num or ""
    local exits = "{" .. table.concat(keys(self.exits), ", ") .. "}"
    local pos = self.pos and ("{" .. table.concat(self.pos, ", ") .. "}") or "{}"
    local moving = self.moving or false
    local label = self.label or ""
    local env = self.environment or ""
    local area = self.area or ""
    local tags = "{" .. table.concat(keys(self.tags), ", ") .. "}"
    local desert = self.desert or false

    local str = "<Room: name=" .. name
    str = str .. " num= " .. num
    str = str .. " exits= " .. exits
    str = str .. " pos= " .. pos
    str = str .. " moving= " .. tostring(moving)
    str = str .. " label= " .. label
    str = str .. " environment= " .. env
    str = str .. " area= " .. area
    str = str .. " tags= " .. tags
    str = str .. " desert= " .. tostring(desert)
    str = str .. ">"
    return str
end

function Room.new()
    return setmetatable({}, Room)
end

function Room.load(obj)
    return setmetatable(obj, Room)
end

function Room:save()
    local ret = {}
    for k, v in pairs(self) do
        if type(v) ~= "function" then
            ret[k] = v
        end
    end
    return ret
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
    self.label = nil
end

function Room:has_tag(val)
    return self.tags and self.tags[val]
end

function Room:add_tag(val)
    if not self.tags then self.tags = {} end
    self.tags[val] = true
end

function Room:add_exit(dir, area, pos)
    local ndir = Util.parse_exit(dir)
    if #ndir == 0 then
        ndir = dir
    end
    if not self.exits then self.exits = {} end
    if not self.exits[ndir] then
        info("ROOM", format("Adding exit '%s'", ndir))
        self.exits[ndir] = {}
    end
    if area then
        self.exits[ndir].area = area
    end
    if pos then
        self.exits[ndir].pos = pos
    end
end

function Room:add_exit_cmd(dir, cmd)
    local ndir = Util.parse_exit(dir)
    info("ROOM", format("Setting command '%s' for '%s'", cmd, ndir))
    if not self.exits then self.exits = {} end
    if not self.exits[ndir] then
        self.exits[ndir] = {}
    end
    self.exits[ndir].cmd = cmd
end

function Room:get_exit_cmd(dir)
    local ndir = Util.parse_exit(dir)
    if self.exits and self.exits[ndir] then
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

    if not self.exits then self.exits = {} end
    if not self.exits[ndir] then
        self.exits[ndir] = {}
    end
    self.exits[ndir].door = door
end

function Room:is_exit_door(dir)
    local ndir = Util.parse_exit(dir)
    if self.exits and self.exits[ndir] then
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
    if not self.exits then self.exits = {} end
    if not self.exits[ndir] then
        self.exits[ndir] = {}
    end
end

function Room:rename_area(old_name, new_name)
    if not self.exits then return end
    for _, exit in pairs(self.exits) do
        if exit.area == old_name then
            exit.area = new_name
        end
    end
end

function Room:parse_json(room_json)
    if self.num ~= room_json.num and self.num ~= nil then
        error("ROOM", format("trying to update room with json, but room nums don't match"))
        return
    end
    for k, v in pairs(room_json) do
        if k == 'exits' then
            self:parse_exits(v)
        else
            if self[k] == nil or self[k] == " " then
                self[k] = v
            else
                error("ROOM", format("Trying to update %s but its already set", k))
            end
        end
    end
end

function Room:parse_exits(exits_json)
    for dir, num in pairs(exits_json) do
        local ndir, vec, rdir = Util.parse_exit(dir)
        local nse = false
        if #ndir == 0 then
            ndir = dir
            -- non standard exit
            nse = true
        end
        if not self.exits then self.exits = {} end
        if not self.exits[ndir] then
            info("ROOM", format("Adding new exit '%s'", ndir))
            self.exits[ndir] = {}
            self.exits[ndir].num = num
            self.exits[ndir].dir = dir
            if nse then
                self:add_tag("nse")
            else
                local x = self.pos[1] + vec[1]
                local y = self.pos[2] + vec[2]
                local z = self.pos[3] + vec[3]
                self.exits[ndir].pos = { x, y, z }
            end
        elseif not self.exits[ndir].num then
            info("ROOM", format("Updating known exit '%s'", ndir))
            self.exits[ndir].num = num
        end
    end
end

function Room:leads_to(num)
    if not self.exits then return nil end
    for ndir, exit in pairs(self.exits) do
        if exit.num == num then
            return ndir
        end
    end
end

return Room
