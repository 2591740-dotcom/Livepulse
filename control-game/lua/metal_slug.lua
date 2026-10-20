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
  LLUVIA_BOMBAS = { kind = "bomb", amount = 50, label = "Lluvia de granadas" }
}

local frame = 0
local nameStyle = { size = 16, font = "Segoe UI Emoji", style = "regular", color = 0xFFFFFF00 }
local hudNote = ""
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
  if memory.read_u16_be then
    local ok, value = pcall(memory.read_u16_be, addr)
    if ok and type(value) == "number" then return math.floor(value) % 65536 end
  end
  local hi = raw8(addr)
  local lo = raw8(addr + 1)
  if hi == nil or lo == nil then return nil end
  return hi * 256 + lo
end

local function read32be(addr)
  if not ramReady or addr == nil or addr < 0 or addr + 3 >= domainSize then return nil end
  if memory.read_u32_be then
    local ok, value = pcall(memory.read_u32_be, addr)
    if ok and type(value) == "number" and value >= 0 then return math.floor(value) % 4294967296 end
  end
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

local function alive(player)
  local flag = read8(dom(player.flag))
  if not flag or flag == 0 then return false end
  local code = read32be(dom(player.base))
  if not code then return false end
  if code % 2 ~= 0 then return false end
  if code < 0x20000 or code >= 0x100000 then return false end
  return true
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

local function apply(effect)
  local did = false
  local index = 1
  while index <= #PLAYERS do
    local player = PLAYERS[index]
    if alive(player) and applyOne(player.base, effect) then did = true end
    index = index + 1
  end
  return did
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
  if not anyAlive() or not apply(effect) then
    holdNote = "sin jugador"
    return
  end
  holdNote = ""
  deleteCmd()
  flashHud(user .. " · " .. effect.label)
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

local function loadStyle()
  if io == nil or io.open == nil then return end
  local handle = io.open(STYLE_PATH, "r")
  if not handle then return end
  local line = handle:read("*l")
  handle:close()
  if not line then return end
  local sizeText, font, weight, color = line:match("^(%d+)|([^|\r\n]+)|([^|\r\n]+)|(%x%x%x%x%x%x)$")
  local size = tonumber(sizeText)
  if not size or size < 12 or size > 32 then size = 16 end
  if not STYLE_FONTS[font] then font = "Segoe UI Emoji" end
  if not STYLE_WEIGHTS[weight] then weight = "regular" end
  local rgb = tonumber(color, 16) or 0xFFFF00
  nameStyle.size = size
  nameStyle.font = font
  nameStyle.style = weight
  nameStyle.color = 0xFF000000 + rgb
end

local function labelFont(text)
  if string.find(tostring(text or ""), "[\128-\255]") then return "Segoe UI Emoji" end
  return nameStyle.font
end

local function drawHud()
  local note = ""
  local font = "Segoe UI"
  if hudNote ~= "" and frame <= hudUntil then
    note = hudNote
    font = labelFont(note)
  elseif not ramReady then
    note = "sin RAM"
  elseif not playable() then
    note = "en menu"
  elseif holdNote ~= "" then
    note = holdNote
  end
  pcall(function()
    if gui.drawText then
      gui.drawText(160, 4, "livepulse", 0x99FFFFFF, 0x00000000, 11, "Segoe UI", "regular", "center", "top")
      if note ~= "" then
        gui.drawText(160, 18, note, nameStyle.color, 0x00000000, 12, font, nameStyle.style, "center", "top")
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
  drawHud()
  emu.frameadvance()
end
