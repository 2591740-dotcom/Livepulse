-- Super Mario Bros. (NES) USA — LivePulse
-- Direcciones del desensamblado de doppelganger (SMBDIS).
-- El archivo de Downloads escribía el tipo sin encender Enemy_Flag,
-- y estos identificadores no son los del juego:
--   0x2F es la enredadera, no la flor
--   0x30 es la bandera del poste, no la estrella
--   0x2D es Bowser, no el 1-Up
--   0x0B es el pez rojo, no Lakitu
--   0x09 no es un Para-Koopa
-- El power-up real vive en el hueco 5. Los enemigos usan los huecos 0 a 4.
-- El juego solo anima un power-up. Una lluvia guarda la cola y suelta
-- el siguiente en ese mismo hueco cuando el anterior ya no está, con
-- 32 frames de espera. No hay sprites de adorno.
-- El hongo, el 1-Up y la estrella caen con la física del juego.
-- La flor no tiene esa física: este script la baja hasta el bloque de abajo.
-- Los enemigos salen repartidos dentro de la pantalla, lejos del borde.

local CMD_PATH = "C:\\LivePulse\\livepulse_cmd.txt"
local ON_PATH = "C:\\LivePulse\\livepulse_on.txt"
local STYLE_PATH = "C:\\LivePulse\\livepulse_style.txt"

local EFFECTS = {
  SPAWN_HONGO = { kind = "power", ptype = 0, name = "Hongo" },
  SPAWN_FLOR = { kind = "power", ptype = 1, name = "Flor" },
  SPAWN_ESTRELLA = { kind = "power", ptype = 2, name = "Estrella" },
  SPAWN_1UP = { kind = "power", ptype = 3, name = "1-Up" },
  SPAWN_MONEDA = { kind = "coin", name = "Moneda" },
  SPAWN_GOOMBA = { kind = "enemy", id = 0x06, box = 0x09, name = "Goomba" },
  SPAWN_KOOPA = { kind = "enemy", id = 0x00, box = 0x03, name = "Koopa" },
  SPAWN_PARAKOOPA = { kind = "enemy", id = 0x10, box = 0x03, fly = true, name = "Para-Koopa" },
  SPAWN_BALA = { kind = "enemy", id = 0x08, box = 0x09, bill = true, name = "Bala" },
  SPAWN_SPINY = { kind = "enemy", id = 0x12, box = 0x09, name = "Spiny" },
  SPAWN_LAKITU = { kind = "enemy", id = 0x11, box = 0x03, lakitu = true, name = "Lakitu" },
  SPAWN_HAMMERBRO = { kind = "enemy", id = 0x05, box = 0x0B, hammer = true, name = "Hammer Bro" },
  SPAWN_PIRANHA = { kind = "enemy", id = 0x0D, box = 0x09, plant = true, name = "Piraña" },
  -- El NES solo tiene 5 huecos de enemigo. Un comando llena esos huecos.
  CAOS_GOOMBAS = { kind = "wave", name = "Caos Goombas", list = { "SPAWN_GOOMBA", "SPAWN_GOOMBA", "SPAWN_GOOMBA", "SPAWN_GOOMBA", "SPAWN_GOOMBA" } },
  CAOS_KOOPAS = { kind = "wave", name = "Caos Koopas", list = { "SPAWN_KOOPA", "SPAWN_KOOPA", "SPAWN_KOOPA", "SPAWN_KOOPA", "SPAWN_KOOPA" } },
  LLUVIA_ENEMIGOS = { kind = "wave", name = "Lluvia de enemigos", list = { "SPAWN_GOOMBA", "SPAWN_KOOPA", "SPAWN_PARAKOOPA", "SPAWN_SPINY", "SPAWN_BALA" } },
  LLUVIA_VIDAS = { kind = "rain", ptype = 3, count = 5, name = "Lluvia de vidas" },
  LLUVIA_HONGOS = { kind = "rain", ptype = 0, count = 5, name = "Lluvia de hongos" }
}

