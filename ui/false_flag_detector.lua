local ffi = require("ffi")
local C = ffi.C

local falseFlagDetector = {
  configBlackboard = "$FalseFlagDetectorConfig",
  colorsBlackboard = "$FalseFlagDetectorColors",
  shadowTrackerBlackboard = "$shadowTracker",
  textPage = 1972092446,
  mapLinkLifetime = 600,
  debugLevel = "none",
}

local function write(message, ...)
  if select("#", ...) > 0 then
    message = string.format(message, ...)
  end
  DebugError("FalseFlagDetector: " .. message)
end

function falseFlagDetector.Error(message, ...) write(message, ...) end
function falseFlagDetector.Debug(message, ...) if falseFlagDetector.debugLevel ~= "none" then write(message, ...) end end
function falseFlagDetector.Trace(message, ...) if falseFlagDetector.debugLevel == "trace" then write(message, ...) end end

local function playerId() return ConvertStringTo64Bit(tostring(C.GetPlayerID())) end

function falseFlagDetector.ReadConfig()
  local config = GetNPCBlackboard(playerId(), falseFlagDetector.configBlackboard)
  if type(config) == "table" and config.debugLevel then
    falseFlagDetector.debugLevel = tostring(config.debugLevel)
  end
end

-- MD has no access to faction colours: publish them as AARRGGBB per faction id
function falseFlagDetector.PublishColors()
  falseFlagDetector.ReadConfig()
  local colors, count = {}, 0
  for _, faction in ipairs(GetLibrary("factions") or {}) do
    local color = GetFactionData(faction.id, "color")
    if type(color) == "table" and color.r then
      colors[faction.id] = string.format("%02x%02x%02x%02x", math.floor(color.a * 255 / 100 + 0.5), color.r, color.g, color.b)
      count = count + 1
      falseFlagDetector.Trace("colour %s = %s", faction.id, colors[faction.id])
    end
  end
  SetNPCBlackboard(playerId(), falseFlagDetector.colorsBlackboard, colors)
  falseFlagDetector.Debug("published %d faction colours", count)
end

local function trackedShips()
  local tracked = {}
  local shadowTracker = GetNPCBlackboard(playerId(), falseFlagDetector.shadowTrackerBlackboard)
  if type(shadowTracker) == "table" and type(shadowTracker.installed) == "table" then
    for _, ship in ipairs(shadowTracker.installed) do
      tracked[tostring(ConvertIDTo64Bit(ship))] = true
    end
  end
  return tracked
end

-- A logbook entry cannot expire: drop the "show on map" link of older reports whenever a logbook list is read
local vanillaGetLogbook = GetLogbook
function GetLogbook(...)
  local entries = vanillaGetLogbook(...)
  if type(entries) ~= "table" then
    return entries
  end
  local title = ReadText(falseFlagDetector.textPage, 1021)
  local cutoff = GetCurTime() - falseFlagDetector.mapLinkLifetime
  local tracked, hidden = nil, 0
  for _, entry in ipairs(entries) do
    if entry.interaction == "showonmap" and entry.title == title and entry.time < cutoff then
      tracked = tracked or trackedShips()
      if not tracked[tostring(ConvertIDTo64Bit(entry.interactioncomponent))] then
        entry.interaction = nil
        hidden = hidden + 1
      end
    end
  end
  if hidden > 0 then
    falseFlagDetector.Trace("map link hidden on %d of %d logbook entries", hidden, #entries)
  end
  return entries
end

local function init()
  RegisterEvent("FalseFlagDetector.PublishColors", falseFlagDetector.PublishColors)
  RegisterEvent("FalseFlagDetector.ConfigChanged", falseFlagDetector.ReadConfig)
  -- A UI reload in game gets no MD request; there is no player in the main menu
  if playerId() ~= 0 then
    falseFlagDetector.PublishColors()
  end
end

init()
