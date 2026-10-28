-- Metal Slug 2. Las direcciones son las de los cheats de MAME/Kawaks, dentro de
-- la RAM del 68000 (0x100000-0x10FFFF). El offset 0 de ese dominio es $100000.
-- El regalo entra directo al jugador. Unos 3 s al centro: (usuario) activo (powerup).
-- Este programa no tiene el reparto de objetos del 1, asi que no se copia.
-- Se escribe el arma, las granadas, la municion, la vida o el invencible.
-- Caos aplica las seis partes en el acto. Lluvia de vidas suma 5.
-- La misma arma suma la recarga y se corta en 255. Las granadas se cortan en 99.
-- La invencibilidad se reescribe unos segundos: el juego borra ese byte solo.
-- No se toca el tiempo ni el canon del vehiculo.

local CMD_PATH = "C:\\LivePulse\\livepulse_cmd.txt"
local ON_PATH = "C:\\LivePulse\\livepulse_on.txt"
local STYLE_PATH = "C:\\LivePulse\\livepulse_style.txt"
local PLATE_PATH = "C:\\LivePulse\\livepulse_plate.txt"
local plateOf = {}
local heroName = ""

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
  if #spans < 1 then return false end
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

-- Igual que Metal Slug 1: las letras son pixeles del juego. Una imagen estirada no sigue el paso.
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

local TIMER_ADDR = 0x1013B5
local LIFE_CAP = 9
local BOMB_CAP = 99
local AMMO_CAP = 255
local INV_VALUE = 0x77
local INV_FRAMES = 480

local PLAYERS = {
  {
    lives = 0x101277,
    bombs = 0x10C349,
    ammo = 0x10C34C,
    inv = 0x101516,
    flag = 0x101525,
    weapon = 0x10C346
  },
  {
    lives = 0x10131F,
    bombs = 0x10C348,
    ammo = 0x10C34E,
    inv = 0x1015BE,
    flag = 0x1015CD,
    weapon = 0x10C347
  }
}

-- Municion inicial y recarga del juego: escopeta, cohete y llamas 30/20.
-- Ametralladora y laser 200/150. El byte de RAM llega solo hasta 255.
local PACK = {
  [0] = { ammo = 30, add = 20 },
  [1] = { ammo = 30, add = 20 },
  [2] = { ammo = 30, add = 20 },
  [3] = { ammo = 200, add = 150 },
  [4] = { ammo = 200, add = 150 }
}

local EFFECTS = {
  SPAWN_SHOTGUN = { kind = "weapon", weapon = 0, label = "Escopeta" },
  SPAWN_ROCKET = { kind = "weapon", weapon = 1, label = "Lanzacohetes" },
  SPAWN_FLAME = { kind = "weapon", weapon = 2, label = "Llamas" },
  SPAWN_HEAVY = { kind = "weapon", weapon = 3, label = "Ametralladora" },
  SPAWN_LASER = { kind = "weapon", weapon = 4, label = "Laser" },
  SPAWN_BOMBA = { kind = "bomb", amount = 10, label = "Granadas" },
  LLUVIA_BOMBAS = { kind = "bomb", amount = 50, label = "Lluvia de granadas" },
  LLUVIA_ARMAS = { kind = "ammo", label = "Municion" },
  SPAWN_1UP = { kind = "life", amount = 1, label = "Vida" },
  LLUVIA_VIDAS = { kind = "lives", amount = 5, label = "Lluvia de vidas" },
  CAOS_ENEMIGOS = { kind = "storm", label = "Caos de armas" },
  SPAWN_ESTRELLA = { kind = "inv", label = "Invencible" }
}

local frame = 0
local nameStyle = { size = 16, font = "Segoe UI", style = "regular", color = 0xFFFFFF00, back = 0x00000000 }
local hudNote = ""
local hudUser = ""
local hudUntil = 0
local holdNote = ""
local ramReady = false
local ramName = nil
local busBase = nil
local domainSize = 0
local invUntil = 0
local invOn = { false, false }

local function lower(text)
  return string.lower(tostring(text or ""))
end

local function blocked(name)
  local n = lower(name)
  if n:find("rom", 1, true) then return true end
  if n:find("sprite", 1, true) then return true end
  if n:find("audio", 1, true) or n:find("sound", 1, true) or n:find("z80", 1, true) then return true end
  if n:find("palette", 1, true) or n:find("vram", 1, true) or n:find("ym", 1, true) then return true end
  if n:find("fix", 1, true) or n:find("pcm", 1, true) then return true end
  return false
end