local slotOwners = {}
local coinTag = nil
local powerQueue = {}
local nextPowerAt = 0
local POWER_GAP = 32
local POWER_CAP = 12
local FLOWER = { on = false, vy = 0, landed = false, page = 0, x = 0, y = 0, yHigh = 1 }
local RAIN_GAP = { 16, 34, -6, 46, -22 }
local frame = 0
local nameStyle = { size = 16, font = "Segoe UI Emoji", style = "regular", color = 0xFFFFFF00 }
local hudNote = ""
local hudUntil = 0
local ramReady = false

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

local function nesGame()
  return read8(0x07FF) == 0xA5
end

-- Jugable: modo juego, motor en marcha, Mario controlable, sin pausa ni tubo.
local function playable()
  if not nesGame() then return false end
  if read8(0x0770) ~= 1 then return false end
  if read8(0x0772) ~= 3 then return false end
  if read8(0x000E) ~= 8 then return false end
  if (read8(0x0776) or 1) % 2 == 1 then return false end
  if (read8(0x0747) or 1) ~= 0 then return false end
  if (read8(0x0774) or 1) ~= 0 then return false end
  return true
end

-- La pausa detiene el nivel, pero la cola del power-up sigue en pie.
local function pausedOnly()
  if not nesGame() then return false end
  if read8(0x0770) ~= 1 then return false end
  if read8(0x0772) ~= 3 then return false end
  if read8(0x000E) ~= 8 then return false end
  return (read8(0x0776) or 0) % 2 == 1
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

local function worldAt(screenPixel)
  local page = read8(0x071A) or 0
  local left = read8(0x071C) or 0
  local pixel = math.floor(screenPixel)
  if pixel < 8 then pixel = 8 end
  if pixel > 240 then pixel = 240 end
  local sum = left + pixel
  while sum >= 256 do
    sum = sum - 256
    page = (page + 1) % 256
  end
  return page, sum
end

-- Lejos del borde: ahí el juego borra al enemigo. La bala nace a la derecha y vuela a la izquierda.
local SAFE_X = { [0] = 64, 96, 128, 160, 192 }

local function place(effect, slot)
  if effect.bill then return 192 end
  return SAFE_X[slot or 0] or 128
end

-- 36 px al lado de Mario, del lado hacia el que el juego lo va a soltar.
local function besideMario()
  local rel = read8(0x03AD) or 96
  local pixel = rel + 36
  if pixel > 200 or pixel < 48 then pixel = rel - 36 end
  if pixel < 48 then pixel = 48 end
  if pixel > 200 then pixel = 200 end
  return pixel
end

local function faceMario(goLeft)
  if goLeft then return 1, 0x08 end
  return 2, 0xF8
end

local function alive(slot, owner)
  if not owner then return false end
  local flag = read8(0x000F + slot)
  local id = read8(0x0016 + slot)
  if flag == nil or flag == 0 or id ~= owner.id then return false end
  if owner.ptype ~= nil and read8(0x0039) ~= owner.ptype then return false end
  return true
end

local function freeEnemy()
  for slot = 0, 4 do
    if (read8(0x000F + slot) or 1) == 0 then return slot end
  end
  return nil
end

local function makeRoom()
  local slot = freeEnemy()
  if slot ~= nil then return slot end
  local oldest, born = nil, nil
  for i = 0, 4 do
    local owner = slotOwners[i]
    if owner and alive(i, owner) then
      if born == nil or (owner.born or 0) < born then
        oldest = i
        born = owner.born or 0
      end
    elseif owner then
      slotOwners[i] = nil
    end
  end
  if oldest == nil then return nil end
  write8(0x000F + oldest, 0)
  slotOwners[oldest] = nil
  return oldest
end

