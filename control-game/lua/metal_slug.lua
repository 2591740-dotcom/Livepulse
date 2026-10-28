-- Metal Slug (set mslug). SetWeapon esta en $32B58.
-- La misma arma suma la municion de su tabla y se corta en 999.
-- Un arma nueva deja la municion de la tabla. Un pickup real con $98 en $FF dejaria 255.
-- Las granadas suman en +$80 y se cortan en 99, como $32C7E.
-- BizHawk MAME nombra la RAM "cpu : ram : 0x100000-0x10FFFF". El offset 0 de ese dominio es $100000.
-- "System Bus" de ese core no acepta escrituras, asi que no se usa.
-- No se crean soldados ni se escriben vidas. Su arranque no es una escritura segura.

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

local MODE_ADDR = 0x10FDAF
local P1_BASE = 0x100440
local P2_BASE = 0x1004E0
local P1_FLAG = 0x106ECC
local P2_FLAG = 0x106ECD
local AMMO_CAP = 999
local BOMB_CAP = 99

local AMMO = { [0] = 10, [1] = 10, [2] = 15, [3] = 20, [4] = 150 }

local PLAYERS = {
  { base = P1_BASE, flag = P1_FLAG },
  { base = P2_BASE, flag = P2_FLAG }
}

local EFFECTS = {
  SPAWN_HEAVY = { kind = "weapon", weapon = 4, label = "Ametralladora pesada" },
  SPAWN_ROCKET = { kind = "weapon", weapon = 3, label = "Lanzacohetes" },
  SPAWN_SHOTGUN = { kind = "weapon", weapon = 1, label = "Escopeta" },
  SPAWN_FLAME = { kind = "weapon", weapon = 2, label = "Llamas" },
  SPAWN_BOMBA = { kind = "bomb", amount = 10, label = "Granadas" },
  LLUVIA_ARMAS = { kind = "ammo", times = 5, label = "Lluvia de municion" },
  LLUVIA_BOMBAS = { kind = "bomb", amount = 50, label = "Lluvia de granadas" },
  CAOS_ENEMIGOS = { kind = "storm", label = "Caos de armas" },
  LLUVIA_VIDAS = { kind = "lives", amount = 5, label = "Lluvia de vidas" }
}

local frame = 0
local nameStyle = { size = 16, font = "Segoe UI", style = "regular", color = 0xFFFFFF00, back = 0x00000000 }
local hudNote = ""
local hudUser = ""
local hudUntil = 0
local holdNote = ""
local ramReady = false
local busBase = nil
local domainSize = 0

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
  if memory.read_u8 then
    local ok, value = pcall(memory.read_u8, addr)
    if ok and type(value) == "number" then return math.floor(value) % 256 end
  end
  if memory.readbyte then
    local ok, value = pcall(memory.readbyte, addr)
    if ok and type(value) == "number" then return math.floor(value) % 256 end
  end
  return nil
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

local function read32be(addr)
  if not ramReady or addr == nil or addr < 0 or addr + 3 >= domainSize then return nil end
  local hi = read16be(addr)
  local lo = read16be(addr + 2)
  if hi == nil or lo == nil then return nil end
  return hi * 65536 + lo
end

local function write8(addr, value)
  if not ramReady or addr == nil or addr < 0 or addr >= domainSize then return false end
  local byte = math.floor(value) % 256
  if memory.write_u8 then
    local ok = pcall(memory.write_u8, addr, byte)
    if ok then return true end
  end
  if memory.writebyte then
    local ok = pcall(memory.writebyte, addr, byte)
    if ok then return true end
  end
  return false
end

local function write16be(addr, value)
  if not ramReady or addr == nil or addr < 0 or addr + 1 >= domainSize then return false end
  local word = math.floor(value) % 65536
  if memory.write_u16_be then
    local ok = pcall(memory.write_u16_be, addr, word)
    if ok then return true end
  end
  if not write8(addr, math.floor(word / 256)) then return false end
  return write8(addr + 1, word % 256)
end

local function write32be(addr, value)
  if not ramReady or addr == nil or addr < 0 or addr + 3 >= domainSize then return false end
  local word = math.floor(value) % 4294967296
  local hi = math.floor(word / 65536)
  local lo = word % 65536
  if not write16be(addr, hi) then return false end
  return write16be(addr + 2, lo)
end

local function dom(cpu)
  if busBase == nil then return nil end
  local addr = cpu - busBase
  if addr < 0 or addr >= domainSize then return nil end
  return addr
end

local function bindDomain()
  ramReady = false
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
    if first and last and first <= 0x100000 and last >= 0x10FDAF and size > (0x10FDAF - first) then
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
  if not pcall(memory.usememorydomain, chosen.name) then return false end
  busBase = chosen.base
  domainSize = chosen.size
  if raw8(dom(MODE_ADDR)) == nil then
    busBase = nil
    domainSize = 0
    return false
  end
  ramReady = true
  return true