local function hexRange(name)
  local first, last = tostring(name):match("0x(%x+)%-0x(%x+)")
  if not first then return nil, nil end
  return tonumber(first, 16), tonumber(last, 16)
end

local function workRamName(name)
  if blocked(name) then return false end
  local n = lower(name)
  if n:find("system bus", 1, true) then return false end
  if not n:find("ram", 1, true) then return false end
  if n:find("68", 1, true) or n:find("main", 1, true) or n:find("work", 1, true) or n:find("cpu", 1, true) then
    return true
  end
  return false
end

local function eachDomain(list, visit)
  if type(list) ~= "table" then return end
  local seen = {}
  for _, name in pairs(list) do
    local key = tostring(name)
    if not seen[key] then
      seen[key] = true
      visit(name)
    end
  end
end

local function sizeOf(name)
  if not memory or not memory.getmemorydomainsize then return nil end
  local ok, size = pcall(memory.getmemorydomainsize, name)
  if ok and type(size) == "number" and size > 0 then return size end
  return nil
end

local function raw8(addr)
  if addr == nil or addr < 0 or domainSize <= 0 or addr >= domainSize then return nil end
  local function grab(fn, named)
    if not fn then return nil end
    local ok, value
    if named and ramName then
      ok, value = pcall(fn, addr, ramName)
    else
      ok, value = pcall(fn, addr)
    end
    if ok and type(value) == "number" then return math.floor(value) % 256 end
    return nil
  end
  if ramName then
    local value = grab(memory.read_u8, true)
    if value ~= nil then return value end
    value = grab(memory.readbyte, true)
    if value ~= nil then return value end
  end
  local value = grab(memory.read_u8, false)
  if value ~= nil then return value end
  return grab(memory.readbyte, false)
end

local function read8(addr)
  if not ramReady then return nil end
  return raw8(addr)
end

local function read16be(addr)
  if not ramReady or addr == nil or addr < 0 or addr + 1 >= domainSize then return nil end
  local hi = raw8(addr)
  local lo = raw8(addr + 1)
  if hi == nil or lo == nil then return nil end
  return hi * 256 + lo
end

local function s16(value)
  if value == nil then return nil end
  if value >= 32768 then return value - 65536 end
  return value
end

local function pack16(value)
  if value < 0 then value = value + 65536 end
  return math.floor(value) % 65536
end

-- Igual que Metal Slug 1: la X ya es de pantalla. La Y de pantalla es $200 menos la Y guardada.
local function screenOf(worldX, worldY)
  local x = s16(worldX)
  local y = s16(worldY)
  if x == nil or y == nil then return nil, nil end
  return x, s16(pack16(0x200 - y))
end

-- BizHawk solo guarda el byte si el dominio va en la llamada.
-- El system bus de MAME acepta la orden y no escribe nada.
local function write8(addr, value)
  if not ramReady or addr == nil or addr < 0 or addr >= domainSize then return false end
  local byte = math.floor(value) % 256
  local function landed(fn, named)
    if not fn then return false end
    if named and not ramName then return false end
    local ok
    if named then
      ok = pcall(fn, addr, byte, ramName)
    else
      ok = pcall(fn, addr, byte)
    end
    if not ok then return false end
    return raw8(addr) == byte
  end
  if landed(memory.write_u8, true) then return true end
  if landed(memory.writebyte, true) then return true end
  if landed(memory.write_u8, false) then return true end
  if landed(memory.writebyte, false) then return true end
  return false
end

local function dom(cpu)
  if busBase == nil then return nil end
  local addr = cpu - busBase
  if addr < 0 or addr >= domainSize then return nil end
  return addr
end

local function bindDomain()
  ramReady = false
  ramName = nil
  busBase = nil
  domainSize = 0
  if not memory or not memory.usememorydomain or not memory.getmemorydomainlist then return false end
  local ok, list = pcall(memory.getmemorydomainlist)
  if not ok then return false end
  local best = nil
  local plain = nil
  eachDomain(list, function(name)
    local size = sizeOf(name)
    if not size or not workRamName(name) then return end
    local first, last = hexRange(name)
    if first and last and first <= 0x100000 and last >= 0x10C34E and size > (0x10C34E - first) then
      local span = last - first
      if not best or span < best.span then
        best = { name = tostring(name), size = size, base = first, span = span }
      end
    elseif not first and size >= 0xFE00 and size <= 0x20000 then
      if not plain or size > plain.size then
        plain = { name = tostring(name), size = size, base = 0x100000 }
      end
    end
  end)
  local chosen = best or plain
  if not chosen then return false end
  ramName = chosen.name
  busBase = chosen.base
  domainSize = chosen.size
  if not pcall(memory.usememorydomain, ramName) then
    ramName = nil
    busBase = nil
    domainSize = 0
    return false
  end
  if raw8(dom(TIMER_ADDR)) == nil then
    ramName = nil
    busBase = nil
    domainSize = 0
    return false
  end
  ramReady = true
  return true
