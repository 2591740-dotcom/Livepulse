-- Super Mario Bros. 3 (NES) USA — LivePulse
-- El objeto nace como lo hace un bloque del juego: slot vacio,
-- Level_ObjectID con un ID global, X/XHi/Y/YHi junto a Mario,
-- Objects_SpawnIdx = $FF y Objects_State = 1. Al frame siguiente
-- el motor calcula el grupo, carga la pagina, corre el init y
-- la fisica. No se escribe ObjGroupRel_Idx ni Player_Suit.
-- Tanooki es el objeto estrella con el frame 1. Player_BounceDir
-- en 0 y PUp_StarManFlash sin bits bajos hacen que el item caiga
-- en vez de salir de un bloque. Los enemigos usan solo los slots
-- 0-4, que son los que tienen sus variables.

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

local ID_1UP = 0x0B
local ID_STAR = 0x0C
local ID_MUSH = 0x0D
local ID_FLOWER = 0x19
local ID_LEAF = 0x1E
local ID_KOOPA = 0x6D
local ID_GOOMBA = 0x72
local ID_PARAGOOMBA = 0x73
local ID_BILL = 0x78
local ID_HAMMER = 0x81
local ID_LAKITU = 0x83
local ID_PIRANHA = 0xA6

local STATE = 0x0661
local OBJ_ID = 0x0671
local SPAWN_IDX = 0x0659
local X_HI = 0x0076
local Y_HI = 0x0088
local OBJ_X = 0x0091
local OBJ_Y = 0x00A3
local SPRITE_X = 0x00AC
local SPRITE_Y = 0x00B5
local X_VEL = 0x00BE
local FLIP = 0x0679
local PLAYER_X = 0x0090
local PLAYER_XHI = 0x0075
local PLAYER_Y = 0x00A2
local PLAYER_YHI = 0x0087
local BOUNCE_DIR = 0x057D
local STAR_FLASH = 0x0586
local LEVEL_EVENT = 0x0566
local SOUND = 0x04F2
local SND_RISE = 0x02
local LIFE_CAP = 99
local WAVE = 5

local function copies(id, count)
  local list = {}
  for index = 1, count do
    list[index] = id
  end
  return list
end

local EFFECTS = {
  SPAWN_HONGO = { kind = "item", ids = copies(ID_MUSH, 1), lift = 48, flash = 0, name = "Hongo" },
  SPAWN_FLOR = { kind = "item", ids = copies(ID_FLOWER, 1), lift = 48, flash = 0, name = "Flor" },
  SPAWN_HOJA = { kind = "item", ids = copies(ID_LEAF, 1), lift = 56, flash = 0, name = "Hoja" },
  SPAWN_ESTRELLA = { kind = "item", ids = copies(ID_STAR, 1), lift = 48, flash = 0x80, flashStay = 0x80, name = "Estrella" },
  SPAWN_1UP = { kind = "item", ids = copies(ID_1UP, 1), lift = 48, flash = 0, name = "1-Up" },
  SPAWN_TANOOKI = { kind = "item", ids = copies(ID_STAR, 1), lift = 48, flash = 1, name = "Tanooki" },
  LLUVIA_VIDAS = { kind = "item", ids = copies(ID_1UP, WAVE), lift = 56, flash = 0, name = "Lluvia de vidas" },
  LLUVIA_HONGOS = { kind = "item", ids = copies(ID_MUSH, WAVE), lift = 56, flash = 0, name = "Lluvia de hongos" },
  LLUVIA_ESTRELLAS = { kind = "item", ids = copies(ID_STAR, WAVE), lift = 56, flash = 0x80, flashStay = 0x80, name = "Lluvia de estrellas" },
  SPAWN_GOOMBA = { kind = "enemy", ids = copies(ID_GOOMBA, 1), lift = 24, name = "Goomba" },
  SPAWN_KOOPA = { kind = "enemy", ids = copies(ID_KOOPA, 1), lift = 24, name = "Koopa" },
  SPAWN_HAMMERBRO = { kind = "enemy", ids = copies(ID_HAMMER, 1), lift = 24, name = "Hammer Bro" },
  SPAWN_PIRANHA = { kind = "enemy", ids = copies(ID_PIRANHA, 1), lift = 0, name = "Planta Piraña" },
  SPAWN_LAKITU = { kind = "enemy", ids = copies(ID_LAKITU, 1), lift = 32, name = "Lakitu" },
  SPAWN_BALA = { kind = "enemy", ids = copies(ID_BILL, 1), lift = 8, name = "Bala" },
  CAOS_GOOMBAS = { kind = "enemy", ids = copies(ID_GOOMBA, WAVE), lift = 24, name = "Caos Goombas" },
  CAOS_KOOPAS = { kind = "enemy", ids = copies(ID_KOOPA, WAVE), lift = 24, name = "Caos Koopas" },
  LLUVIA_ENEMIGOS = {
    kind = "enemy",
    ids = { ID_GOOMBA, ID_KOOPA, ID_GOOMBA, ID_KOOPA, ID_PARAGOOMBA },
    lift = 28,
    name = "Lluvia de enemigos"
  },
  EJERCITO = {
    kind = "enemy",
    ids = { ID_GOOMBA, ID_KOOPA, ID_HAMMER, ID_LAKITU, ID_PARAGOOMBA },
    lift = 28,
    name = "Ejército"
  }
}