end

local function ensureDomain()
  if ramReady and raw8(dom(MODE_ADDR)) ~= nil then return true end
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

local function playable()
  if not ramReady then return false end
  return read8(dom(MODE_ADDR)) == 2
end

-- $400 es rts. El hueco conserva ese puntero en el menu.
-- La mision lo cambia: el nacimiento de Marco esta en $3364A y deja Y en $1D8.
local function codeLive(player)
  local code = read32be(dom(player.base))
  if not code or code % 2 ~= 0 then return false end
  if code <= 0x400 or code >= 0x100000 then return false end
  return true
end

local function alive(player)
  return codeLive(player)
end

local function anyAlive()
  return alive(PLAYERS[1]) or alive(PLAYERS[2])
end

local function withBit4(value)
  local byte = math.floor(value) % 256
  return (math.floor(byte / 32) * 32) + 16 + (byte % 16)
end

local function tableAmmo(weapon)
  local amount = AMMO[weapon]
  if not amount then return 10 end
  return amount
end

local function flashGun(base)
  local timer = dom(base + 0x87)
  local bitsAddr = dom(base + 0x8C)
  if timer then write8(timer, 5) end
  if bitsAddr then
    local bits = read8(bitsAddr) or 0
    write8(bitsAddr, withBit4(bits))
  end
end

local function grantWeapon(base, weapon)
  local weaponAddr = dom(base + 0x71)
  local ammoAddr = dom(base + 0x82)
  if not weaponAddr or not ammoAddr then return false end
  local current = read8(weaponAddr)
  local ammo = read16be(ammoAddr)
  if current == nil or ammo == nil then return false end
  local nextAmmo = tableAmmo(weapon)
  if current == weapon then nextAmmo = ammo + nextAmmo end
  if nextAmmo > AMMO_CAP then nextAmmo = AMMO_CAP end
  if not write8(weaponAddr, weapon) then return false end
  if not write16be(ammoAddr, nextAmmo) then
    write8(weaponAddr, current)
    return false
  end
  flashGun(base)
  return true
end

local function grantAmmo(base, times)
  local weaponAddr = dom(base + 0x71)
  local ammoAddr = dom(base + 0x82)
  if not weaponAddr or not ammoAddr then return false end
  local weapon = read8(weaponAddr)
  local ammo = read16be(ammoAddr)
  if weapon == nil or ammo == nil then return false end
  local nextAmmo = ammo + (tableAmmo(weapon) * times)
  if nextAmmo > AMMO_CAP then nextAmmo = AMMO_CAP end
  if not write16be(ammoAddr, nextAmmo) then return false end
  flashGun(base)
  return true
end

local function grantBombs(base, amount)
  local addr = dom(base + 0x80)
  if not addr then return false end
  local current = read8(addr)
  if current == nil then return false end
  local nextCount = current + amount
  if nextCount > BOMB_CAP then nextCount = BOMB_CAP end
  return write8(addr, nextCount)
end

local function applyOne(base, effect)
  if effect.kind == "weapon" then return grantWeapon(base, effect.weapon) end
  if effect.kind == "ammo" then return grantAmmo(base, effect.times) end
  if effect.kind == "bomb" then return grantBombs(base, effect.amount) end
  return false
end

-- El regalo es el pickup real. $4AE lo saca de $106E80 y lo cuelga de $100800.
-- Arma: $9A918 pesada, $9A9D4 escopeta, $9AA32 llamas, $9A976 cohete.
-- Granadas: $9AC52 suma el byte $98 en +$80. Municion: $9ABC2.
local FREE_HEAD = 0x106E80
local ITEM_PARENT = 0x100800
local POOL_BASE = 0x100A80
local POOL_END = 0x106E80
local WEAPON_CODE = {
  [1] = 0x9A9D4,
  [2] = 0x9AA32,
  [3] = 0x9A976,
  [4] = 0x9A918
}
local GRENADE_CODE = 0x9AC52
local AMMO_CODE = 0x9ABC2
local gifts = {}

local function poolObj(addr)
  if not addr or addr < POOL_BASE or addr >= POOL_END then return false end
  return (addr - POOL_BASE) % 0xA0 == 0
end