end

local function ensureDomain()
  if ramReady and raw8(dom(TIMER_ADDR)) ~= nil then return true end
  return bindDomain()
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

local function usable(player, allowZeroLives)
  local lives = read8(dom(player.lives))
  local bombs = read8(dom(player.bombs))
  local flag = read8(dom(player.flag))
  if lives == nil or bombs == nil or flag == nil then return false end
  if lives > LIFE_CAP then return false end
  if not allowZeroLives and lives < 1 then return false end
  if bombs > BOMB_CAP then return false end
  if flag ~= 0 and flag ~= 1 then return false end
  return true
end

local function playable()
  if not ramReady then return false end
  local timer = read8(dom(TIMER_ADDR))
  if timer == nil or timer < 1 or timer > 180 then return false end
  return usable(PLAYERS[1], true)
end

local stick = {}
local noticeUser = ""
local noticeLabel = ""
local noticeUntil = 0
local NOTICE_FRAMES = 180

local function arm(addr, value, frames)
  local kept = {}
  local index = 1
  while index <= #stick do
    if stick[index].addr ~= addr then kept[#kept + 1] = stick[index] end
    index = index + 1
  end
  stick = kept
  stick[#stick + 1] = { addr = addr, value = value, untilFrame = frame + (frames or 30) }
end

local function flushStick()
  local kept = {}
  local index = 1
  while index <= #stick do
    local job = stick[index]
    if frame <= job.untilFrame then
      write8(job.addr, job.value)
      kept[#kept + 1] = job
    end
    index = index + 1
  end
  stick = kept
end

local function grantWeapon(player, code)
  local pack = PACK[code]
  if not pack then return false end
  local flagAddr = dom(player.flag)
  local weaponAddr = dom(player.weapon)
  local ammoAddr = dom(player.ammo)
  if not flagAddr or not weaponAddr or not ammoAddr then return false end
  local flag = read8(flagAddr)
  local weapon = read8(weaponAddr)
  local ammo = read8(ammoAddr)
  if flag == nil or weapon == nil or ammo == nil then return false end
  local nextAmmo = pack.ammo
  if flag == 1 and weapon == code then
    nextAmmo = ammo + pack.add
    if nextAmmo > AMMO_CAP then nextAmmo = AMMO_CAP end
  end
  if not write8(flagAddr, 1) then return false end
  if not write8(weaponAddr, code) then
    write8(flagAddr, flag)
    return false
  end
  if not write8(ammoAddr, nextAmmo) then
    write8(weaponAddr, weapon)
    write8(flagAddr, flag)
    return false
  end
  arm(flagAddr, 1, 180)
  arm(weaponAddr, code, 180)
  arm(ammoAddr, nextAmmo, 180)
  return true
end

local function grantAmmo(player)
  local flagAddr = dom(player.flag)
  local weaponAddr = dom(player.weapon)
  local ammoAddr = dom(player.ammo)
  if not flagAddr or not weaponAddr or not ammoAddr then return false end
  if read8(flagAddr) ~= 1 then return false end
  local weapon = read8(weaponAddr)
  local ammo = read8(ammoAddr)
  local pack = weapon ~= nil and PACK[weapon] or nil
  if not pack or ammo == nil then return false end
  local nextAmmo = ammo + pack.add
  if nextAmmo > AMMO_CAP then nextAmmo = AMMO_CAP end
  if not write8(ammoAddr, nextAmmo) then return false end
  arm(ammoAddr, nextAmmo)
  return true
end

local function grantBombs(player, amount)
  local addr = dom(player.bombs)
  if not addr then return false end
  local current = read8(addr)
  if current == nil or current > BOMB_CAP then return false end
  local nextCount = current + amount
  if nextCount > BOMB_CAP then nextCount = BOMB_CAP end
  if not write8(addr, nextCount) then return false end
  arm(addr, nextCount)
  return true
end

local function grantLives(player, amount)
  local addr = dom(player.lives)
  if not addr then return false end
  local current = read8(addr)
  if current == nil or current > LIFE_CAP then return false end
  local nextCount = current + amount
  if nextCount > LIFE_CAP then nextCount = LIFE_CAP end
  if not write8(addr, nextCount) then return false end
  arm(addr, nextCount)
  return true
end

local function grantInv(player, index)
  local addr = dom(player.inv)
  if not addr then return false end
  if not write8(addr, INV_VALUE) then return false end
  invOn[index] = true
  invUntil = frame + INV_FRAMES
  return true
end

local function applyOne(player, index, effect)
  if effect.kind == "weapon" then return grantWeapon(player, effect.weapon) end
  if effect.kind == "ammo" then return grantAmmo(player) end
  if effect.kind == "bomb" then return grantBombs(player, effect.amount) end
  if effect.kind == "life" then return grantLives(player, effect.amount) end
  if effect.kind == "inv" then return grantInv(player, index) end
  return false
end

-- El regalo entra directo. Unos 3 s al centro: (usuario) activo (powerup).
-- P1 $101494 y P2 $10153C.
-- +$3C es la X de pantalla: el juego la compara con $140.
-- +$40 es la Y viva, entre $100 y $1FF. La Y de pantalla es $200 - $40.
-- +$22 y +$24 no bajan con el jugador y dejan el nombre arriba.
-- Este ROM no tiene el objeto de recogida de Metal Slug 1.
local HERO_HOLD = 8
local P1_OBJ = 0x101494
local P2_OBJ = 0x10153C
local PLAYER_X = 0x3C
local PLAYER_Y = 0x40
local heroSpot = nil
local STORM = {
  { kind = "weapon", weapon = 3, label = "Ametralladora" },
  { kind = "weapon", weapon = 1, label = "Lanzacohetes" },
  { kind = "weapon", weapon = 0, label = "Escopeta" },
  { kind = "weapon", weapon = 2, label = "Llamas" },
  { kind = "bomb", amount = 10, label = "Granadas" },
  { kind = "ammo", label = "Municion" }
}
local function onScreen(x, y)
  if x == nil or y == nil then return false end
  return x >= -40 and x <= 360 and y >= -40 and y <= 260
end

local function objScreen(cpu)
  local rawX = read16be(dom(cpu + PLAYER_X))
  local rawY = read16be(dom(cpu + PLAYER_Y))
  if rawX == nil or rawY == nil then return nil, nil end
  local sx, sy = screenOf(rawX, rawY)
  if onScreen(sx, sy) then return sx, sy end
  sx = s16(rawX)
  sy = s16(rawY)
  if onScreen(sx, sy) then return sx, sy end
  return nil, nil
end

local function playerPoint()
  local x, y = objScreen(P1_OBJ)
  if x then return x, y end
  return objScreen(P2_OBJ)
end

local function heroPoint(allowFresh)
  if allowFresh ~= false then
    local x, y = playerPoint()
    if x then
      heroSpot = { x = x, y = y, left = HERO_HOLD }
      return x, y
    end
  end
  if heroSpot and heroSpot.left > 0 then
    heroSpot.left = heroSpot.left - 1
    return heroSpot.x, heroSpot.y
  end
  return nil, nil
end

local function grantAll(effect)
  local did = false
  local index = 1
  while index <= #PLAYERS do
    local player = PLAYERS[index]
    if usable(player, index == 1) and applyOne(player, index, effect) then did = true end
    index = index + 1
  end
  return did
end

local function apply(effect, user)
  if effect.kind == "storm" then
    local did = false
    local index = 1
    while index <= #STORM do
      if grantAll(STORM[index]) then did = true end
      index = index + 1
    end
    return did
  end
  if effect.kind == "lives" then
    return grantAll({ kind = "life", amount = effect.amount })
  end
  return grantAll(effect)
end

local function showNotice(user, label)
  noticeUser = tostring(user or "")
  noticeLabel = tostring(label or "")
  noticeUntil = frame + NOTICE_FRAMES
end

local function holdInv()
  if frame > invUntil then
    invOn[1] = false
    invOn[2] = false
    return
  end
  local index = 1
  while index <= #PLAYERS do
    if invOn[index] then
      local addr = dom(PLAYERS[index].inv)
      if addr then write8(addr, INV_VALUE) end
    end
    index = index + 1
  end
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

local function poll()
  if not playable() then return end
  local line = readCmd()
  if not line then
    holdNote = ""
    return
  end
  local cmd, user = parse(line)
  local effect = cmd and EFFECTS[cmd] or nil
  if not effect then
    holdNote = ""
    deleteCmd()
    return
  end
  rememberPlate(user)
  if not apply(effect, user) then
    holdNote = "no grabo"
    return
  end
  holdNote = ""
  deleteCmd()
  showNotice(user, effect.label)
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

local function drawTag(sx, sy, text, plate, style, lift, follow)
  if sx == nil or sy == nil then return end
  local minY = follow and -80 or -16
  local maxY = follow and 300 or 240
  if sx < -40 or sx > 360 or sy < minY or sy > maxY then return end
  local tx = math.floor(sx)
  local ty = math.floor(sy - (lift or 24))
  if tx < 24 then tx = 24 end
  if tx > 296 then tx = 296 end
  if ty < 18 then ty = 18 end
  if ty > 176 then ty = 176 end
  local shown = tostring(text or "")
  if not drawPlate(tx, ty, plate) then
    local safe = plainName(shown)
    local color = style and style.color or 0xFFFFFF00
    local back = style and style.back or 0x00000000
    pcall(gui.pixelText, math.max(4, tx - 8), math.max(4, ty - 10), safe ~= "" and safe or "?", color, back)
  end
end

local function drawNotice()
  if frame > noticeUntil or noticeLabel == "" then return end
  local label = "activo " .. plainName(noticeLabel)
  local plate = plateOf[noticeUser]
  pcall(function()
    if plate and plate.path and plate.path ~= "" and gui.drawImage then
      local w = math.floor(plate.w)
      local h = math.floor(plate.h)
      if w > 280 and w > 0 then
        h = math.max(1, math.floor(h * 280 / w))
        w = 280
      end
      local x = 160 - math.floor(w / 2)
      local y = 92 - math.floor(h / 2)
      if y < 36 then y = 36 end
      gui.drawImage(plate.path, x, y, w, h, true, "emucore")
      if gui.drawText then
        gui.drawText(160, y + h + 4, label, 0xFFFFFF00, 0x80000000, 16, "Segoe UI", "bold", "center", "top")
      end
      return
    end
    local who = plainName(noticeUser)
    local line = label
    if who ~= "" then line = who .. " " .. label end
    if gui.drawText then
      gui.drawText(160, 104, line, 0xFFFFFF00, 0x80000000, 16, "Segoe UI", "bold", "center", "middle")
    else
      gui.pixelText(40, 100, line, 0xFFFFFF00, 0x00000000)
    end
  end)
end

local function drawHero(allowFresh)
  if heroName == "" then return end
  local sx, sy = heroPoint(allowFresh)
  if not sx then return end
  drawTag(sx, sy, heroName, heroPlate, heroText, 58, true)
end

local function drawHud()
  local label = ""
  local font = "Segoe UI"
  local fresh = hudNote ~= "" and frame <= hudUntil
  if fresh then
    label = plainName(hudNote)
    font = labelFont()
  elseif not ramReady then
    label = "sin RAM"
  elseif not playable() then
    label = "en menu"
  elseif holdNote ~= "" then
    label = holdNote
  end
  local who = fresh and tostring(hudUser or "") or ""
  pcall(function()
    if gui.drawText then
      gui.drawText(160, 4, "livepulse", 0x99FFFFFF, 0x00000000, 11, "Segoe UI", "regular", "center", "top")
      local nameH = 0
      if who ~= "" then
        nameH = drawPlate(160, 16, plateOf[who], "top") or 0
        if nameH == 0 then
          local safe = plainName(who)
          pcall(gui.pixelText, 120, 16, safe ~= "" and safe or "?", nameStyle.color, nameStyle.back)
          nameH = 8
        end
      end
      if who ~= "" and label ~= "" and nameH > 0 then
        gui.drawText(160, 16 + nameH + 2, label, nameStyle.color, 0x00000000, 12, "Segoe UI", "regular", "center", "top")
      elseif label ~= "" then
        gui.drawText(160, 18, label, nameStyle.color, 0x00000000, 12, font, nameStyle.style, "center", "top")
      end
    else
      gui.pixelText(136, 4, "livepulse", 0x99FFFFFF, 0x00000000)
    end
  end)
end

deleteCmd()
pcall(os.remove, ON_PATH)
loadStyle()
local wasActive = false
local quiet = 0

while true do
  frame = frame + 1
  pcall(function()
    if not ramReady or frame % 30 == 0 then
      ensureDomain()
    end
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
    local showHero = false
    if active then
      quiet = 0
      poll()
      flushStick()
      holdInv()
      showHero = true
    else
      quiet = quiet + 1
      if quiet > 30 then
        heroSpot = nil
        noticeUntil = 0
      end
    end
    drawHero(showHero)
    drawNotice()
    drawHud()
  end)
  emu.frameadvance()
end
