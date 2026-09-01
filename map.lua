local Area = require("area")
local Util = require "util"
local serpent = require("serpent")

local format = string.format
local info = Util.info
local debug = Util.debug
local error = Util.error

local Map = {}
Map.__index = Map
Map.saveOpts = { comment=false, sortKeys=true }

local function expand_tilde(path)
    if path:find("^~") ~= nil then
        return format("%s%s", os.getenv("HOME"), path:sub(2))
    else
        return path
    end
end

function Map.new(name)
    local ret = setmetatable({}, Map)

    ret.name = name
    ret.currentArea = nil
    ret.currentRoom = nil
    ret.areas = {}
    ret.save_location = nil
    ret._room_cache = setmetatable({}, {__mode = "v"}) -- Weak values table for cache

    return ret
end

function Map:add_area(name)
    if not self.areas[name] then
        self.areas[name] = Area.new(name)
        self.currentArea = self.areas[name]
        self.currentRoom = self.currentArea:get_room()
        return self.areas[name]
    end
    return self.areas[name]
end

function Map:replace_area(name)
    if self.areas[name] then
        self.areas[name] = Area.new(name)
        self.currentArea = self.areas[name]
        self.currentRoom = self.currentArea:get_room()
        return self.areas[name]
    end
    return nil
end

function Map:rename_area(old_name, new_name)
    self.areas[new_name] = self.areas[old_name]
    self.areas[old_name] = nil
    for _, area in pairs(self.areas) do
        area:rename_area(old_name, new_name)
    end
    -- Clear cache on rename as room references might be invalid
    self._room_cache = setmetatable({}, {__mode = "v"})
end

function Map:track(dir)
    if self.currentArea == nil then
        return false
    end
    local exit = self.currentArea:track(dir)
    if exit and exit.num and self:find_room(exit.num) then
        local oldRoom = self.currentRoom
        self:set_position(exit.num)
        if oldRoom and oldRoom.area and self.currentRoom.area and not exit.area then
            exit.area = self.currentRoom.area
        end
        return exit
    else
        self.currentRoom = nil
        return nil
    end
end

function Map:set_position(num)
    self.currentArea = nil
    self.currentRoom = nil
    if self._room_cache[num] then
        local cachedRoom = self._room_cache[num]
        self.currentArea = self.areas[cachedRoom.area]
        self.currentRoom = cachedRoom
        if self.currentArea then
            self.currentArea:set_pos(table.unpack(self.currentRoom.pos))
            self:check_room_migration(self.currentRoom)
            return true
        end
    end

    for _, area in pairs(self.areas) do
        local room = area:find_room(num)
        if room then
            self.currentArea = area
            self.currentRoom = room
            self.currentArea:set_pos(table.unpack(room.pos))
            -- populate cache
            self._room_cache[num] = room
            self:check_room_migration(room)
            return true
        end
    end
    return false
end

-- Checks if a room should be moved to a different area based on its exits
function Map:check_room_migration(room)
    if not room or not room.exits then return end

    local exit_areas = {}
    local total_exits = 0

    for _, exit in pairs(room.exits) do
        if exit.area then
            total_exits = total_exits + 1
            exit_areas[exit.area] = (exit_areas[exit.area] or 0) + 1
        end
    end

    if total_exits > 0 then
        for area_name, count in pairs(exit_areas) do
            -- If all exits point to a different area, relocate the room
            if count == total_exits and area_name ~= room.area then
                info("MAP", string.format("Relocating room %s from %s to %s based on exit consistency", room.num or "unknown", room.area, area_name))
                self:relocate_room(room, area_name)
                break
            end
        end
    end
end

function Map:relocate_room(room, new_area_name)
    local old_area_name = room.area
    local old_area = self.areas[old_area_name]
    local new_area = self:add_area(new_area_name)

    if old_area then
        local key = format("%d,%d,%d", table.unpack(room.pos))
        old_area.rooms[key] = nil
    end

    room.area = new_area_name
    local new_key = format("%d,%d,%d", table.unpack(room.pos))
    new_area.rooms[new_key] = room

    -- Update current pointers if needed
    if self.currentRoom == room then
        self.currentArea = new_area
    end
end

function Map:find_room(num)
    -- create a cache to speed up retrieval
    if not self._room_cache then
        self._room_cache = setmetatable({}, {__mode = "v"})
    end

    if self._room_cache[num] then
        return self._room_cache[num], self._room_cache[num].area
    end

    for name, area in pairs(self.areas) do
        local room = area:find_room(num)
        if room then
            -- populate cache for future calls
            self._room_cache[num] = room
            return room, name
        end
    end

    return nil
end

function Map:get_area()
    return self.currentArea
end

function Map:get_room()
    return self.currentRoom
end

function Map:move(dir)
    if self.currentArea ~= nil then
        self.currentRoom = self.currentArea:move(dir)
    end
    return self.currentRoom
end

