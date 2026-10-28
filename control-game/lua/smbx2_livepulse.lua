-- LivePulse para SMBX2 (LunaLua).
-- Lo carga data\scripts\base\game\lunabase.lua al abrir un nivel o el mapa.
-- SMBX2 solo deja leer y escribir dentro de su carpeta, así que las órdenes
-- viven en data\logs\, no en C:\LivePulse.

local SPAWN = {
  SPAWN_HONGO = 9,
  SPAWN_FLOR = 14,
  SPAWN_HOJA = 34,
  SPAWN_TANOOKI = 169,
  SPAWN_ESTRELLA = 293,
  SPAWN_1UP = 90,
  SPAWN_GOOMBA = 1,
  SPAWN_KOOPA_VERDE = 4
}

local tick = 0
local heroName = ""
local heroPlatePath = ""
local giftPlatePath = ""
local labels = {}
local images = {}
local general = { phase = "", action = "", user = "", untilAt = 0, plate = "" }
local resetSent = false
local textplusApi = nil
local savestateApi = nil
local history = {}
local rewindOn = false
local rewindFrom = 0
local rewindSpan = 0
local rewindIndex = -1
local rewindUntil = 0
local engineSpeed = -1
local MASK_PLAY = 0x6
local PHRASE = {
  acelerar = "aceleró el emulador",
  reiniciar = "hizo soft reset",
  cerrar = "cerró el emulador",
  terremoto = "hizo un terremoto",
  rewinder = "hizo rewinder"
}

pcall(function() textplusApi = require("textplus") end)
pcall(function() savestateApi = require("savestate") end)

pcall(function()
  if Misc ~= nil and Misc.runWhenUnfocused ~= nil then
    Misc.runWhenUnfocused(true)
  end
end)

local function logsDir()
  local list = { "C:\\Games\\SMBX2\\data\\logs\\" }
  if type(getSMBXPath) == "function" then
    local ok, value = pcall(getSMBXPath)
    if ok and value ~= nil then
      local root = tostring(value):gsub("[\\/]+$", "")
      table.insert(list, 1, root .. "\\data\\logs\\")
      table.insert(list, 1, root .. "\\logs\\")
    end
  end
  for i = 1, #list do
    local probe = io.open(list[i] .. "livepulse_hero.txt", "r")
    if probe ~= nil then
      probe:close()
      return list[i]
    end
  end
  return list[1]
end

local LOGS = logsDir()
local CMD_PATH = LOGS .. "livepulse_cmd.txt"
local HERO_PATH = LOGS .. "livepulse_hero.txt"
local HERO_PLATE_PATH = LOGS .. "livepulse_hero_plate.txt"
local GIFT_PLATE_PATH = LOGS .. "livepulse_plate.txt"
local GENERAL_PATH = LOGS .. "livepulse_general.txt"
local GENERAL_PLATE_PATH = LOGS .. "livepulse_general_plate.txt"

local function readLine(path)
  local handle = io.open(path, "r")
  if not handle then return "" end
  local line = handle:read("*l")
  handle:close()
  return tostring(line or "")
end

local function writeLine(path, text)
  local handle = io.open(path, "w")
  if not handle then return false end
  handle:write(text or "")
  handle:close()
  return true
end

local function platePath(line)
  local path = tostring(line or ""):match("^([^|]+)|%d+|%d+")
  if path == nil or path == "" then return "" end
  return path
end

local function imageOf(path)
  if path == nil or path == "" then return nil end
  local row = images[path]
  if row ~= nil and (row.img ~= nil or tick - row.tried < 45) then return row.img end
  local img = nil
  if Graphics ~= nil and Graphics.loadImage ~= nil then
    local ok, loaded = pcall(Graphics.loadImage, path)
    if ok and loaded ~= nil then img = loaded end
  end
  images[path] = { img = img, tried = tick }
  return img
end

local function drawPlate(path, x, y)
  local img = imageOf(path)
  if img == nil or Graphics == nil or Graphics.drawImage == nil then return false end
  local ok = pcall(Graphics.drawImage, img, math.floor(x - (img.width or 0) / 2), math.floor(y - (img.height or 0)))
  return ok
end

local function drawTextAt(text, x, y)
  if text == nil or text == "" or Text == nil or Text.print == nil then return end
  pcall(Text.print, tostring(text), math.floor(x - 36), math.floor(y - 16))
end

local function drawName(text, plate, x, y)
  if not drawPlate(plate, x, y) then drawTextAt(text, x, y) end
