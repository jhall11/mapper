local Room = require "room"
local Util = require "util"

-- Default list
local DefaultList = {}
DefaultList.__index = DefaultList

local info = Util.info
local debug = Util.debug
local error = Util.error
local format = string.format

function DefaultList.new()
    local mt = {
        __index = function(t, k)
            t[k] = {}
            return t[k]
        end
    }
    return setmetatable({}, mt)
end

local function create_matrix()
    local mt = {
        __index = function(t, k)
            t[k] = DefaultList.new()
            return t[k]
        end
    }
    return setmetatable({}, mt)
end

Area = {}
Area.__index = Area

function Area.new(name)
    local ret = setmetatable({}, Area)

    ret.name = name
    ret.pos = { 0, 0, 0 }
    ret.last_pos = {}
    ret.last_dir = ""
    ret.rooms = create_matrix()
    ret.rooms[0][0][0] = Room.new()
    local room = ret.rooms[0][0][0]
    room.pos = { 0, 0, 0 }

    return ret
end

function Area.load(obj)
    local ret = setmetatable({}, Area)
    local loadRoom = Room.load -- lua performance optimization

    ret.name = obj.name
    ret.pos = { 0, 0, 0 }
    ret.last_pos = {}
    ret.last_dir = ""
    ret.rooms = create_matrix()

    for _, room in ipairs(obj.rooms) do
        local x, y, z = table.unpack(room.pos)
        ret.rooms[x][y][z] = loadRoom(room)
    end

    return ret
end

function Area:save()
    local rooms = {}
    for _, row in pairs(self.rooms) do
        for _, col in pairs(row) do
            for _, room in pairs(col) do
                table.insert(rooms, room:save())
            end
        end
    end

    return {
        rooms = rooms,
        name = self.name
    }
end

function Area:set_pos(x, y, z)
    self.last_pos = { table.unpack(self.pos) }
    self.pos = { x, y, z }
end

function Area:move(dir)
    local ndir, vec, rdir = Util.parse_exit(dir)
    self.last_dir = ndir

    local x = self.pos[1] + vec[1]
    local y = self.pos[2] + vec[2]
    local z = self.pos[3] + vec[3]
    return self:innerMove(ndir, x, y, z, rdir)
end

function Area:moveLength(dir, length)
    local ndir, vec, rdir = Util.parse_exit(dir)
    self.last_dir = ndir

    local x = self.pos[1] + (vec[1] * length)
    local y = self.pos[2] + (vec[2] * length)
    local z = self.pos[3] + (vec[3] * length)
    return self:innerMove(ndir, x, y, z, rdir)
end

function Area:innerMove(ndir, x, y, z, rdir)
    local oldRoom = self:get_room()
    if not oldRoom then
        error("Unknown location")
        return
    end
    -- TODO CHECK IF EXIT EXISTS?
    oldRoom:add_exit(ndir, self.name, { x, y, z })

    local newRoom = self.rooms[x][y][z]
    if not newRoom then
        info("AREA", "Creating room")
        self.rooms[x][y][z] = Room.new()
        newRoom = self.rooms[x][y][z]
        newRoom.pos = { x, y, z }
    else
        info("AREA", "Updating room")
    end

    if rdir ~= nil then
        newRoom:add_exit(rdir, self.name, { table.unpack(self.pos) })
        -- TODO add mechanism for detecting unset exit pos and trying to update them
    end
    self:set_pos(table.unpack(newRoom.pos))
    return newRoom
end

function Area:delete_current_room()
    local x, y, z = table.unpack(self.pos)
    info("AREA", "Removing room")
    self.rooms[x][y][z] = nil
end

function Area:go_back()
    info("area", "Moving to previous room")
    self.pos = { table.unpack(self.last_pos) }
    self.last_pos = {}
    return self:get_room()
end

function Area:unmove()
    self:delete_current_room()
    return self:go_back()
end

function Area:track(dir)
    local room = self:get_room()
    local ndir = Util.parse_exit(dir)
    if room ~= nil and room.exits[ndir] ~= nil and room.exits[ndir].pos ~= nil then
        local exit = room.exits[ndir]
        debug("AREA", format("Tracking known exit %s", json.encode(exit)))
        if self:find_room(exit.num) then
            debug("AREA", "Setting position")
            self:set_pos(table.unpack(exit.pos))
        end
        return exit
    else
        return nil
    end
end

function Area:drop_last_exit()
    local room = self:get_room()
    if room then
        info("area", format("Dropping exit '%s'", self.last_dir))
        room.exits[self.last_dir] = nil
    end
end

function Area:rename_area(old_name, new_name)
    if self.name == old_name then
        self.name = new_name
    end
    for _, row in pairs(self.rooms) do
        for _, col in pairs(self.rooms[row]) do
            for _, room in pairs(self.rooms[row][col]) do
                room:rename_area(old_name, new_name)
            end
        end
    end
end

function Area:delete_room(dir)
    local room = self:get_room()
    if room then
        local ndir, vec = Util.parse_exit(dir)
        info("area", format("Deleting room '%s'", ndir))
        room.exits[ndir] = {}
        local rpos = {
            self.pos[1] + vec[1],
            self.pos[2] + vec[2],
            self.pos[3] + vec[3],
        }
        self.rooms[rpos[1]][rpos[2]][rpos[3]] = nil
        return true
    end
    return false
end

function Area:get_room()
    return self.rooms[self.pos[1]][self.pos[2]][self.pos[3]]
end

