-- Contra (USA) NES — LivePulse
-- Cada regalo ocupa un slot vacio (ENEMY_ROUTINE == 0) y lo deja como
-- initialize_enemy: rutina 1, sprite 1, y los 4 bytes de enemy_prop.
-- La rutina 1 es weapon/soldier/sniper/turret/jumper routine_00.
-- El juego mueve el objeto, dispara y aplica el arma al recogerla.
-- No se escribe el arma del jugador ($AA) ni el temporizador de barrera ($B0).
-- El saltador (tipo $16) solo existe en las bases, nivel actual 1 o 3.
-- En los demas niveles ese regalo crea un soldado que dispara.

local CMD_PATH = "C:\\LivePulse\\livepulse_cmd.txt"
local ON_PATH = "C:\\LivePulse\\livepulse_on.txt"
local STYLE_PATH = "C:\\LivePulse\\livepulse_style.txt"
local PLATE_PATH = "C:\\LivePulse\\livepulse_plate.txt"
local plateOf = {}
local heroName = ""

-- LivePulse pinta el nombre exacto, emojis incluidos, en un PNG.
-- gui.drawText no puede recibirlos: BizHawk 2.11 se congela.
local function readPlate()
  if io == nil or io.open == nil then return "" end
  local handle = io.open(PLATE_PATH, "r")
  if not handle then return "" end
  local line = handle:read("*l")
  handle:close()
  return tostring(line or ""):gsub("^\239\187\191", ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function rememberPlate(user)
  if user == nil or user == "" then return end
  local path, wText, hText = readPlate():match("^([^|]+)|(%d+)|(%d+)$")
  local w = tonumber(wText)
  local h = tonumber(hText)
  if path and w and h and w >= 1 and h >= 1 and w <= 2000 and h <= 400 then
    plateOf[user] = { path = path, w = w, h = h }
  else
    plateOf[user] = nil
  end
end

-- Las letras se pintan como pixeles del juego. Una imagen estirada tiembla al caminar.
local spanOf = {}
local plateHold = {}

local function loadSpans(path)
  local found = spanOf[path]
  if found then return found end
  if io == nil or io.open == nil then return nil end
  local handle = io.open(path .. ".px", "r")
  if not handle then return nil end
  local spans = {}
  for line in handle:lines() do
    local yText, xText, lenText, color8 = line:match("^(%d+) (%d+) (%d+) (%x%x%x%x%x%x%x%x)$")
    local color6 = nil
    if not yText then
      yText, xText, lenText, color6 = line:match("^(%d+) (%d+) (%d+) (%x%x%x%x%x%x)$")
    end
    if yText then
      local paint = color8 and tonumber(color8, 16) or (0xFF000000 + tonumber(color6, 16))
      spans[#spans + 1] = {
        y = tonumber(yText),
        x = tonumber(xText),
        len = tonumber(lenText),
        color = paint
      }
    end
  end
  handle:close()
  if #spans < 1 then return nil end
  spanOf[path] = spans
  return spans
end

local function stillPoint(key, x, y)
  local spot = plateHold[key]
  if not spot then
    plateHold[key] = { x = x, y = y, rawX = x, rawY = y, dx = 0, dy = 0 }
    return x, y
  end
  local dx = x - spot.rawX
  local dy = y - spot.rawY
  local function flip(delta, last)
    if delta == 0 or last == 0 then return false end
    if delta > 2 or delta < -2 or last > 2 or last < -2 then return false end
    return (delta > 0 and last < 0) or (delta < 0 and last > 0)
  end
  if not flip(dx, spot.dx) then spot.x = x end
  if not flip(dy, spot.dy) then spot.y = y end
  spot.dx = dx
  spot.dy = dy
  spot.rawX = x
  spot.rawY = y
  return spot.x, spot.y
end

local function drawPlate(px, py, plate, anchor)
  if type(plate) ~= "table" or not plate.path or plate.path == "" then return false end
  if not gui or not gui.drawLine then return false end
  local spans = loadSpans(plate.path)
  if not spans then return false end
  if gui.use_surface then gui.use_surface("emucore") end
  local w = math.max(1, math.floor(plate.w))
  local h = math.max(1, math.floor(plate.h))
  local x = math.floor(px) - math.floor(w / 2)
  local y = math.floor(py) - h
  if anchor == "top" then y = math.floor(py) end
  x, y = stillPoint(plate.path .. "|" .. (anchor or "bottom"), x, y)
  for i = 1, #spans do
    local s = spans[i]
    local x1 = x + s.x
    local y1 = y + s.y
    gui.drawLine(x1, y1, x1 + s.len - 1, y1, s.color, "emucore")
  end
  return h
end

local ENEMY_SPRITES = 0x030A
local ENEMY_Y = 0x0324
local ENEMY_X = 0x033E
local ENEMY_SPRITE_ATTR = 0x0358
local ENEMY_ROUTINE = 0x04B8
local ENEMY_Y_ACC = 0x04C8
local ENEMY_X_ACC = 0x04D8
local ENEMY_Y_FAST = 0x04E8
local ENEMY_Y_FRACT = 0x04F8
local ENEMY_X_FAST = 0x0508
local ENEMY_X_FRACT = 0x0518
local ENEMY_TYPE = 0x0528
local ENEMY_DELAY = 0x0538
local ENEMY_VAR_A = 0x0548
local ENEMY_VAR_B = 0x0558
local ENEMY_FRAME = 0x0568
local ENEMY_HP = 0x0578
local ENEMY_SCORE = 0x0588
local ENEMY_STATE = 0x0598
local ENEMY_FLAGS = 0x05A8
local ENEMY_V1 = 0x05B8
local ENEMY_V2 = 0x05C8
local ENEMY_V3 = 0x05D8
local ENEMY_V4 = 0x05E8

local PLAYER_Y = 0x031A
local PLAYER_X = 0x0334
local GAME_ROUTINE = 0x0018
local DEMO_MODE = 0x001C
local PAUSE_STATE = 0x0025
local LEVEL_ROUTINE = 0x002C
local CURRENT_LEVEL = 0x0030
local P1_GAME_OVER = 0x0038
local BOSS_FLAG = 0x003B
local PLAYER_STATE = 0x0090

local TYPE_ITEM = 0x00
local TYPE_SOLDIER = 0x05
local TYPE_SNIPER = 0x06
local TYPE_TURRET = 0x07
local TYPE_JUMPER = 0x16

local ATTR_RAPID = 0
local ATTR_MACHINE = 1
local ATTR_FIRE = 2
local ATTR_RIFLE = 3
local ATTR_LASER = 4
local ATTR_BARRIER = 5

local PROPS = {
  [TYPE_ITEM] = { 0x82, 0x22, 0x01, 0x00 },
  [TYPE_SOLDIER] = { 0x83, 0x10, 0x01, 0x00 },
  [TYPE_SNIPER] = { 0x83, 0x30, 0x01, 0x00 },
  [TYPE_TURRET] = { 0x8F, 0x30, 0x08, 0x00 },
  [TYPE_JUMPER] = { 0x13, 0x16, 0x01, 0x00 }
}

local CLEAR_AT = {
  ENEMY_SPRITES, ENEMY_Y, ENEMY_X, ENEMY_SPRITE_ATTR, ENEMY_ROUTINE,
  ENEMY_Y_ACC, ENEMY_X_ACC, ENEMY_Y_FAST, ENEMY_Y_FRACT,
  ENEMY_X_FAST, ENEMY_X_FRACT, ENEMY_TYPE, ENEMY_DELAY,
  ENEMY_VAR_A, ENEMY_VAR_B, ENEMY_FRAME, ENEMY_HP, ENEMY_SCORE,
  ENEMY_STATE, ENEMY_FLAGS, ENEMY_V1, ENEMY_V2, ENEMY_V3, ENEMY_V4
}

local function item(attr)
  return { kind = "item", attr = attr }
end

local function soldier(shoot)
  return { kind = "soldier", shoot = shoot }
end

local function sniper()
  return { kind = "sniper" }
end

local function turret()
  return { kind = "turret" }
end

local function jumper()
  return { kind = "jumper" }
end

local EFFECTS = {
  SPAWN_RIFLE = { name = "Rifle", units = { item(ATTR_RIFLE) } },
  SPAWN_MACHINEGUN = { name = "Ametralladora", units = { item(ATTR_MACHINE) } },
  SPAWN_LASER = { name = "Laser", units = { item(ATTR_LASER) } },
  SPAWN_FIREBALL = { name = "Bola de fuego", units = { item(ATTR_FIRE) } },
  SPAWN_BARRIER = { name = "Barrera", units = { item(ATTR_BARRIER) } },
  SPAWN_RAPID = { name = "Disparo rapido", units = { item(ATTR_RAPID) } },
  SPAWN_SOLDADO = { name = "Soldado", units = { soldier(true) } },
  SPAWN_SNIPER = { name = "Francotirador", units = { sniper() } },
  SPAWN_RUNNING = { name = "Corredor", units = { soldier(false) } },
  SPAWN_TURRET = { name = "Torreta", units = { turret() } },
  SPAWN_JUMPER = { name = "Saltador", units = { jumper() } },
  CAOS_SOLDADOS = {
    name = "Caos de soldados",
    units = { soldier(true), soldier(true), soldier(true), soldier(true), soldier(true) }
  },
  CAOS_ENEMIGOS = {
    name = "Caos de enemigos",
    units = { soldier(true), sniper(), soldier(false), turret(), jumper() }
  },
  LLUVIA_ENEMIGOS = {
    name = "Lluvia de enemigos",
    units = { soldier(true), soldier(false), sniper(), soldier(true), jumper() }
  },
  LLUVIA_ARMAS = {
    name = "Lluvia de armas",
    units = { item(ATTR_RIFLE), item(ATTR_MACHINE), item(ATTR_LASER), item(ATTR_FIRE), item(ATTR_RAPID) }
  },
  LLUVIA_BARRERAS = {
    name = "Lluvia de barreras",
    units = { item(ATTR_BARRIER), item(ATTR_BARRIER), item(ATTR_BARRIER), item(ATTR_BARRIER), item(ATTR_BARRIER) }
  }
}

local frame = 0
local nameStyle = { size = 16, font = "Segoe UI", style = "regular", color = 0xFFFFFF00, back = 0x00000000 }
local hudNote = ""
local hudUntil = 0
local ramReady = false
local owned = {}

pcall(function()
  if memory and memory.usememorydomain then
    memory.usememorydomain("RAM")
    ramReady = true
  end
end)

local function read8(addr)
  if ramReady and memory and memory.readbyte then
    local ok, value = pcall(memory.readbyte, addr)
    if ok and type(value) == "number" then return value % 256 end
  end
  if mainmemory and mainmemory.readbyte then
    local ok, value = pcall(mainmemory.readbyte, addr)
    if ok and type(value) == "number" then return value % 256 end
  end
  return nil
end

local function write8(addr, value)
  local byte = math.floor(value) % 256
  if ramReady and memory and memory.writebyte then
    local ok = pcall(memory.writebyte, addr, byte)
    if ok then return true end
  end
  if mainmemory and mainmemory.writebyte then
    local ok = pcall(mainmemory.writebyte, addr, byte)
    if ok then return true end
  end
  return false
end

local function clamp(value, lo, hi)
  if value < lo then return lo end
  if value > hi then return hi end
  return value
end

local function tagName(user)
  local name = tostring(user or "Alguien"):gsub("[\r\n|]", " "):gsub("^%s+", ""):gsub("%s+$", "")
  if name == "" then name = "Alguien" end
  if utf8 and utf8.offset then
    local cut = utf8.offset(name, 49)
    if cut then name = name:sub(1, cut - 1) end
  elseif #name > 48 then
    name = name:sub(1, 48)
  end
  return name
end

local function deleteCmd()
  pcall(os.remove, CMD_PATH)
  local handle = io.open(CMD_PATH, "r")
  if handle then
    handle:close()
    local wipe = io.open(CMD_PATH, "w")
    if wipe then wipe:close() end
    pcall(os.remove, CMD_PATH)
  end
end

local function readCmd()
  if io == nil or io.open == nil then return nil end
  local handle = io.open(CMD_PATH, "r")
  if not handle then return nil end
  local raw = handle:read("*l")
  handle:close()
  if raw == nil then return nil end
  raw = raw:gsub("^\239\187\191", ""):gsub("\r", ""):gsub("^%s+", ""):gsub("%s+$", "")
  if raw == "" then
    deleteCmd()
    return nil
  end
  return raw
end

local function parse(line)
  local cmd, user = line:match("^([%w_]+)|([^|\r\n]*)|")
  if not cmd then return nil end
  return string.upper(cmd), tagName(user)
end

-- $07FF = $A5 es la firma de arranque de Super Mario Bros. 1.
local function smb1()
  return read8(0x07FF) == 0xA5
end

-- 0 es el jugador 1. 1 es el jugador 2. Nil si ninguno está jugando.
local function activePlayer()
  if read8(PLAYER_STATE) == 1 and (read8(P1_GAME_OVER) or 1) == 0 then
    return 0
  end
  if read8(0x0091) == 1 and (read8(0x0039) or 1) == 0 then
    return 1
  end
  return nil
end

-- Nivel en juego: rutina de partida 5, rutina de nivel 4, sin pausa,
-- sin demo, al menos un jugador normal y sin jefe ya vencido.
local function playable()
  if smb1() then return false end
  if read8(GAME_ROUTINE) ~= 5 then return false end
  if read8(LEVEL_ROUTINE) ~= 4 then return false end
  if (read8(PAUSE_STATE) or 1) ~= 0 then return false end
  if (read8(DEMO_MODE) or 1) ~= 0 then return false end
  if (read8(BOSS_FLAG) or 1) ~= 0 then return false end
  if activePlayer() == nil then return false end
  local level = read8(CURRENT_LEVEL)
  if level == nil or level > 7 then return false end
  return true
end

local function baseLevel()
  local level = read8(CURRENT_LEVEL)
  return level == 1 or level == 3
end

local function heartbeat(on)
  if not on then
    pcall(os.remove, ON_PATH)
    return
  end
  local handle = io.open(ON_PATH, "w")
  if handle then
    handle:write("1")
    handle:close()
  end
end

local function flashHud(text)
  hudNote = tostring(text or "")
  hudUntil = frame + 120
end

local function findSlot()
  local slot = 15
  while slot >= 7 do
    if read8(ENEMY_ROUTINE + slot) == 0 then return slot end
    slot = slot - 1
  end
  slot = 6
  while slot >= 0 do
    if read8(ENEMY_ROUTINE + slot) == 0 then return slot end
    slot = slot - 1
  end
  return nil
end

local function writeSlot(slot, enemyType, x, y, attr)
  local props = PROPS[enemyType]
  if not props then return false end
  local index = 1
  while index <= #CLEAR_AT do
    if not write8(CLEAR_AT[index] + slot, 0) then return false end
    index = index + 1
  end
  if not write8(ENEMY_TYPE + slot, enemyType) then return false end
  if not write8(ENEMY_X + slot, x) then return false end
  if not write8(ENEMY_Y + slot, y) then return false end
  if not write8(ENEMY_FLAGS + slot, attr) then return false end
  if not write8(ENEMY_STATE + slot, props[1]) then return false end
  if not write8(ENEMY_SCORE + slot, props[2]) then return false end
  if not write8(ENEMY_HP + slot, props[3]) then return false end
  if not write8(ENEMY_VAR_A + slot, props[4]) then return false end
  if not write8(ENEMY_SPRITES + slot, 1) then return false end
  if not write8(ENEMY_ROUTINE + slot, 1) then return false end
  return true
end

local function leftRunnerX(index, px)
  local x = px + 40 + (index - 1) * 18
  if px > 160 then
    x = 220 - (index - 1) * 18
  end
  return clamp(x, 48, 224)
end

local function place(unit, index, lead, px, py)
  if unit.kind == "item" then
    local dir = 1
    if px > 112 then dir = -1 end
    local x = clamp(px + dir * (32 + (index - 1) * 20), 32, 216)
    local y = clamp(py - 28, 36, 168)
    return TYPE_ITEM, x, y, unit.attr
  end
  if unit.kind == "sniper" then
    local dir = 1
    if px > 128 then dir = -1 end
    local x = clamp(px + dir * (52 + (index - 1) * 16), 24, 220)
    return TYPE_SNIPER, x, clamp(py, 32, 208), 0
  end
  if unit.kind == "turret" then
    local x = clamp(0xD0 - (index - 1) * 18, 0x48, 0xE0)
    local y = clamp(py, 0x50, 0xB0)
    return TYPE_TURRET, x, y, 0
  end
  if unit.kind == "jumper" then
    if not baseLevel() then
      return place(soldier(true), index, false, px, py)
    end
    local fromLeft = px >= 128
    if index % 2 == 0 then fromLeft = not fromLeft end
    local attr = 0
    if fromLeft then attr = 1 end
    return TYPE_JUMPER, px, py, attr
  end
  if unit.kind == "soldier" then
    local attr = 0x02
    if unit.shoot then attr = attr + 0x04 end
    local x = leftRunnerX(index, px)
    if lead and px >= 176 then
      attr = attr + 0x01
      x = px
    end
    return TYPE_SOLDIER, x, clamp(py, 0x20, 0xD0), attr
  end
  return nil
end

local function spawnWave(effect, user)
  local made = 0
  local index = 1
  local total = #effect.units
  while index <= total do
    local slot = findSlot()
    if not slot then break end
    local who = activePlayer()
    if who == nil then break end
    local px = read8(PLAYER_X + who)
    local py = read8(PLAYER_Y + who)
    if not px or not py then break end
    local enemyType, x, y, attr = place(effect.units[index], index, total == 1, px, py)
    if enemyType and writeSlot(slot, enemyType, x, y, attr) then
      owned[slot] = { name = user, kind = enemyType, born = frame }
      made = made + 1
    end
    index = index + 1
  end
  return made
end

local function poll()
  local line = readCmd()
  if not line then return end
  local cmd, user = parse(line)
  local effect = cmd and EFFECTS[cmd] or nil
  if not effect then
    deleteCmd()
    return
  end
  rememberPlate(user)
  if not playable() then return end
  if not findSlot() then return end
  local made = spawnWave(effect, user)
  if made < 1 then return end
  deleteCmd()
  flashHud(effect.name)
end

local STYLE_FONTS = {
  ["Segoe UI Emoji"] = true,
  ["Segoe UI"] = true,
  ["Arial"] = true,
  ["Tahoma"] = true,
  ["Consolas"] = true,
  ["Comic Sans MS"] = true,
  ["Impact"] = true
}
local STYLE_WEIGHTS = {
  regular = true,
  bold = true,
  italic = true,
  ["bold italic"] = true
}

local HERO_PATH = "C:\\LivePulse\\livepulse_hero.txt"
local HERO_PLATE_PATH = "C:\\LivePulse\\livepulse_hero_plate.txt"
local HERO_STYLE_PATH = "C:\\LivePulse\\livepulse_hero_style.txt"
local heroText = { size = 16, font = "Segoe UI", style = "regular", color = 0xFFFFFF00, back = 0x00000000 }
local heroPlate = nil

local function loadHero()
  if io == nil or io.open == nil then return end
  local styleFile = io.open(HERO_STYLE_PATH, "r")
  if styleFile then
    local styleLine = styleFile:read("*l")
    styleFile:close()
    local sizeText, font, weight, color, backText = tostring(styleLine or ""):match("^(%d+)|([^|\r\n]+)|([^|\r\n]+)|(%x%x%x%x%x%x)|([^|\r\n]*)")
    if not sizeText then
      sizeText, font, weight, color = tostring(styleLine or ""):match("^(%d+)|([^|\r\n]+)|([^|\r\n]+)|(%x%x%x%x%x%x)$")
      backText = "none"
    end
    local size = tonumber(sizeText)
    if size and size >= 12 and size <= 32 then heroText.size = size end
    if font and font ~= "Segoe UI Emoji" and STYLE_FONTS[font] then heroText.font = font end
    if weight and STYLE_WEIGHTS[weight] then heroText.style = weight end
    local rgb = tonumber(color or "", 16)
    if rgb then heroText.color = 0xFF000000 + rgb end
    heroText.back = 0x00000000
    if backText and string.match(backText, "^%x%x%x%x%x%x$") then
      local backRgb = tonumber(backText, 16)
      if backRgb then heroText.back = 0xFF000000 + backRgb end
    end
  end
  local handle = io.open(HERO_PATH, "r")
  if not handle then
    heroName = ""
    heroPlate = nil
    return
  end
  local line = handle:read("*l")
  handle:close()
  local name = tostring(line or ""):gsub("^\239\187\191", ""):gsub("[\r\n|]", " "):gsub("^%s+", ""):gsub("%s+$", "")
  if name == "" then
    heroName = ""
    heroPlate = nil
    return
  end
  heroName = name
  heroPlate = nil
  local plate = io.open(HERO_PLATE_PATH, "r")
  if not plate then return end
  local raw = plate:read("*l")
  plate:close()
  local path, wText, hText = tostring(raw or ""):match("^([^|]+)|(%d+)|(%d+)$")
  local w = tonumber(wText)
  local h = tonumber(hText)
  if path and w and h and w >= 1 and h >= 1 and w <= 2000 and h <= 400 then
    heroPlate = { path = path, w = w, h = h }
  end
end

local function loadStyle()
  loadHero()
  if io == nil or io.open == nil then return end
  local handle = io.open(STYLE_PATH, "r")
  if not handle then return end
  local line = handle:read("*l")
  handle:close()
  if not line then return end
  local sizeText, font, weight, color, backText = line:match("^(%d+)|([^|\r\n]+)|([^|\r\n]+)|(%x%x%x%x%x%x)|([^|\r\n]*)")
  if not sizeText then
    sizeText, font, weight, color = line:match("^(%d+)|([^|\r\n]+)|([^|\r\n]+)|(%x%x%x%x%x%x)$")
    backText = "none"
  end
  local size = tonumber(sizeText)
  if not size or size < 12 or size > 32 then size = 16 end
  if not font or font == "Segoe UI Emoji" or not STYLE_FONTS[font] then font = "Segoe UI" end
  if not STYLE_WEIGHTS[weight] then weight = "regular" end
  local rgb = tonumber(color, 16) or 0xFFFF00
  nameStyle.size = size
  nameStyle.font = font
  nameStyle.style = weight
  nameStyle.color = 0xFF000000 + rgb
  nameStyle.back = 0x00000000
  if backText and string.match(backText, "^%x%x%x%x%x%x$") then
    local backRgb = tonumber(backText, 16)
    if backRgb then nameStyle.back = 0xFF000000 + backRgb end
  end
end

-- BizHawk 2.11 se cuelga dentro de drawText si la fuente es Segoe UI Emoji
-- o si el texto trae un emoji. Los acentos se quedan; el emoji no se pinta.
local function plainName(text)
  local src = tostring(text or "")
  local out = {}
  local i = 1
  while i <= #src do
    local b = src:byte(i)
    local len = 1
    if b >= 240 then len = 4
    elseif b >= 224 then len = 3
    elseif b >= 192 then len = 2
    end
    if i + len - 1 > #src then break end
    if b < 224 then out[#out + 1] = src:sub(i, i + len - 1) end
    i = i + len
  end
  return (table.concat(out):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function labelFont(style)
  local font = (style or nameStyle).font
  if font == nil or font == "" or font == "Segoe UI Emoji" then return "Segoe UI" end
  return font
end

local function drawLabel(px, py, text, style)
  local look = style or nameStyle
  local tx = math.floor(px)
  local ty = math.floor(py)
  if tx < 20 then tx = 20 end
  if tx > 236 then tx = 236 end
  if ty < 18 then ty = 18 end
  if ty > 210 then ty = 210 end
  local shown = tostring(text or "")
  local plate = plateOf[shown]
  if style == heroText then plate = heroPlate end
  if drawPlate(tx, ty, plate) then return end
  local safe = plainName(shown)
  pcall(gui.pixelText, math.max(4, tx - 8), math.max(4, ty - 10), safe ~= "" and safe or "?", 0xFFFFFF00, look.back)
end

local function drawNames()
  if not playable() then return end
  local slot = 0
  while slot <= 15 do
    local own = owned[slot]
    if own and frame > own.born then
      local routine = read8(ENEMY_ROUTINE + slot)
      local kind = read8(ENEMY_TYPE + slot)
      if routine and routine ~= 0 and kind == own.kind then
        local sx = read8(ENEMY_X + slot)
        local sy = read8(ENEMY_Y + slot)
        if sx and sy then
          drawLabel(sx + 8, sy - 4, own.name)
        end
      else
        owned[slot] = nil
      end
    end
    slot = slot + 1
  end
end

local function drawHero()
  if heroName == "" or smb1() then return end
  if read8(GAME_ROUTINE) ~= 5 then return end
  if read8(LEVEL_ROUTINE) ~= 4 then return end
  if (read8(DEMO_MODE) or 1) ~= 0 then return end
  if (read8(BOSS_FLAG) or 1) ~= 0 then return end
  local who = activePlayer()
  if who == nil then return end
  local level = read8(CURRENT_LEVEL)
  if level == nil or level > 7 then return end
  local px = read8(PLAYER_X + who)
  local py = read8(PLAYER_Y + who)
  if not px or not py then return end
  drawLabel(px + 8, py - 4, heroName, heroText)
end

local function drawHud()
  pcall(function()
    if gui.drawText then
      gui.drawText(128, 4, "livepulse", 0x99FFFFFF, 0x00000000, 11, "Segoe UI", "regular", "center", "top")
      local note = plainName(hudNote)
      if note ~= "" and frame <= hudUntil then
        gui.drawText(128, 16, note, 0xCCFFFFFF, 0x00000000, 11, "Segoe UI", "regular", "center", "top")
      end
    else
      gui.pixelText(104, 4, "livepulse", 0x99FFFFFF, 0x00000000)
    end
  end)
end

local function clearOwned()
  local slot = 0
  while slot <= 15 do
    owned[slot] = nil
    slot = slot + 1
  end
end

local function keepSprites()
  return (read8(PAUSE_STATE) or 0) ~= 0
end

deleteCmd()
pcall(os.remove, ON_PATH)
pcall(os.remove, "C:\\LivePulse\\livepulse_place.txt")
loadStyle()
local wasActive = false

while true do
  frame = frame + 1
  local active = playable()
  if active ~= wasActive then
    heartbeat(active)
    wasActive = active
  elseif active and frame % 30 == 0 then
    heartbeat(true)
  end
  if frame % 30 == 0 then
    loadStyle()
  end
  if not active then
    if not keepSprites() then
      clearOwned()
    end
  else
    poll()
    drawNames()
  end
  pcall(drawHero)
  drawHud()
  emu.frameadvance()
end