end

local function bannerScale()
  local w = 800
  if camera ~= nil and camera.width ~= nil and camera.width > 32 then w = camera.width end
  local scale = w / 256
  if scale < 2 then scale = 2 end
  if scale > 4 then scale = 4 end
  return scale
end

local function drawBannerPlate(path, x, y)
  local img = imageOf(path)
  if img == nil or Graphics == nil then return 0 end
  local scale = bannerScale()
  local w = math.floor((img.width or 0) * scale)
  local h = math.floor((img.height or 0) * scale)
  if w < 1 or h < 1 then return 0 end
  local drawX = math.floor(x - w / 2)
  local drawY = math.floor(y)
  if Graphics.drawBox ~= nil then
    local ok = pcall(Graphics.drawBox, {
      texture = img,
      x = drawX,
      y = drawY,
      width = w,
      height = h,
      priority = 8,
      sceneCoords = false,
      linearFiltered = false
    })
    if ok then return h end
  end
  return 0
end

local function bannerCount()
  local left = (general.untilAt or 0) - os.time()
  if general.phase == "go" or general.phase == "hold" then
    if left < 1 then return nil end
    if left > 120 then return 120 end
    return left
  end
  if left < 1 then return 1 end
  if left > 5 then return 5 end
  return left
end

local function drawBannerText(text, x, y)
  if text == nil or text == "" then return end
  local scale = bannerScale()
  if textplusApi ~= nil and textplusApi.print ~= nil then
    local ok = pcall(function()
      local args = {
        text = text,
        x = x,
        y = y,
        plaintext = true,
        xscale = scale,
        yscale = scale,
        priority = 9,
        sceneCoords = false,
        pivot = { 0.5, 0 },
        smooth = false
      }
      if Color ~= nil and Color.fromHexRGBA ~= nil then
        args.color = Color.fromHexRGBA(0xFFFF00FF)
      end
      textplusApi.print(args)
    end)
    if ok then return end
  end
  drawTextAt(text, x, y + 16)
end

local function drawGeneralBanner()
  if general.phase == "" or general.user == "" or camera == nil then return end
  local w = camera.width or 800
  local h = camera.height or 600
  local cx = math.floor(w / 2)
  local cy = math.floor(h / 2) - 24
  local nameH = drawBannerPlate(general.plate, cx, cy)
  if nameH < 1 then
    drawTextAt(general.user, cx, cy + 16)
    nameH = 16
  end
  local phrase = PHRASE[general.action] or ""
  local n = bannerCount()
  if n ~= nil then
    if phrase ~= "" then phrase = phrase .. "  " .. tostring(n) else phrase = tostring(n) end
  end
  if phrase ~= "" then drawBannerText(phrase, cx, cy + nameH + 8) end
end

local function readHero()
  heroName = readLine(HERO_PATH):gsub("^%s+", ""):gsub("%s+$", "")
  heroPlatePath = platePath(readLine(HERO_PLATE_PATH))
end

local function readGeneral()
  local line = readLine(GENERAL_PATH)
  local phase, action, user, untilText = line:match("^(%w+)|([^|]*)|([^|]*)|%d+|(%d+)")
  if not phase then
    general.phase = ""
    general.action = ""
    general.user = ""
    general.untilAt = 0
    general.plate = ""
    resetSent = false
    return
  end
  if phase ~= general.phase or action ~= general.action then resetSent = false end
  general.phase = phase
  general.action = action
  general.user = user or ""
  general.untilAt = tonumber(untilText) or 0
  general.plate = platePath(readLine(GENERAL_PLATE_PATH))
end

local function spawnAt(id, x, y, section)
  if NPC == nil or NPC.spawn == nil then return nil end
  local ok, npc = pcall(NPC.spawn, id, x, y, section, false, true)
  if not ok then return nil end
  return npc
end

local function tag(npc, user, x, y)
  if user == nil or user == "" then return end
  labels[#labels + 1] = {
    npc = npc,
    x = x,
    y = y,
    user = user,
    plate = giftPlatePath,
    left = 180
  }
end