function Area:find_room(num)
    for _, row in pairs(self.rooms) do
        for _, col in pairs(row) do
            for _, room in pairs(col) do
                if room.num == num then
                    return room
                end
            end
        end
    end
    return nil
end

local function _print_exit_symbol(self, symbol, exit)
    -- todo we  aren't saving an exit's area always
    if not exit.area then
        return cformat("<red>%s<reset>", symbol)
    elseif exit.cmd then
        return cformat("<byellow>%s<reset>", symbol)
    elseif self.name ~= exit.area then
        return cformat("<magenta>%s<reset>", symbol)
    else
        return symbol
    end
end

local function _print_exits(self, exits, matrix, px, py)
    if exits["n"] then
        matrix[py - 1][px] = _print_exit_symbol(self, "|", exits["n"])
    end
    if exits["s"] then
        matrix[py + 1][px] = _print_exit_symbol(self, "|", exits["s"])
    end
    if exits["e"] then
        matrix[py][px + 2] = _print_exit_symbol(self, "-", exits["e"])
    end
    if exits["w"] then
        matrix[py][px - 2] = _print_exit_symbol(self, "-", exits["w"])
    end
    if exits["ne"] then
        if matrix[py - 1][px + 2] == "\\" then
            matrix[py - 1][px + 2] = _print_exit_symbol(self, "X", exits["ne"])
        else
            matrix[py - 1][px + 2] = _print_exit_symbol(self, "/", exits["ne"])
        end
    end
    if exits["nw"] then
        if matrix[py - 1][px - 2] == "/" then
            matrix[py - 1][px - 2] = _print_exit_symbol(self, "X", exits["nw"])
        else
            matrix[py - 1][px - 2] = _print_exit_symbol(self, "\\", exits["nw"])
        end
    end
    if exits["se"] then
        if matrix[py + 1][px + 2] == "/" then
            matrix[py + 1][px + 2] = _print_exit_symbol(self, "X", exits["se"])
        else
            matrix[py + 1][px + 2] = _print_exit_symbol(self, "\\", exits["se"])
        end
    end
    if exits["sw"] then
        if matrix[py + 1][px - 2] == "\\" then
            matrix[py + 1][px - 2] = _print_exit_symbol(self, "X", exits["sw"])
        else
            matrix[py + 1][px - 2] = _print_exit_symbol(self, "/", exits["sw"])
        end
    end
end

function Area:print()
    local yoffset = 3
    local xoffset = 4
    local xmin = self.pos[1] - xoffset
    local xmax = self.pos[1] + xoffset
    local ymin = self.pos[2] - yoffset
    local ymax = self.pos[2] + yoffset
    local z = self.pos[3]
    local linkSize = 1
    local labelSize = 1
    local roomSize = 2 + labelSize

    local width = (xoffset * 2 + 1) * roomSize + linkSize
    local height = (yoffset * 2 + 1) * 2 + linkSize
    local matrix = {}
    local _print_exits = _print_exits -- lua performance optimization
    ---
    --local row = {}
    --for _ = 1, width do
    --    table.insert(row, "-")
    --end
    --matrix[-1]=row
    ---
    for _ = 1, height do
        local row = {}
        for _ = 1, width do
            table.insert(row, " ")
        end
        table.insert(matrix, row)
    end

    ---
    --local row = {}
    --for _ = 1, width do
    --    table.insert(row, "-")
    --end
    --matrix[height+1]=row
    ---

    local py = 2
    for y = ymin, ymax do
        local px = 3
        for x = xmin, xmax do
            local room = self.rooms[x][y][z]
            if room then
                if room.num and room:is_moving() then -- TODO: choose unique colors
                    matrix[py][px - 1] = cformat("<cyan>[<reset>")
                    matrix[py][px + 1] = cformat("<cyan>]<reset>")
                elseif room.num and room:has_tag("nse") then
                    matrix[py][px - 1] = cformat("<cyan>{<reset>")
                    matrix[py][px + 1] = cformat("<cyan>}<reset>")
                elseif room.num and (room:has_tag("desert") or room.desert) then
                    matrix[py][px - 1] = cformat("<yellow>[<reset>")
                    matrix[py][px + 1] = cformat("<yellow>]<reset>")
                elseif room.num then
                    matrix[py][px - 1] = cformat("<white>[<reset>")
                    matrix[py][px + 1] = cformat("<white>]<reset>")
                else
                    matrix[py][px - 1] = cformat("<red>[<reset>")
                    matrix[py][px + 1] = cformat("<red>]<reset>")
                end
                if self.pos[1] == x and self.pos[2] == y then
                    matrix[py][px] = cformat("<bcyan>+<reset>")
                elseif room.exits["u"] and room.exits["d"] then
                    matrix[py][px] = cformat("=")
                elseif room.exits["u"] then
                    matrix[py][px] = cformat("^")
                elseif room.exits["d"] then
                    matrix[py][px] = cformat("_")
                else
                    matrix[py][px] = room.label
                end
                _print_exits(self, room.exits, matrix, px, py)
            end
            px = px + 4
        end
        py = py + 2
    end

    local room_num = "n/a"
    if self:get_room() then
        room_num = self:get_room().num or "n/a"
    end
    local lines = {
        cformat("<green>%s<reset> <cyan>[%s]<reset> <yellow>[%d,%d,%d]<reset>", self.name, room_num, table.unpack(self.pos))
    }
    table.insert(lines, self:get_room().name or "n/a")
    for _, row in ipairs(matrix) do
        local line = ""
        for _, str in ipairs(row) do
            if str then
                line = line .. str
            end
        end
        table.insert(lines, line)
    end
    return lines
end

return Area
