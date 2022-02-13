---@type GL
local _, GL = ...;

---@class StackedRoll
GL.StackedRoll = {
    _initialized = false,
    MaterializedData = {
        DetailsByPlayerName = {},
    },
};

local DB = GL.DB; ---@type DB
local StackedRoll = GL.StackedRoll; ---@type StackedRoll

---@return boolean
function StackedRoll:_init()
    GL:debug("StackedRoll:_init");

    if (self._initialized) then
        return false;
    end

    self:materializeData();

    self._initialized = true;
    return true;
end

--- Check whether stacked rolls are enabled
---
---@return boolean
function StackedRoll:enabled()
    GL:debug("StackedRoll:enabled");

    return GL.Settings:get("StackedRoll.enabled");
end

--- Check whether there are stacked rolls available
---
---@return boolean
function StackedRoll:available()
    GL:debug("StackedRoll:available");

    return GL:higherThanZero(DB:get("StackedRoll.MetaData.importedAt", 0));
end

--- Draw either the importer or overview
--- based on the current stacked roll data
---
---@return void
function StackedRoll:draw()
    GL:debug("StackedRoll:draw");

    -- No data available, show importer
    if (not self:available()) then
        GL.Interface.StackedRoll.Importer:draw();
        return;
    end

    -- Show the stacked roll overview instead
    GL.Interface.StackedRoll.Overview:draw();
end

--- Materialize the stacked roll data to make it more accessible during runtime
---
---@return void
function StackedRoll:materializeData()
    GL:debug("StackedRoll:materializeData");

    local DetailsByPlayerName = {}; -- Details including aliases by player name
    local Aliases = {}; -- Direct access to aliases

    --- Create entries from points data
    for name, points in pairs(DB:get("StackedRoll.Points", {})) do
        local name = string.lower(name or "");
        local points = self:toPoints(points or 0);

        if (type(name) == "string"
            and not GL:empty(name)
        ) then
            if (not DetailsByPlayerName[name]) then
                GL:tableSet(DetailsByPlayerName, name .. ".Aliases", {});
                DetailsByPlayerName[name].points = points;
                DetailsByPlayerName[name].class = "";
            end
        end
    end

    --- Add aliases
    for alias, main in pairs(DB:get("StackedRoll.Aliases", {})) do
        local alias = string.lower(alias or "");
        local main = string.lower(main or "");

        if (type(alias) == "string" and type(main) == "string"
            and not GL:empty(alias) and not GL:empty(main)
        ) then
            if (DetailsByPlayerName[main] and not DetailsByPlayerName[alias]) then
                tinsert(DetailsByPlayerName[main].Aliases, alias);
            end
        end
    end

    self.MaterializedData.DetailsByPlayerName = DetailsByPlayerName;
end

--- Format a stacked roll.
---
---@param points any
---@return number
function StackedRoll:toPoints(points)
    points = tonumber(points);

    if not points then
        return nil;
    end

    points = math.max(0, math.floor(points));
    return points;
end;

--- Calculate roll points from points.
---
---@param points number
---@return number
function StackedRoll:rollPoints(points)
    return math.min(GL.Settings:get("StackedRoll.reserveThreshold"), points);
end;

--- Calculate reserve from points.
---
---@param points number
---@return number
function StackedRoll:reserve(points)
    return math.max(0, points - GL.Settings:get("StackedRoll.reserveThreshold"));
end;

--- Calculate max roll from points.
---
---@param points number
---@return number
function StackedRoll:maxStackedRoll(points)
    return math.max(1, math.min(GL.Settings:get("StackedRoll.reserveThreshold"), points));
end;

--- Calculate min roll from points.
---
---@param points number
---@return number
function StackedRoll:minStackedRoll(points)
    return math.max(1, self:maxStackedRoll(points) - 100);
end;

--- Detect stacked rolls.
---
---@param min number
---@param max number
---@return boolean
function StackedRoll:isStackedRoll(low, high)
    local threshold = GL.Settings:get("StackedRoll.reserveThreshold");
    --- Check maximum.
    if (self:maxStackedRoll(high) ~= high or high > threshold) then
        return false;
    end

    --- Check minimum.
    if (self:minStackedRoll(high) ~= low) then
        return false;
    end
    return true;