local frame = 0
local nameStyle = { size = 16, font = "Segoe UI", style = "regular", color = 0xFFFFFF00, back = 0x00000000 }
local hudNote = ""
local hudUntil = 0
local ramReady = false
local owned = {}
local flashArmed = false
local flashSaved = 0
local flashHeld = false

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

-- Nivel en marcha: mapa normal o vertical, tileset de nivel, sin pausa,
-- sin muerte, sin tubo, sin union y con Mario ya colocado.
local function playable()
  if smb1() then return false end
  local mode = read8(0x0100)
  if mode ~= 0xC0 and mode ~= 0x80 then return false end
  local tileset = read8(0x070A)
  if not tileset or tileset < 1 or tileset > 14 then return false end
  if (read8(0x0376) or 1) ~= 0 then return false end
  if (read8(0x00F1) or 1) ~= 0 then return false end
  if (read8(0x00CE) or 1) ~= 0 then return false end
  if (read8(0x0571) or 1) ~= 0 then return false end
  if (read8(0x03DE) or 1) ~= 0 then return false end
  if (read8(0x0559) or 1) ~= 0 then return false end
  if (read8(0x00EB) or 0) == 0 then return false end
  return true
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

local function add16(lo, hi, delta)
  local sum = lo + delta
  while sum < 0 do
    sum = sum + 256
    hi = (hi - 1) % 256
  end
  while sum > 255 do
    sum = sum - 256
    hi = (hi + 1) % 256
  end
  return sum % 256, hi % 256
end

local function slotFree(slot)
  return (read8(STATE + slot) or 1) == 0
end

local function findEnemySlot()
  for slot = 0, 4 do
    if slotFree(slot) then return slot end
  end
  return nil
end

local function findPowerSlot()
  for slot = 5, 7 do
    if slotFree(slot) then return slot end
  end
  for slot = 0, 4 do
    if slotFree(slot) then return slot end
  end
  return nil
end

local function releaseFlash()
  if not flashArmed then return end
  write8(STAR_FLASH, flashSaved)
  flashArmed = false
end

-- El init lee PUp_StarManFlash en el frame del juego. 0 cae,
-- 1 es el traje Tanooki y $80 es la estrella con ciclo de color.
-- Al frame siguiente se restaura el byte anterior.
local function holdFlash(value)
  if not flashArmed then
    flashSaved = read8(STAR_FLASH) or 0
    flashArmed = true
  end
  write8(STAR_FLASH, value or 0)
end

local function releaseStarFlash()
  if not flashHeld then return end
  for slot = 0, 7 do
    local own = owned[slot]
    if own and own.rainbow then return end
  end
  write8(STAR_FLASH, 0)
  flashHeld = false
end

local function kickBullet(slot)
  local ox = read8(OBJ_X + slot)
  local oxh = read8(X_HI + slot)
  local px = read8(PLAYER_X)
  local pxh = read8(PLAYER_XHI)
  if not ox or not oxh or not px or not pxh then return end
  local objectPos = oxh * 256 + ox
  local playerPos = pxh * 256 + px
  local vel = 0xE8
  local flip = 0x00
  if playerPos >= objectPos then
    vel = 0x18
    flip = 0x40
  end
  write8(X_VEL + slot, vel)
  write8(FLIP + slot, flip)
end

local function maintain()
  for slot = 0, 7 do
    local own = owned[slot]
    if own then
      local state = read8(STATE + slot) or 0
      local id = read8(OBJ_ID + slot)
      if state == 0 or id ~= own.id then
        owned[slot] = nil
      elseif own.bullet and not own.kicked and state >= 2 then
        kickBullet(slot)
        own.kicked = true
      end
    end
  end
  releaseStarFlash()
end

local function spawnAt(slot, id, spread, lift, user, rainbow)
  local x = read8(PLAYER_X)
  local xhi = read8(PLAYER_XHI)
  local y = read8(PLAYER_Y)
  local yhi = read8(PLAYER_YHI)
  if not x or not xhi or not y or not yhi then return false end
  local nx, nxhi = add16(x, xhi, spread)
  local ny, nyhi = add16(y, yhi, -(lift or 0))
  if not write8(X_HI + slot, nxhi) then return false end
  if not write8(OBJ_X + slot, nx) then return false end
  if not write8(Y_HI + slot, nyhi) then return false end
  if not write8(OBJ_Y + slot, ny) then return false end
  if not write8(OBJ_ID + slot, id) then return false end
  if not write8(SPAWN_IDX + slot, 0xFF) then return false end
  if not write8(STATE + slot, 1) then return false end
  owned[slot] = {
    id = id,
    name = user,
    bullet = id == ID_BILL,
    kicked = false,
    born = frame,
    rainbow = rainbow and true or false
  }
  return true