local function finishObj(obj)
  local function w8(off, value) return write8(dom(obj + off), value) end
  local function w16(off, value) return write16be(dom(obj + off), value) end
  if not w16(0x14, 0) then return false end
  if not w16(0x16, 0xFFFF) then return false end
  if not w16(0x18, 0xFFFF) then return false end
  if not w16(0x1A, 0xFFFF) then return false end
  if not w16(0x1C, 0xFFFF) then return false end
  if not w16(0x1E, 0) then return false end
  if not w8(0x12, 0) then return false end
  if not w16(0x38, 0) then return false end
  if not w8(0x13, 0) then return false end
  if not w8(0x5A, 0) then return false end
  if not w8(0x69, 0) then return false end
  if not w8(0x5B, 0) then return false end
  if not w8(0x6B, 0) then return false end
  if not w8(0x32, 0xFF) then return false end
  if not w8(0x33, 0xFF) then return false end
  if not w8(0x3A, 0) then return false end
  if not w16(0x28, 0) then return false end
  if not w16(0x2A, 0) then return false end
  if not w16(0x2C, 0) then return false end
  if not w16(0x2E, 0) then return false end
  if not w16(0x26, 0) then return false end
  if not w8(0x59, 0) then return false end
  if not w8(0x45, 0) then return false end
  if not w8(0x44, 0) then return false end
  if not w8(0x6A, 0) then return false end
  local flags = read8(dom(obj + 0x13)) or 0
  if not w8(0x13, (flags + 64) % 256) then return false end
  return true
end

-- $4AE lo inserta justo despues de $100800, que es el padre de los regalos del juego.
local function allocItem(code, parent)
  local headAddr = dom(FREE_HEAD)
  local head = read32be(headAddr)
  if not poolObj(head) or parent == nil then return nil end
  local nxt = read32be(dom(head + 8)) or 0xFFFFFFFF
  if not write32be(headAddr, nxt) then return nil end
  local off = 0x9C
  while off >= 0x10 do
    if not write32be(dom(head + off), 0xFFFFFFFF) then return nil end
    off = off - 4
  end
  if not finishObj(head) then return nil end
  local child = read32be(dom(parent + 8)) or 0xFFFFFFFF
  local depth = ((read8(dom(parent + 0x10)) or 0) + 1) % 256
  if not write32be(dom(head), code) then return nil end
  if not write32be(dom(head + 0x0C), parent) then return nil end
  if not write8(dom(head + 0x10), depth) then return nil end
  if not write32be(dom(head + 4), parent) then return nil end
  if not write32be(dom(head + 8), child) then return nil end
  if not write32be(dom(parent + 8), head) then return nil end
  if child >= 0x100000 and child < 0x110000 then
    write32be(dom(child + 4), head)
  end
  finishObj(head)
  if read32be(dom(parent + 8)) ~= head then return nil end
  if read32be(dom(head)) ~= code then return nil end
  return head
end

-- El juego ya deja $22/$24 en espacio de pantalla. Restar $106F50 los saca del cuadro.
-- Pantalla Y = $200 - $24. El recorte del propio juego exige Y entre $E0 y $230.
local function s16(value)
  if value == nil then return nil end
  if value >= 32768 then return value - 65536 end
  return value
end

local function pack16(value)
  if value < 0 then value = value + 65536 end
  return math.floor(value) % 65536
end

local function screenOf(worldX, worldY)
  local x = s16(worldX)
  local y = s16(worldY)
  if x == nil or y == nil then return nil, nil end
  return x, s16(pack16(0x200 - y))
end

local function worldOf(screenX, screenY)
  return pack16(screenX), pack16(0x200 - screenY)
end

-- Arriba, dentro del cuadro donde el juego no borra el objeto.
local function placeAt(obj, screenX)
  local wx, wy = worldOf(screenX, 18)
  write16be(dom(obj + 0x22), wx)
  write16be(dom(obj + 0x24), wy)
  write16be(dom(obj + 0x2A), 0xFE00)
  write16be(dom(obj + 0x2E), 0xFFC0)
end