function Map:moveLength(dir, length)
    if self.currentArea ~= nil then
        self.currentRoom = self.currentArea:moveLength(dir, length)
    end
    return self.currentRoom
end

function Map:unmove()
    if self.currentArea ~= nil then
        self.currentRoom = self.currentArea:unmove()
    end
    return self.currentRoom
end

function Map:go_back()
    if self.currentArea ~= nil then
        self.currentRoom = self.currentArea:go_back()
    end
    return self.currentRoom
end

function Map:drop_last_exit()
    if self.currentArea ~= nil then
        self.currentArea:drop_last_exit()
    end
end

local function table_len(obj)
    local count = 0
    for _, _ in pairs(obj) do
        count = count + 1
    end
    return count
end

function Map:save(path, suffix)
    debug("MAP", "Starting Save Process")

    Map.saveTask = tasks.spawn(Map.saveTaskFn, self, path, suffix)
    tasks.spawn(Map.reportTaskFn, Map.saveTask)
end

Map.saveTaskFn = function(self, path, suffix)
    local timestamp = core.time() / 1000
    local t1 = timestamp
    suffix = suffix or ""
    path = expand_tilde(path)
    local base_fname = format("%s.map_%s%s", path, self.name, suffix)
    local area_files = {}

    -- Save each area to its own file using compact dump
    for name, area in pairs(self.areas) do
        local area_fname = format("%s.area_%s.lua", base_fname, name)
        local file = io.open(area_fname, "w")
        if file then
            file:write(serpent.dump(area:save(), self.saveOpts))
            file:close()
            table.insert(area_files, name)
        end

        if (core.time() / 1000) > timestamp + 0.5 then -- FIXME still issue if individual file is more that 1.1 seconds, but this is like 3 seconds vs 19 for 19 files
            debug("SAVE TASK", "Its been at least a 0.5 seconds since we yielded back to main task; sleep after area: " .. name)
            tasks.sleep(0)
            timestamp = core.time() / 1000
        end
    end

    -- Save a master index file that lists all areas
    local index_fname = format("%s.index.lua", base_fname)
    local index_file = io.open(index_fname, "w")
    if index_file then
        index_file:write(serpent.dump(area_files, self.saveOpts))
        index_file:close()
    end
    info("MAP", format("Saved %d areas to individual files", #area_files))
    debug("MAP", format("total time spent = %s seconds", (core.time() / 1000) - t1))
end

function Map.reportTaskFn(saveTask)
    while not saveTask.dead do
        tasks.sleep(0)
    end
    if saveTask.error then
        error("MAP", format("Failed to save map:"))
        for i, err in ipairs(saveTask.error) do
            error("MAP", format(i .. ") " .. err))
        end
    else
        debug("MAP", format("Map Saved"))
    end
end


function Map:load(path, suffix)
    info("MAP", "Starting Load Process")
    --Map.loadTask = tasks.spawn(Map.loadTaskFn, path, suffix)
    -- FIXME we need to wait for task to finish before returning from this fn or we don't have map loaded before we get gmcp info
    Map.loadTaskFn(self, path, suffix)
end

function Map.loadTaskFn(self, path, suffix)
    suffix = suffix or ""
    path = expand_tilde(path)
    local base_fname = format("%s.map_%s%s", path, self.name, suffix)

    local index_fname = format("%s.index.lua", base_fname)
    local index_file = io.open(index_fname, "r")

    if not index_file then
        -- Fallback to old single-file load if index doesn't exist
        local old_fname = format("%s.map_%s%s.lua", path, self.name, suffix)
        info("MAP", "Index not found, attempting legacy load from " .. old_fname)
        --tasks.sleep(0)
        local file = io.open(old_fname, "r")
        if file then
            local ok, obj = serpent.load(file:read("*a"))
            file:close()
            if ok then
                self.areas = {}
                for name, area_data in pairs(obj) do
                    self.areas[name] = Area.load(area_data)
                end
                info("MAP", "Legacy map loaded successfully")
                return true
            end
        end
        return false
    end

    -- Load from index and individual area files
    local ok, area_list = serpent.load(index_file:read("*a"))
    index_file:close()

    if ok then
        self.areas = {}
        for _, name in ipairs(area_list) do
            --tasks.sleep(0)
            local area_fname = format("%s.area_%s.lua", base_fname, name)
            local a_file = io.open(area_fname, "r")
            if a_file then
                local a_ok, a_data = serpent.load(a_file:read("*a"))
                a_file:close()
                if a_ok then
                    self.areas[name] = Area.load(a_data)
                end
            end
        end
        info("MAP", format("Loaded %d areas from individual files", table_len(self.areas)))
    end
    return ok
end

function Map:print(x,y)
    if self.currentArea ~= nil and self.currentRoom ~= nil then
        return self.currentArea:print(x,y)
    end
    return { "", cformat("<red>-- No map available<reset>") }
end

return Map