local function applyCommand()
  local line = readLine(CMD_PATH)
  if line == "" then return end
  local cmd, user = line:match("^([%w_]+)|([^|]*)|")
  if not cmd then
    writeLine(CMD_PATH, "")
    return
  end
  if isOverworld or player == nil then return end
  writeLine(CMD_PATH, "")
  giftPlatePath = platePath(readLine(GIFT_PLATE_PATH))
  local section = player.section
  local x = player.x + (player.width or 32) + 20
  local y = player.y - 12
  if cmd == "LLUVIA_VIDAS" then
    if Misc ~= nil and Misc.lives ~= nil then
      local now = tonumber(Misc.lives()) or 0
      Misc.lives(math.min(99, now + 5), true)
    end
    tag(nil, user, player.x, player.y - 28)
    return
  end
  if cmd == "CAOS_GOOMBAS" then
    for i = 0, 5 do
      local npc = spawnAt(1, x + (i * 28), y - 40, section)
      tag(npc, user, x + (i * 28), y - 40)
    end
    return
  end
  local id = SPAWN[cmd]
  if id == nil then return end
  local npc = spawnAt(id, x, y, section)
  tag(npc, user, x, y)
end

local function setEngineSpeed(ratio)
  if engineSpeed == ratio then return end
  if Misc == nil or Misc.SetEngineSpeed == nil then return end
  local ok = pcall(function()
    if ratio == 1 and Misc.SetNominalSpeed ~= nil then Misc.SetNominalSpeed(1) end
    Misc.SetEngineSpeed(ratio, false)
  end)
  if ok then engineSpeed = ratio end
end

local function captureSnap()
  local snap = { npcs = {} }
  if player ~= nil then snap.section = player.section end
  if savestateApi ~= nil and savestateApi.save ~= nil then
    local ok, state = pcall(savestateApi.save, MASK_PLAY)
    if ok then snap.state = state end
  end
  if player ~= nil then
    snap.px = player.x
    snap.py = player.y
    snap.psx = player.speedX
    snap.psy = player.speedY
    snap.power = player.powerup
    snap.dir = player.direction
  end
  if NPC ~= nil and NPC.get ~= nil then
    local ok, list = pcall(NPC.get)
    if ok and list ~= nil then
      for i = 1, #list do
        local n = list[i]
        if n ~= nil and n.isValid ~= false and n.id ~= nil and n.id > 0 then
          snap.npcs[#snap.npcs + 1] = {
            id = n.id, x = n.x, y = n.y, sx = n.speedX, sy = n.speedY, dir = n.direction
          }
        end
      end
    end
  end
  return snap
end

local function placeNpc(src)
  local section = 0
  if player ~= nil and player.section ~= nil then section = player.section end
  local born = spawnAt(src.id, src.x, src.y, section)
  if born == nil then return end
  born.speedX = src.sx or 0
  born.speedY = src.sy or 0
  if src.dir ~= nil then born.direction = src.dir end
end