local function writeEnemy(slot, effect, page, x, y, yHigh)
  write8(0x000F + slot, 0)
  write8(0x0016 + slot, effect.id)
  write8(0x001E + slot, 0)
  write8(0x006E + slot, page)
  write8(0x0087 + slot, x)
  write8(0x00B6 + slot, yHigh)
  write8(0x00CF + slot, y)
  write8(0x049A + slot, effect.box)
  write8(0x03C5 + slot, 0)
  write8(0x00A0 + slot, 0)
  write8(0x0434 + slot, 0)
  local dir, speed = 2, 0xF8
  if effect.bill then
    dir, speed = 2, 0xE8
  elseif effect.fly or effect.lakitu then
    dir, speed = 1, 0
  elseif effect.plant then
    dir, speed = 0, 1
    local down = y
    local up = y - 0x18
    if up < 0x20 then up = 0x20 end
    write8(0x0434 + slot, down)
    write8(0x0417 + slot, up)
    write8(0x078A + slot, 0)
  elseif effect.hammer then
    dir, speed = 2, 0
    write8(0x003C + slot, 0x30)
    write8(0x03A2 + slot, 0x40)
  else
    local goLeft = x < (read8(0x0086) or 0)
    local pageMario = read8(0x006D) or 0
    if page ~= pageMario then goLeft = page < pageMario end
    dir, speed = faceMario(goLeft)
  end
  write8(0x0046 + slot, dir)
  write8(0x0058 + slot, speed)
  write8(0x000F + slot, 1)
  return true
end

local function spawnEnemy(effect, user)
  local slot = makeRoom()
  if slot == nil then return false, "Pantalla llena" end
  local page, x = worldAt(place(effect, slot))
  local y = read8(0x00CE) or 0xB0
  local yHigh = read8(0x00B5) or 1
  if effect.lakitu then y = 0x30 end
  if effect.fly and y > 0x40 then y = y - 0x18 end
  if y < 0x20 then y = 0x20 end
  writeEnemy(slot, effect, page, x, y, yHigh)
  write8(0x000F + slot, 1)
  slotOwners[slot] = { name = user, id = effect.id, born = frame }
  return true
end

local function clearPowerSlot()
  local slot = 5
  write8(0x000F + slot, 0)
  write8(0x0016 + slot, 0)
  write8(0x001E + slot, 0)
  write8(0x0046 + slot, 0)
  write8(0x0058 + slot, 0)
  write8(0x00A0 + slot, 0)
  write8(0x0401 + slot, 0)
  write8(0x0434 + slot, 0)
  write8(0x03C5 + slot, 0)
  write8(0x0110 + slot, 0)
  write8(0x078A + slot, 0)
  write8(0x0796 + slot, 0)
  slotOwners[slot] = nil
end

-- Al lado de Mario, en coordenadas del nivel, un poco arriba para que caiga.
-- Si el margen lo sacaría de la pantalla, se invierte hacia el otro lado.
local function nearMario(spread)
  local page = read8(0x006D) or 0
  local x = read8(0x0086) or 64
  local rel = read8(0x03AD) or 96
  local delta = spread or 24
  if rel + delta > 216 then delta = -math.abs(delta) end
  if rel + delta < 24 then delta = math.abs(delta) end
  x = x + delta
  local yHigh = read8(0x00B5) or 1
  local y = (read8(0x00CE) or 0xB0) - 48
  while x >= 256 do
    x = x - 256
    page = (page + 1) % 256
  end
  while x < 0 do
    x = x + 256
    page = page - 1
    if page < 0 then page = 255 end
  end
  if y < 0 then
    y = y + 256
    yHigh = yHigh - 1
  end
  if yHigh < 1 or y < 0x28 then
    yHigh = 1
    if y < 0x28 then y = 0x28 end
  end
  return page, x, yHigh, y
end

local NONSOLID = {
  [0x00] = true, [0x23] = true, [0x26] = true,
  [0x5F] = true, [0x60] = true, [0xC2] = true, [0xC3] = true
}

local function feetSolid(page, x, y)
  local fx = x + 8
  local fp = page
  if fx >= 256 then
    fx = fx - 256
    fp = (fp + 1) % 256
  end
  local fy = y + 24
  if fy < 0x20 or fy >= 256 then return false end
  local row = fy - 0x20
  row = row - (row % 16)
  if row < 0 or row > 0xC0 then return false end
  local base = (fp % 2 == 0) and 0x0500 or 0x05D0
  local tile = read8(base + math.floor(fx / 16) + row) or 0
  return not NONSOLID[tile]