local function rememberGift(obj, user)
  gifts[#gifts + 1] = { obj = obj, user = user }
  if #gifts > 16 then table.remove(gifts, 1) end
end

local function firstAlive()
  if alive(PLAYERS[1]) then return PLAYERS[1] end
  if alive(PLAYERS[2]) then return PLAYERS[2] end
  return nil
end

local function spawnAt(effect, user, player, screenX)
  local code = nil
  local extra = nil
  local extraHi = nil
  if effect.kind == "weapon" then
    code = WEAPON_CODE[effect.weapon]
    extra = 0
  elseif effect.kind == "bomb" then
    code = GRENADE_CODE
    extra = effect.amount
  elseif effect.kind == "ammo" then
    code = AMMO_CODE
    local weapon = read8(dom(player.base + 0x71)) or 0
    extra = tableAmmo(weapon) * effect.times
    if extra > 255 then extra = 255 end
    extraHi = extra
  end
  if not code then return false end
  local obj = allocItem(code, ITEM_PARENT)
  if not obj then return false end
  placeAt(obj, screenX)
  if extra ~= nil then write8(dom(obj + 0x98), extra) end
  if extraHi ~= nil then write8(dom(obj + 0x99), extraHi) end
  rememberGift(obj, user)
  return true
end

local function spawnGift(effect, user)
  local player = firstAlive()
  if not player then return false end
  local x = read16be(dom(player.base + 0x22))
  local sx = s16(x) or 0
  local dropX = 230
  if sx >= 160 then dropX = 16 end
  return spawnAt(effect, user, player, dropX)
end

-- Seis pickups reales, repartidos. No hay spawner de soldados verificable.
local STORM = {
  { kind = "weapon", weapon = 4 },
  { kind = "weapon", weapon = 3 },
  { kind = "weapon", weapon = 1 },
  { kind = "weapon", weapon = 2 },
  { kind = "bomb", amount = 10 },
  { kind = "ammo", times = 1 }
}
local STORM_X = { 28, 68, 108, 148, 188, 228 }

local function spawnStorm(user)
  local player = firstAlive()
  if not player then return false end
  local n = 0
  for i = 1, #STORM do
    if spawnAt(STORM[i], user, player, STORM_X[i]) then n = n + 1 end
  end
  return n > 0
end

-- El contador vive en el objeto $100300 / $1003A0, byte +$77.
-- Al morir, $2598A hace subi.b #1, $77(a6) y en cero pasa a continue.
local LIFE_MGR = { 0x100300, 0x1003A0 }
local LIFE_CAP = 9
local LIFE_X = { 28, 78, 128, 178, 228 }

local function managerLive(base)
  local code = read32be(dom(base))
  if code == nil or code % 2 ~= 0 then return false end
  return code > 0x400 and code < 0x100000
end

local function addLives(amount)
  local ok = false
  for i = 1, 2 do
    local base = LIFE_MGR[i]
    if alive(PLAYERS[i]) and managerLive(base) then
      local cur = read8(dom(base + 0x77)) or 0
      local nxt = cur + amount
      if nxt > LIFE_CAP then nxt = LIFE_CAP end
      if write8(dom(base + 0x77), nxt) and read8(dom(base + 0x77)) == nxt then
        ok = true
      end
    end
  end
  return ok
end

-- No hay un objeto 1UP. El contador sube y caen granadas de 1 para llevar el nombre.
local function spawnLifeRain(user, amount)
  if not addLives(amount) then return false end
  local player = firstAlive()
  if not player then return true end
  for i = 1, #LIFE_X do
    spawnAt({ kind = "bomb", amount = 1 }, user, player, LIFE_X[i])
  end
  return true
end

local function apply(effect, user)
  if effect.kind == "storm" then return spawnStorm(user) end
  if effect.kind == "lives" then return spawnLifeRain(user, effect.amount) end
  return spawnGift(effect, user)
end

local function flashHud(text)
  hudNote = tostring(text or "")
  hudUntil = frame + 120
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
  if not anyAlive() then
    holdNote = "sin jugador"
    return
  end
  if not apply(effect, user) then
    holdNote = "sin espacio"
    return
  end
  holdNote = ""
  hudUser = user
  deleteCmd()
  flashHud(effect.label)
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

-- BizHawk 2.11 se cuelga dentro de drawText con Segoe UI Emoji o con un emoji.
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

local function drawGifts()
  local index = 1
  while index <= #gifts do
    local gift = gifts[index]
    local code = read32be(dom(gift.obj))
    if not code or code < 0x9A000 or code >= 0x9C000 then
      table.remove(gifts, index)
    else
      local x = read16be(dom(gift.obj + 0x22))
      local y = read16be(dom(gift.obj + 0x24))
      local sx, sy = screenOf(x, y)
      drawTag(sx, sy, gift.user, plateOf[gift.user], nameStyle, 22, true)
      index = index + 1
    end
  end
end

-- La Y de Marco nace en $1D8. Hay que restar la camara antes de pintar.
local function drawHero()
  if heroName == "" or not playable() then return end
  local player = nil
  if alive(PLAYERS[1]) then
    player = PLAYERS[1]
  elseif alive(PLAYERS[2]) then
    player = PLAYERS[2]
  end
  if not player then return end
  local x = read16be(dom(player.base + 0x22))
  local y = read16be(dom(player.base + 0x24))
  local sx, sy = screenOf(x, y)
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
pcall(os.remove, "C:\\LivePulse\\livepulse_place.txt")
loadStyle()
local wasActive = false

while true do
  frame = frame + 1
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
  if active then
    poll()
  end
  if active then pcall(drawGifts) end
  pcall(drawHero)
  drawHud()
  emu.frameadvance()
end