local function restoreSnap(snap)
  if snap == nil then return end
  if snap.state ~= nil and savestateApi ~= nil and savestateApi.load ~= nil then
    pcall(savestateApi.load, snap.state, MASK_PLAY)
  elseif player ~= nil and snap.px ~= nil then
    player.x = snap.px
    player.y = snap.py
    player.speedX = snap.psx or 0
    player.speedY = snap.psy or 0
    if snap.power ~= nil then player.powerup = snap.power end
    if snap.dir ~= nil then player.direction = snap.dir end
  end
  if player ~= nil and snap.section ~= nil and player.section ~= snap.section then return end
  if NPC == nil or NPC.get == nil or snap.npcs == nil then return end
  local ok, list = pcall(NPC.get)
  if not ok or list == nil then return end
  local live = {}
  for i = 1, #list do
    local n = list[i]
    if n ~= nil and n.isValid ~= false and n.id ~= nil and n.id > 0 then live[#live + 1] = n end
  end
  local want = snap.npcs
  local shared = #live
  if #want < shared then shared = #want end
  for i = 1, shared do
    local n = live[i]
    local src = want[i]
    if n.id == src.id then
      n.x = src.x
      n.y = src.y
      n.speedX = src.sx or 0
      n.speedY = src.sy or 0
      if src.dir ~= nil then n.direction = src.dir end
    else
      pcall(function() n:kill() end)
      placeNpc(src)
    end
  end
  for i = #want + 1, #live do
    pcall(function() live[i]:kill() end)
  end
  for i = #live + 1, #want do
    placeNpc(want[i])
  end
end

local function noteHistory()
  if rewindOn or isOverworld or player == nil then
    if isOverworld and #history > 0 then history = {} end
    return
  end
  if #history > 0 then
    local last = history[#history]
    if last.section ~= nil and player.section ~= last.section then history = {} end
  end
  if tick % 65 ~= 0 then return end
  local ok, snap = pcall(captureSnap)
  if not ok or snap == nil then return end
  history[#history + 1] = snap
  while #history > 130 do table.remove(history, 1) end
end

local function applyGeneral()
  local now = os.time()
  local active = general.phase ~= ""
  if active and general.untilAt > 0 and now > general.untilAt + 1 and general.phase ~= "pre" then
    writeLine(GENERAL_PATH, "")
    general.phase = ""
    general.action = ""
    active = false
  end
  local rewinding = active and general.phase == "go" and general.action == "rewinder" and now <= general.untilAt and not isOverworld
  if rewinding then
    if not rewindOn or rewindUntil ~= general.untilAt then
      rewindOn = true
      rewindUntil = general.untilAt
      rewindFrom = #history
      rewindSpan = general.untilAt - now
      if rewindSpan < 1 then rewindSpan = 1 end
      if rewindSpan > 120 then rewindSpan = 120 end
      rewindIndex = -1
    end
    local left = general.untilAt - now
    if left < 0 then left = 0 end
    local steps = rewindSpan - left
    if steps < 0 then steps = 0 end
    local index = rewindFrom - steps
    if index < 1 then index = 1 end
    if index > #history then index = #history end
    if steps >= 1 and index >= 1 and index ~= rewindIndex then
      rewindIndex = index
      restoreSnap(history[index])
    end
  elseif rewindOn then
    if rewindIndex >= 1 then
      while #history > rewindIndex do table.remove(history) end
    end
    rewindOn = false
    rewindIndex = -1
    rewindUntil = 0
  end
  local wantSpeed = 1
  if not rewindOn and active and general.phase == "go" and general.action == "acelerar" and now <= general.untilAt and not isOverworld then
    wantSpeed = 4
  end
  setEngineSpeed(wantSpeed)
  if not active or isOverworld then return end
  if general.phase == "go" and general.action == "terremoto" and Defines ~= nil then
    local shake = Defines.earthquake or 0
    if shake < 10 then Defines.earthquake = 10 end
  end
  if general.phase == "go" and general.action == "reiniciar" and not resetSent then
    resetSent = true
    history = {}
    local kept = "hold|reiniciar|" .. general.user .. "|4|" .. tostring(general.untilAt)
    if writeLine(GENERAL_PATH, kept .. "\n") and Level ~= nil and Level.load ~= nil then
      pcall(Level.load)
    end
  end
end

local api = {}

function api.onTick()
  tick = tick + 1
  if tick % 30 == 0 then readHero() end
  if tick % 3 == 0 then
    readGeneral()
    applyCommand()
  end
  applyGeneral()
  noteHistory()
  for i = #labels, 1, -1 do
    local row = labels[i]
    row.left = row.left - 1
    local gone = row.left <= 0
    if row.npc ~= nil and row.npc.isValid == false then gone = true end
    if gone then table.remove(labels, i) end
  end
end

local function screenOf(worldX, worldY)
  if camera == nil then return nil, nil end
  return math.floor(worldX - camera.x), math.floor(worldY - camera.y)
end

readHero()

function api.onHUDDraw()
  if player ~= nil and camera ~= nil and heroName ~= "" then
    local sx, sy = screenOf(player.x + (player.width or 32) / 2, player.y - 6)
    if sx ~= nil and sx > -80 and sx < 900 and sy > -40 and sy < 700 then
      drawName(heroName, heroPlatePath, sx, sy)
    end
  end
  if camera ~= nil then
    for i = 1, #labels do
      local row = labels[i]
      local worldX, worldY = row.x, row.y
      local npc = row.npc
      if npc ~= nil and npc.isValid ~= false and npc.x ~= nil then
        worldX = npc.x + (npc.width or 32) / 2
        worldY = npc.y - 4
      end
      if worldX ~= nil and worldY ~= nil then
        local sx, sy = screenOf(worldX, worldY)
        if sx ~= nil and sx > -80 and sx < 900 and sy > -40 and sy < 700 then
          drawName(row.user, row.plate, sx, sy)
        end
      end
    end
  end
  drawGeneralBanner()
end

setEngineSpeed(1)

if type(registerEvent) == "function" then
  registerEvent(api, "onTick")
  registerEvent(api, "onHUDDraw")
else
  onTick = api.onTick
  onHUDDraw = api.onHUDDraw
end
writeLine(LOGS .. "livepulse_seen.txt", "ok\n")