end

local function stepBody(body)
  if body.landed then
    if not feetSolid(body.page, body.x, body.y + 2) then
      body.landed = false
      body.vy = 1
    elseif body.walk then
      body.x = body.x + 1
      if body.x >= 256 then
        body.x = 0
        body.page = (body.page + 1) % 256
      end
    end
    if body.landed then return end
  end
  body.vy = (body.vy or 0) + 1
  if body.vy > 3 then body.vy = 3 end
  local y = body.y + body.vy
  local yHigh = body.yHigh or 1
  if y >= 256 then
    y = y - 256
    yHigh = yHigh + 1
  end
  if feetSolid(body.page, body.x, y) then
    local guard = 0
    while feetSolid(body.page, body.x, y) and guard < 20 do
      y = y - 1
      guard = guard + 1
    end
    body.vy = 0
    body.landed = true
  end
  body.y = y
  body.yHigh = yHigh
end

local function spawnPower(effect, user, spread)
  local slot = 5
  local page, x, yHigh, y = nearMario(spread)
  clearPowerSlot()
  local ptype = effect.ptype
  write8(0x0039, ptype)
  write8(0x0016 + slot, 0x2E)
  -- $80: ya salió, el juego lo dibuja y no lo hace subir.
  -- $C0: además el juego lo deja caer (hongo y 1-Up). La flor cae desde aquí.
  local state = 0xC0
  if ptype == 1 or ptype == 2 then state = 0x80 end
  write8(0x001E + slot, state)
  write8(0x006E + slot, page)
  write8(0x0087 + slot, x)
  write8(0x00B6 + slot, yHigh)
  write8(0x00CF + slot, y)
  write8(0x049A + slot, 0x03)
  write8(0x03C5 + slot, 0x00)
  write8(0x0046 + slot, 1)
  local xSpeed = 0x10
  if ptype == 1 then xSpeed = 0 end
  write8(0x0058 + slot, xSpeed)
  write8(0x00A0 + slot, 0)
  write8(0x0406, 0)
  write8(0x0439, 0)
  write8(0x06EA, 0xA8)
  write8(0x000F + slot, 1)
  write8(0x00FE, 0x02)
  slotOwners[slot] = {
    name = user,
    id = 0x2E,
    ptype = ptype,
    born = frame
  }
  FLOWER.on = ptype == 1
  FLOWER.vy = 0
  FLOWER.landed = false
  FLOWER.page = page
  FLOWER.x = x
  FLOWER.y = y
  FLOWER.yHigh = yHigh
  FLOWER.walk = false
  return true
end