end;

--- Clear all stacked roll data
---
---@return void
function StackedRoll:clear()
    DB.StackedRoll = {};
    self.MaterializedData = {
        DetailsByPlayerName = {},
    };

    GL.Interface.StackedRoll.Overview:close();
end

--- Get a player's points
---
---@param name string
---@param points number
---@return void
function StackedRoll:getPoints(name, default)
    GL:debug("StackedRoll:getPoints");
    local normalizedName = string.lower(name);
    --- Follow alias table if present
    if (DB.StackedRoll.Aliases[normalizedName]) then
        normalizedName = DB.StackedRoll.Aliases[normalizedName];
    end
    if (self.MaterializedData.DetailsByPlayerName[normalizedName]) then
        return self.MaterializedData.DetailsByPlayerName[normalizedName].points;
    end

    return default;
end

--- Set a player's points
---
---@param name string
---@param points number
---@return void
function StackedRoll:setPoints(name, points)
    GL:debug("StackedRoll:setPoints");
    local normalizedName = string.lower(name);
    --- Follow alias table if present
    if (DB.StackedRoll.Aliases[normalizedName]) then
        normalizedName = DB.StackedRoll.Aliases[normalizedName];
    end
    if (self.MaterializedData.DetailsByPlayerName[normalizedName]) then
        self.MaterializedData.DetailsByPlayerName[normalizedName].points = points;
        DB:set("StackedRoll.Points."..normalizedName, points);
    end
end

--- Modify a player's points
---
---@param name string
---@param points number
---@return void
function StackedRoll:modifyPoints(name, change)
    GL:debug("StackedRoll:modifyPoints");
    local normalizedName = string.lower(name);
    --- Follow alias table if present
    if (DB.StackedRoll.Aliases[normalizedName]) then
        normalizedName = DB.StackedRoll.Aliases[normalizedName];
    end
    if (self.MaterializedData.DetailsByPlayerName[normalizedName]) then
        local points = self.MaterializedData.DetailsByPlayerName[normalizedName].points;
        points = self:toPoints(points + change);
        self:setPoints(normalizedName, points);
    end
end

--- Import a CSV or TSV data string
---
---@param data string
---@return boolean
function StackedRoll:import(data, openOverview)
    GL:debug("StackedRoll:import");

    -- Make sure all the required properties are available and of the correct type
    if (GL:empty(data)) then
        GL.Interface:getItem("StackedRoll.Importer", "Label.StatusMessage"):SetText("Invalid stacked roll data provided");
        return false;
    end

    local Points = {};
    local Aliases = {};
    
    for line in data:gmatch("[^\n]+") do
        --- We expect lines to be in the form,
        --- where the individual variables are comma, tab, or spaces separated:
        --- PlayerName,Points,Alias1,Alias2...
        --- e.g., "Foobar,240,Barfoo"
        --- This facilitates imports from CSV, TSV files or pasting from Google Docs
        local Segments = GL:separateValues(line);
        
        local playerName = tostring(Segments[1]);
        playerName = string.lower(playerName);
        local points = self:toPoints(Segments[2]);

        if (not GL:empty(playerName) and not Points[playerName] and points) then
            Points[playerName] = points;

            --- Import further segments as aliases (twink names)
            for i = 3, #Segments do
                local alias = tostring(Segments[i]);
                alias = string.lower(alias);
                if (not GL:empty(alias) and not Points[alias] and not Aliases[alias]) then
                    Aliases[alias] = playerName;
                end
            end
        end
    end

    if (GL:empty(Points)) then
        local errorMessage = "Invalid data provided. Make sure that the contents follows the required format and no header row is included.";
        GL.Interface:getItem("StackedRoll.Importer", "Label.StatusMessage"):SetText(errorMessage);

        return false;
    end

    DB.StackedRoll = {
        Points = Points,
        Aliases = Aliases,
        MetaData = {
            importedAt = GetServerTime(),
            importString = data,
        },
    };

    GL:success("Import of stacked roll data successful");
    GL.Events:fire("GL.STACKEDROLL_IMPORTED");

    self:materializeData();
    GL.Interface.StackedRoll.Importer:close();

    if (openOverview) then
        self:draw();
    end

    return true;
end


GL:debug("StackedRoll.lua");