end

-- El power-up sale al lado con mas pantalla, lejos de Mario.
-- Player_SpriteX marca el borde para que no nazca fuera.
local function itemSpread(index, total)
  local spriteX = read8(0x00AB) or 128
  local roomRight = 236 - spriteX
  local roomLeft = spriteX - 20
  local sign = 1
  local room = roomRight
  if roomLeft > roomRight then
    sign = -1
    room = roomLeft
  end
  if room > 168 then room = 168 end
  local near = 96
  if total > 1 then near = 80 end
  if near > room then near = room end
  local dist = near
  if total > 1 and room > near then
    dist = near + math.floor((index - 1) * (room - near) / (total - 1))
  end
  return sign * dist
end

local function spawnList(effect, user)
  local total = #effect.ids
  local made = 0
  local lift = effect.lift or 24
  local event = read8(LEVEL_EVENT) or 0
  for index = 1, total do
    local id = effect.ids[index]
    if id == ID_HAMMER and total > 1 and event == 7 then
      id = ID_GOOMBA
    end
    local slot = nil
    if effect.kind == "enemy" then
      slot = findEnemySlot()
    else
      slot = findPowerSlot()
    end
    if slot then
      local spread = 0
      if effect.kind == "item" then
        spread = itemSpread(index, total)
      else
        spread = math.floor((index - 1 - (total - 1) / 2) * 28 + 0.5)
        if id == ID_BILL then
          if spread >= 0 then spread = spread + 48 else spread = spread - 48 end
        end
      end
      if spawnAt(slot, id, spread, lift, user, effect.flashStay ~= nil) then
        made = made + 1
      end
    end
  end
  return made
end

local function clampLives()
  local addr = 0x0736
  if (read8(0x0726) or 0) ~= 0 then addr = 0x0737 end
  local lives = read8(addr)
  if lives and lives > LIFE_CAP and lives < 128 then
    write8(addr, LIFE_CAP)
  end
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
  if not playable() then
    return
  end
  if effect.kind == "item" and (read8(BOUNCE_DIR) or 0) ~= 0 then
    return
  end
  if effect.kind == "enemy" and effect.ids[1] == ID_HAMMER and #effect.ids == 1 and (read8(LEVEL_EVENT) or 0) == 7 then
    deleteCmd()
    return
  end
  local slotReady = findPowerSlot()
  if effect.kind == "enemy" then slotReady = findEnemySlot() end
  if not slotReady then return end
  if effect.kind == "item" then
    holdFlash(effect.flash or 0)
  end
  local made = spawnList(effect, user)
  if made < 1 then return end
  if effect.flashStay and flashSaved ~= effect.flashStay then
    flashSaved = effect.flashStay
    flashHeld = true
  end
  if effect.kind == "item" and (read8(SOUND) or 1) == 0 then
    write8(SOUND, SND_RISE)
  end
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
  for slot = 0, 7 do
    local own = owned[slot]
    if own and frame > own.born then
      local sx = read8(SPRITE_X + slot)
      local sy = read8(SPRITE_Y + slot)
      if sx and sy then
        drawLabel(sx + 8, sy - 4, own.name)
      end
    end
  end
end

-- $AB y $B4 son la X y la Y de Mario en la pantalla.
local function drawHero()
  if heroName == "" or smb1() then return end
  local mode = read8(0x0100)
  if mode ~= 0xC0 and mode ~= 0x80 then return end
  local tileset = read8(0x070A)
  if not tileset or tileset < 1 or tileset > 14 then return end
  local sx = read8(0x00AB)
  local sy = read8(0x00B4)
  if not sx or not sy then return end
  drawLabel(sx + 8, sy - 4, heroName, heroText)
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
  for slot = 0, 7 do
    owned[slot] = nil
  end
end

-- La pausa y el crecimiento paran el nivel, pero los sprites siguen.
local function keepSprites()
  if (read8(0x0376) or 0) ~= 0 then return true end
  if (read8(0x00CE) or 0) ~= 0 then return true end
  return false
end

deleteCmd()
pcall(os.remove, ON_PATH)
pcall(os.remove, "C:\\LivePulse\\livepulse_place.txt")
loadStyle()
local wasActive = false
local accept = false

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
  releaseFlash()
  if not active then
    accept = false
    if not keepSprites() then
      clearOwned()
      if flashHeld then
        write8(STAR_FLASH, 0)
        flashHeld = false
      end
    end
  else
    accept = true
    maintain()
    clampLives()
    poll()
    drawNames()
  end
  pcall(drawHero)
  drawHud()
  emu.frameadvance()
end