local function enqueuePower(effect, user, count)
  local total = count or 1
  for index = 1, total do
    if #powerQueue >= POWER_CAP then return end
    local spread = 32
    if total > 1 then
      spread = RAIN_GAP[((index - 1) % #RAIN_GAP) + 1]
    end
    powerQueue[#powerQueue + 1] = {
      ptype = effect.ptype,
      user = user,
      spread = spread
    }
  end
end

local function powerBusy()
  local flag = read8(0x000F + 5) or 0
  local id = read8(0x0016 + 5) or 0
  return flag ~= 0 and id == 0x2E
end

local function pumpPower()
  local owner = slotOwners[5]
  if owner and not alive(5, owner) then
    slotOwners[5] = nil
    if owner.ptype == 1 then FLOWER.on = false end
  end
  if #powerQueue == 0 then return end
  if frame < nextPowerAt then return end
  if powerBusy() then return end
  local job = table.remove(powerQueue, 1)
  spawnPower({ ptype = job.ptype }, job.user, job.spread)
  nextPowerAt = frame + POWER_GAP
end

-- GiveOneCoin suma 2 en DigitModifier+4. El bucle empieza en $07E2 y baja:
-- ese 2 cae en las centenas, los mismos 200 del "200" que flota.
local function addScore200()
  local addr = 0x07E2
  local extra = { [0] = 0, 0, 0, 0, 2, 0 }
  local carry = 0
  for i = 5, 0, -1 do
    local digit = read8(addr) or 0
    if digit > 9 then digit = 0 end
    local sum = digit + extra[i] + carry
    carry = 0
    if sum >= 10 then
      sum = sum - 10
      carry = 1
    end
    write8(addr, sum)
    addr = addr - 1
  end
end

local function pushDigits(off, lo, digits)
  local n = #digits
  write8(0x0301 + off, 0x20)
  write8(0x0302 + off, lo)
  write8(0x0303 + off, n)
  for i = 1, n do
    write8(0x0303 + off + i, digits[i])
  end
  return off + n + 3
end

local function addCoin()
  local tally = read8(0x075E) or 0
  tally = tally + 1
  if tally >= 100 then
    tally = 0
    local lives = read8(0x075A) or 0
    if lives < 18 then
      write8(0x075A, lives + 1)
      write8(0x00FE, 0x40)
    else
      write8(0x00FE, 0x01)
    end
  else
    write8(0x00FE, 0x01)
  end
  write8(0x075E, tally)
  local hidden = read8(0x0748) or 0
  if hidden < 255 then write8(0x0748, hidden + 1) end
  local tens = math.floor(tally / 10)
  local ones = tally % 10
  write8(0x07ED, tens)
  write8(0x07EE, ones)
  addScore200()
  local off = read8(0x0300) or 0
  if off <= 32 then
    off = pushDigits(off, 0x6D, { tens, ones })
    local score = {}
    for i = 0, 5 do
      score[i + 1] = read8(0x07DD + i) or 0
    end
    if score[1] == 0 then score[1] = 0x24 end
    off = pushDigits(off, 0x62, score)
    write8(0x0301 + off, 0x00)
    write8(0x0300, off)
  end
end

local function spawnCoin(user)
  local slot = 8
  for s = 8, 6, -1 do
    if (read8(0x002A + s) or 1) == 0 then
      slot = s
      break
    end
  end
  local page, x = worldAt(besideMario())
  local y = (read8(0x00CE) or 0xA0) - 0x20
  if y < 0x28 then y = 0x28 end
  local oam = read8(0x06F3 + slot) or 0
  if oam < 0x28 then
    local safe = 0xC0
    if slot == 7 then safe = 0xC8
    elseif slot == 8 then safe = 0xD0 end
    write8(0x06F3 + slot, safe)
  end
  write8(0x007A + slot, page)
  write8(0x0093 + slot, x)
  write8(0x00DB + slot, y)
  write8(0x00AC + slot, 0xFB)
  write8(0x00C2 + slot, 1)
  write8(0x002A + slot, 1)
  addCoin()
  coinTag = { name = user, slot = slot, untilFrame = frame + 90 }
  return true
end

local function spawn(effect, user)
  if effect.kind == "coin" then return spawnCoin(user) end
  if effect.kind ~= "enemy" then return false end
  return spawnEnemy(effect, user)
end

local function flash(text)
  hudNote = tostring(text or "")
  hudUntil = frame + 120
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
  if not playable() then
    return
  end
  if effect.kind == "wave" then
    local made = 0
    local list = effect.list or {}
    for i = 1, #list do
      local one = EFFECTS[list[i]]
      if one and spawnEnemy(one, user) then made = made + 1 end
    end
    if made < 1 then return end
    deleteCmd()
    flash(effect.name .. " ×" .. made)
    return
  end
  if effect.kind == "power" or effect.kind == "rain" then
    local count = 1
    if effect.kind == "rain" then count = effect.count or 5 end
    if count < 1 then count = 1 end
    enqueuePower(effect, user, count)
    deleteCmd()
    if effect.kind == "rain" then flash(effect.name) end
    return
  end
  if not spawn(effect, user) then return end
  deleteCmd()
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

local function screenOf(page, x, y)
  local sp = read8(0x071A) or 0
  local sx = read8(0x071C) or 0
  local rel = (page - sp) * 256 + (x - sx)
  return rel, y
end

local function labelFont(text)
  if string.find(tostring(text or ""), "[\128-\255]") then return "Segoe UI Emoji" end
  return nameStyle.font
end

local function drawLabel(px, py, text)
  local tx = math.floor(px)
  local ty = math.floor(py)
  if tx < 20 then tx = 20 end
  if tx > 236 then tx = 236 end
  if ty < 18 then ty = 18 end
  if ty > 210 then ty = 210 end
  local drawn = false
  local font = labelFont(text)
  if gui.drawText then
    drawn = pcall(gui.drawText, tx, ty, text, nameStyle.color, 0xC0101828, nameStyle.size, font, nameStyle.style, "center", "bottom")
    if not drawn and font ~= "Segoe UI Emoji" then
      drawn = pcall(gui.drawText, tx, ty, text, nameStyle.color, 0xC0101828, nameStyle.size, "Segoe UI Emoji", nameStyle.style, "center", "bottom")
    end
  end
  if not drawn then
    pcall(gui.pixelText, math.max(4, tx - 8), math.max(4, ty - 10), text, 0xFFFFFF00, 0xC0101828)
  end
end

local function drawNames()
  if not playable() then
    for slot = 0, 5 do slotOwners[slot] = nil end
    coinTag = nil
    return
  end
  for slot = 0, 5 do
    local owner = slotOwners[slot]
    if not alive(slot, owner) then
      slotOwners[slot] = nil
    else
      local page = read8(0x006E + slot)
      local x = read8(0x0087 + slot)
      local y = read8(0x00CF + slot)
      if page and x and y then
        local px, py = screenOf(page, x, y)
        if px > -20 and px < 276 and py > 8 and py < 230 then
          drawLabel(px + 8, py - 2, owner.name)
        end
      end
    end
  end
  if coinTag and frame <= coinTag.untilFrame and coinTag.slot then
    local s = coinTag.slot
    local state = read8(0x002A + s) or 0
    local page = read8(0x007A + s)
    local x = read8(0x0093 + s)
    local y = read8(0x00DB + s)
    if state == 0 or not page or not x or not y then
      coinTag = nil
    else
      local px, py = screenOf(page, x, y)
      if px > -20 and px < 276 then drawLabel(px, py - 8, coinTag.name) end
    end
  else
    coinTag = nil
  end
end

local function guideFlower()
  if FLOWER.on then
    local owner = slotOwners[5]
    if not owner or owner.ptype ~= 1 or not alive(5, owner) then
      FLOWER.on = false
    elseif not FLOWER.landed then
      stepBody(FLOWER)
      if FLOWER.yHigh > 1 or FLOWER.y > 0xE8 then
        FLOWER.on = false
        write8(0x000F + 5, 0)
        write8(0x0016 + 5, 0)
        slotOwners[5] = nil
      else
        write8(0x006E + 5, FLOWER.page)
        write8(0x0087 + 5, FLOWER.x)
        write8(0x00B6 + 5, FLOWER.yHigh)
        write8(0x00CF + 5, FLOWER.y)
        write8(0x001E + 5, 0x80)
        write8(0x000F + 5, 1)
      end
    end
  end
end

local function drawHud()
  pcall(function()
    if gui.drawText then
      gui.drawText(128, 4, "livepulse", 0x99FFFFFF, 0x00000000, 11, "Segoe UI", "regular", "center", "top")
      if hudNote ~= "" and frame <= hudUntil then
        gui.drawText(128, 16, hudNote, 0xCCFFFFFF, 0x00000000, 11, "Segoe UI", "regular", "center", "top")
      end
    else
      gui.pixelText(104, 4, "livepulse", 0x99FFFFFF, 0x00000000)
    end
  end)
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
  if not active then
    accept = false
    if not pausedOnly() then
      powerQueue = {}
      nextPowerAt = 0
      FLOWER.on = false
    end
  else
    accept = true
    poll()
    pumpPower()
  end
  if active then
    guideFlower()
    drawNames()
  end
  drawHud()
  emu.frameadvance()
end
