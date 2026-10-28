-- LivePulse Control Game
-- Super Mario World (SNES) para BizHawk, núcleos snes9x y bsnes.
--
-- LivePulse escribe UNA línea en:
--   C:\LivePulse\livepulse_cmd.txt
-- Formato: COMANDO|Usuario|Diamantes
-- Ejemplo: SPAWN_HONGO|Maria_Live|5
--
-- Este script lee el archivo cada 3 frames, solo con el nivel en marcha.
-- Lo que llegó antes de eso se tira. El juego solo tiene 12 espacios.
-- Se llenan todos. El siguiente regalo borra solo el más antiguo.
--
-- Carga automática (la pone LivePulse al pulsar Iniciar Juego):
--   EmuHawk.exe --lua="C:\Users\Pc\LivePulse\control-game\lua\smw_livepulse.lua" "C:\ruta\Super Mario World.sfc"
--
-- El estado $08 sin inicio, la posición alta en 0 y no escribir las
-- tablas $1656-$190F dejan el cuadro y la paleta vacíos: el enemigo
-- sale deforme. Aquí el estado $01 corre el inicio del juego. Yoshi
-- es la excepción y se explica en spawn().

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
local MAX_OURS = 12
local MAX_SCREEN = 12

-- IDs y bytes de las tablas $1656, $1662, $166E, $167A, $1686 y $190F del ROM USA.
-- Los power-ups llevan $C2 en $167A: Mario no los trata como enemigos.
-- Nacen lejos de Mario para que el nombre del viewer se lea encima del regalo.
local EFFECTS = {
  SPAWN_HONGO = { id = 0x74, dy = -140, name = "Hongo", tweaks = { 0x00, 0x00, 0x08, 0xC2, 0x28, 0x40 } },
  SPAWN_FLOR = { id = 0x75, dy = -140, power = true, name = "Flor", tweaks = { 0x00, 0x00, 0x0A, 0xC2, 0x28, 0x40 } },
  SPAWN_ESTRELLA = { id = 0x76, dy = -96, star = true, name = "Estrella", tweaks = { 0x00, 0x00, 0x20, 0xC2, 0x28, 0x40 } },
  SPAWN_CAPA = { id = 0x77, dy = -140, name = "Capa", tweaks = { 0x00, 0x00, 0x24, 0xC2, 0x28, 0x40 } },
  SPAWN_1UP = { id = 0x78, dy = -140, name = "1-Up", tweaks = { 0x00, 0x00, 0x0A, 0xC2, 0x08, 0x40 } },
  SPAWN_MONEDA = { id = 0x21, dy = -140, name = "Moneda", tweaks = { 0x00, 0x00, 0x24, 0xC2, 0x08, 0x04 } },
  SPAWN_YOSHI = { id = 0x35, dy = -120, yoshi = true, name = "Yoshi", tweaks = { 0x05, 0x09, 0x2A, 0x87, 0x29, 0x46 } },
  SPAWN_HUEVO = { id = 0x2C, dy = -120, name = "Huevo de Yoshi", tweaks = { 0x00, 0x00, 0x3B, 0x9A, 0x09, 0x44 } },
  SPAWN_BLOQUE = { id = 0x84, dy = -100, name = "Bloque ?", tweaks = { 0x00, 0x0C, 0x20, 0x82, 0x31, 0x40 } },
  SPAWN_PSWITCH = { id = 0x3E, dy = -120, name = "P-Switch", tweaks = { 0x00, 0x00, 0x30, 0x3E, 0x0A, 0xC4 } },
  SPAWN_GOOMBA = { id = 0x0F, dy = -120, name = "Goomba", tweaks = { 0x10, 0x00, 0x04, 0x18, 0x00, 0x80 } },
  SPAWN_KOOPA = { id = 0x04, dy = -120, name = "Koopa", tweaks = { 0x10, 0x40, 0x0A, 0x00, 0x02, 0xA0 } },
  SPAWN_KOOPA_ROJO = { id = 0x05, dy = -120, name = "Koopa rojo", tweaks = { 0x10, 0x40, 0x08, 0x00, 0x02, 0xA0 } },
  SPAWN_KOOPA_AZUL = { id = 0x06, dy = -120, name = "Koopa azul", tweaks = { 0x10, 0x40, 0x06, 0x00, 0x02, 0xA0 } },
  SPAWN_PARAKOOPA = { id = 0x08, dy = -100, name = "Para-Koopa", tweaks = { 0x10, 0x40, 0x0A, 0x00, 0x42, 0xB0 } },
  SPAWN_BALA = { id = 0x1C, side = true, name = "Bala", tweaks = { 0x10, 0x80, 0x12, 0x00, 0x90, 0x00 } },
  SPAWN_BUZZY = { id = 0x11, dy = -120, name = "Buzzy", tweaks = { 0x10, 0x00, 0x1D, 0x00, 0x00, 0x80 } },
  SPAWN_SPINY = { id = 0x13, dy = -120, name = "Pincho", tweaks = { 0x00, 0x00, 0x09, 0x00, 0x00, 0x00 } },
  SPAWN_LAKITU = { id = 0x1E, dy = -80, name = "Lakitu", tweaks = { 0x11, 0x81, 0x09, 0x00, 0x11, 0x60 } },
  SPAWN_MARTILLO = { id = 0x9B, dy = -120, name = "Martillo", tweaks = { 0x10, 0x80, 0x00, 0x01, 0x01, 0x40 } },
  SPAWN_BOBOMB = { id = 0x0D, dy = -120, name = "Bob-omb", tweaks = { 0x10, 0x00, 0x17, 0x18, 0x00, 0x80 } },
  SPAWN_THWOMP = { id = 0x26, dy = -80, name = "Thwomp", tweaks = { 0x01, 0x06, 0x33, 0x01, 0x01, 0x24 } },
  SPAWN_FANTASMA = { id = 0x37, dy = -80, name = "Fantasma", tweaks = { 0x00, 0x00, 0xF3, 0x01, 0x19, 0x04 } },
  SPAWN_EERIE = { id = 0x39, dy = -80, name = "Espectro", tweaks = { 0x00, 0x00, 0xFD, 0x01, 0x19, 0x04 } },
  SPAWN_PEZ = { id = 0x17, dy = -80, name = "Pez", tweaks = { 0x10, 0x80, 0x85, 0x00, 0x90, 0x00 } },
  SPAWN_DELFIN = { id = 0x43, dy = -80, name = "Delfín", tweaks = { 0x00, 0x10, 0x37, 0x82, 0x8D, 0x05 } },
  -- Un solo comando crea varios sprites. El tope sigue siendo 12.
  CAOS_GOOMBAS = { count = 6, base = "SPAWN_GOOMBA", name = "Caos Goombas" },
  CAOS_KOOPAS = { count = 5, base = "SPAWN_KOOPA", name = "Caos Koopas" },
  LLUVIA_ENEMIGOS = {
    mix = { "SPAWN_GOOMBA", "SPAWN_KOOPA", "SPAWN_KOOPA_ROJO", "SPAWN_BUZZY", "SPAWN_SPINY", "SPAWN_PARAKOOPA", "SPAWN_BOBOMB", "SPAWN_FANTASMA" },
    name = "Lluvia de enemigos"
  },
  EJERCITO = {
    mix = {
      "SPAWN_GOOMBA", "SPAWN_KOOPA", "SPAWN_KOOPA_ROJO", "SPAWN_KOOPA_AZUL",
      "SPAWN_BUZZY", "SPAWN_SPINY", "SPAWN_PARAKOOPA", "SPAWN_BOBOMB",
      "SPAWN_FANTASMA", "SPAWN_EERIE", "SPAWN_GOOMBA", "SPAWN_KOOPA"
    },
    name = "Ejército"
  },
  LLUVIA_VIDAS = { count = 7, base = "SPAWN_1UP", name = "Lluvia de vidas" },
  LLUVIA_HONGOS = { count = 5, base = "SPAWN_HONGO", name = "Lluvia de hongos" }
}

local TWEAK_AT = { 0x1656, 0x1662, 0x166E, 0x167A, 0x1686, 0x190F }

-- El martillo $9B no dibuja el cuerpo. Lo dibuja la plataforma $9C, y solo
-- si el martillo está en un hueco 0-9. Los bytes salen de las tablas del ROM.
local HAMMER_PLAT = { id = 0x9C, tweaks = { 0x00, 0x1D, 0x30, 0xA2, 0x39, 0x40 } }

-- Tablas de un slot. Se limpian para que un sprite viejo no deje velocidad ni estado.
local CLEAR_AT = {
  0x00AA, 0x00B6, 0x00C2, 0x14EC, 0x14F8,
  0x1504, 0x1510, 0x151C, 0x1528, 0x1534, 0x1540, 0x154C, 0x1558,
  0x1564, 0x1570, 0x157C, 0x1588, 0x1594, 0x15A0, 0x15B8,
  0x15AC, 0x15C4, 0x15D0, 0x15DC, 0x15EA, 0x15F6, 0x1602,
  0x160E, 0x1626, 0x1632, 0x163E, 0x164A,
  0x1656, 0x1662, 0x166E, 0x167A, 0x1686, 0x186C,
  0x187B, 0x190F, 0x1FD6, 0x1FE2
}

local memMode = nil
local frame = 0
local hudLine = "Hasta 12 en pantalla"
local hudUntil = 240
local nameStyle = { size = 16, font = "Segoe UI", style = "regular", color = 0xFFFFFF00, back = 0x00000000 }
local ioWarned = false
local slotOwners = {}

pcall(function()
  if os and os.time then math.randomseed(os.time()) end
end)

local function utf8prefix(text, maxBytes)
  text = tostring(text or "")
  if #text <= maxBytes then return text end
  local i = 1
  local last = 0
  while i <= #text do
    local b = text:byte(i)
    local len = 1
    if b >= 240 then len = 4
    elseif b >= 224 then len = 3
    elseif b >= 192 then len = 2
    end
    if i + len - 1 > maxBytes then break end
    last = i + len - 1
    i = i + len
  end
  if last < 1 then return "" end
  return text:sub(1, last)
end

-- BizHawk 2.11 se cuelga dentro de drawText con Segoe UI Emoji o con un emoji.
-- Los acentos (2 bytes) se quedan. El emoji (3 o 4 bytes) no se pinta.
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

local function note(text, frames)
  hudLine = utf8prefix(text, 48)
  hudUntil = frame + (frames or 180)
end

local function read8(addr)
  if memMode ~= "bus" and memory.read_u8 then
    local ok, value = pcall(memory.read_u8, addr, "WRAM")
    if ok and type(value) == "number" then
      memMode = "wram"
      return value
    end
  end
  if memMode ~= "bus" and memory.readbyte then
    local ok, value = pcall(memory.readbyte, addr, "WRAM")
    if ok and type(value) == "number" then
      memMode = "wram"
      return value
    end
  end
  local bus = 0x7E0000 + addr
  if memory.read_u8 then
    local ok, value = pcall(memory.read_u8, bus, "System Bus")
    if ok and type(value) == "number" then
      memMode = "bus"
      return value
    end
  end
  if memory.readbyte then
    local ok, value = pcall(memory.readbyte, bus, "System Bus")
    if ok and type(value) == "number" then
      memMode = "bus"
      return value
    end
  end
  return nil
end

local function write8(addr, value)
  local byte = math.floor(value) % 256
  if memMode == "bus" then
    local bus = 0x7E0000 + addr
    if memory.write_u8 then
      local ok = pcall(memory.write_u8, bus, byte, "System Bus")
      if ok then return true end
    end
    if memory.writebyte then
      local ok = pcall(memory.writebyte, bus, byte, "System Bus")
      if ok then return true end
    end
    return false
  end
  if memory.write_u8 then
    local ok = pcall(memory.write_u8, addr, byte, "WRAM")
    if ok then return true end
  end
  if memory.writebyte then
    local ok = pcall(memory.writebyte, addr, byte, "WRAM")
    if ok then return true end
  end
  return false
end

local function read16(addr)
  local lo = read8(addr)
  local hi = read8(addr + 1)
  if lo == nil or hi == nil then return nil end
  return lo + hi * 256
end

-- $0100 = $14 es un nivel jugable.
-- $13D4 es la pausa de Start.
-- $009D congela a Mario (tubería, crecimiento, muerte).
-- $0071 distinto de 0 es una animación en la que no debe aparecer nada.
local function playable()
  local mode = read8(0x0100)
  if mode == nil then return false, "Este núcleo no es SNES" end
  if mode ~= 0x14 then return false, "Fuera de nivel" end
  if read8(0x13D4) ~= 0 then return false, "En pausa" end
  if read8(0x009D) ~= 0 then return false, "Espera un momento" end
  if read8(0x0071) ~= 0 then return false, "Espera un momento" end
  return true, ""
end

-- Primero 0-9. Los slots 10 y 11 se usan al final: SMW a veces los reserva.
local function freeSlot()
  local second = nil
  for slot = 0, 11 do
    if read8(0x14C8 + slot) == 0 then
      if slot <= 9 then return slot end
      if second == nil then second = slot end
    end
  end
  return second
end

local function clamp16(value)
  if value < 0 then return 0 end
  if value > 65535 then return 65535 end
  return math.floor(value)
end

-- La bala nace en el borde de la pantalla, a la altura de Mario.
-- El inicio del juego mira de qué lado está y la hace volar hacia él.
local function bulletX(marioX)
  local camX = read16(0x001A)
  if camX == nil then camX = marioX end
  local left = camX + 16
  local right = camX + 224
  local roomL = marioX - left
  local roomR = right - marioX
  local goLeft = roomL >= roomR
  if roomL >= 64 and roomR >= 64 then
    goLeft = math.random(0, 1) == 0
  end
  local x = goLeft and left or right
  return clamp16(x)
end

local function tagName(user)
  local name = tostring(user or "")
  if name == "" then name = "Viewer" end
  return utf8prefix(name, 192)
end

-- Lado lejano de la pantalla, pero dentro del área que el juego sí dibuja.
-- En el borde mismo (16 o 232) el sprite queda fuera y desaparece.
local function apart(marioX, marioY, dy)
  local camX = read16(0x001A)
  if camX == nil then camX = marioX end
  local left = camX + 40
  local right = camX + 200
  local x = (marioX - left) >= (right - marioX) and left or right
  local y = marioY + (dy or -120)
  local camY = read16(0x001C)
  if camY ~= nil then
    local top = camY + 40
    local bottom = camY + 120
    if y < top then y = top end
    if y > bottom then y = bottom end
  end
  return clamp16(x), clamp16(y)
end

-- Reparte un grupo dentro de la pantalla, lejos del borde donde el juego lo borra.
local function waveXY(marioX, marioY, effect, spot, total)
  local camX = read16(0x001A)
  if camX == nil then camX = marioX end
  local camY = read16(0x001C)
  local cols = total or 1
  if cols > 6 then cols = 6 end
  if cols < 1 then cols = 1 end
  local col = (spot or 0) % cols
  local row = math.floor((spot or 0) / cols)
  local step = 24
  local width = (cols - 1) * step
  local left = camX + 40
  local right = camX + 200
  local x
  if (marioX - left) >= (right - marioX) then
    x = left + col * step
  else
    x = right - width + col * step
  end
  local y = marioY + (effect.dy or -120)
  if camY ~= nil then
    y = camY + 48 + row * 28
    if y < camY + 40 then y = camY + 40 end
    if y > camY + 120 then y = camY + 120 end
  end
  return clamp16(x), clamp16(y)
end

local function spawn(slot, effect, spot, total)
  local marioX = read16(0x0094)
  local marioY = read16(0x0096)
  if marioX == nil or marioY == nil then return false end
  local x, y
  if effect.side then
    x = bulletX(marioX)
    y = clamp16(marioY)
  elseif spot ~= nil then
    x, y = waveXY(marioX, marioY, effect, spot, total)
  else
    x, y = apart(marioX, marioY, effect.dy)
  end

  -- El hueco estaba libre. Se pone en 0 otra vez por si el frame anterior
  -- dejó el slot a medias, y recién después se escriben los datos.
  if not write8(0x14C8 + slot, 0x00) then return false end
  for i = 1, #CLEAR_AT do
    if not write8(CLEAR_AT[i] + slot, 0) then return false end
  end
  if not write8(0x009E + slot, effect.id) then return false end
  -- La posición alta sale de Mario. Ponerla en 0 deja el sprite en la
  -- primera pantalla y el contacto queda mal.
  if not write8(0x00E4 + slot, x % 256) then return false end
  if not write8(0x14E0 + slot, math.floor(x / 256)) then return false end
  if not write8(0x00D8 + slot, y % 256) then return false end
  if not write8(0x14D4 + slot, math.floor(y / 256)) then return false end
  if not write8(0x161A + slot, 0xFF) then return false end
  if not write8(0x157C + slot, x >= marioX and 1 or 0) then return false end
  if effect.tweaks then
    for i = 1, #TWEAK_AT do
      if not write8(TWEAK_AT[i] + slot, effect.tweaks[i]) then return false end
    end
    if not write8(0x15F6 + slot, effect.tweaks[3] % 16) then return false end
  end
  if effect.star or effect.power then
    -- El inicio del power-up solo suma 1 a $C2. Con ese valor la flor y la
    -- estrella están "saliendo de un bloque" y se van de la pantalla. Estado
    -- $08 y $C2 en 0 las dejan en el rebote normal, visibles en el aire.
    if not write8(0x00C2 + slot, 0x00) then return false end
    if not write8(0x00AA + slot, 0xE0) then return false end
    if not write8(0x00B6 + slot, x >= marioX and 0xE8 or 0x18) then return false end
    if not write8(0x14C8 + slot, 0x08) then return false end
    return true
  end
  if effect.yoshi then
    -- Yoshi adulto, de pie. El estado 01 corre un inicio que lo borra
    -- si Mario ya trae uno, y sin pose el dibujo sale a pedazos.
    -- $8B es el $87 original más el bit de seguir vivo fuera de pantalla,
    -- para que no se borre en el frame en que Mario se monta.
    if not write8(0x1602 + slot, 0x00) then return false end
    if not write8(0x160E + slot, 0xFF) then return false end
    if not write8(0x00C2 + slot, 0x00) then return false end
    if not write8(0x157C + slot, 1) then return false end
    if not write8(0x167A + slot, 0x8B) then return false end
    if not write8(0x14C8 + slot, 0x08) then return false end
    return true
  end
  -- $01 al final. En el frame siguiente el juego lo pasa a $08 y corre
  -- el inicio de ese sprite. Ese inicio no reescribe estos flags.
  if not write8(0x14C8 + slot, 0x01) then return false end
  return true
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
  if io == nil or io.open == nil then
    if not ioWarned then
      ioWarned = true
      note("BizHawk bloqueó el archivo")
    end
    return nil
  end
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
  local cmd, user, coins = line:match("^([%w_]+)|([^|\r\n]+)|(%d+)$")
  if not cmd then return nil end
  cmd = string.upper(cmd)
  user = tagName(user)
  return cmd, user, coins
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

local function screenCount()
  local total = 0
  for slot = 0, 11 do
    local status = read8(0x14C8 + slot)
    if status and status ~= 0 then total = total + 1 end
  end
  return total
end

-- Deja sitio para `need` sprites. Solo borra regalos de LivePulse, del más
-- viejo al más nuevo. Si el nivel ocupa el resto, devuelve cuántos caben.
local function reserve(need)
  if type(need) ~= "number" or need < 1 then return 0 end
  local list = {}
  for slot = 0, 11 do
    local owner = slotOwners[slot]
    if owner then
      local status = read8(0x14C8 + slot)
      local id = read8(0x009E + slot)
      list[#list + 1] = {
        slot = slot,
        born = owner.born or 0,
        alive = status ~= nil and status ~= 0 and id == owner.id
      }
    end
  end
  for i = 2, #list do
    local item = list[i]
    local j = i - 1
    while j >= 1 and list[j].born > item.born do
      list[j + 1] = list[j]
      j = j - 1
    end
    list[j + 1] = item
  end
  local oursLeft = #list
  local screenLeft = screenCount()
  local dropN = 0
  local fit = need
  if fit > MAX_SCREEN then fit = MAX_SCREEN end
  while true do
    local roomScreen = MAX_SCREEN - screenLeft
    local roomOurs = MAX_OURS - oursLeft
    local room = roomScreen
    if roomOurs < room then room = roomOurs end
    if room >= fit then break end
    if dropN >= #list then
      if room < 0 then room = 0 end
      fit = room
      break
    end
    dropN = dropN + 1
    oursLeft = oursLeft - 1
    if list[dropN].alive then screenLeft = screenLeft - 1 end
  end
  if fit < 1 then return 0 end
  for i = 1, dropN do
    local slot = list[i].slot
    if list[i].alive then write8(0x14C8 + slot, 0) end
    slotOwners[slot] = nil
  end
  return fit
end

local function waveList(effect)
  if effect.mix then return effect.mix end
  if effect.base and effect.count and effect.count > 1 then
    local list = {}
    for i = 1, effect.count do list[i] = effect.base end
    return list
  end
  return nil
end

local function ownedAlive(slot)
  local owner = slotOwners[slot]
  if not owner then return false end
  local status = read8(0x14C8 + slot)
  local id = read8(0x009E + slot)
  return status ~= nil and status ~= 0 and id == owner.id
end

local function oldestOwned(lo, hi)
  local bestSlot = nil
  local bestBorn = nil
  for slot = lo, hi do
    if ownedAlive(slot) then
      local born = slotOwners[slot].born or 0
      if bestSlot == nil or born < bestBorn then
        bestSlot = slot
        bestBorn = born
      end
    end
  end
  return bestSlot
end

-- Dos huecos: el martillo en 0-9 (si no, la plataforma no lo encuentra) y
-- la plataforma en cualquier otro. Si no caben, no deja un cuerpo invisible.
local function prepareHammer()
  for _ = 1, 12 do
    local bro = nil
    for slot = 9, 0, -1 do
      if (read8(0x14C8 + slot) or 1) == 0 then
        bro = slot
        break
      end
    end
    local plat = nil
    if bro ~= nil then
      for slot = 0, 11 do
        if slot ~= bro and (read8(0x14C8 + slot) or 1) == 0 then
          plat = slot
          break
        end
      end
    end
    if bro ~= nil and plat ~= nil then return bro, plat end
    local victim = nil
    if bro == nil then
      victim = oldestOwned(0, 9)
      if victim == nil then return nil, nil end
    else
      victim = oldestOwned(0, 11)
      if victim == nil then return nil, nil end
    end
    write8(0x14C8 + victim, 0)
    slotOwners[victim] = nil
  end
  return nil, nil
end

local function poll()
  local line = readCmd()
  if not line then return end
  local cmd, user = parse(line)
  local effect = cmd and EFFECTS[cmd] or nil
  if not effect then
    deleteCmd()
    note("Comando no reconocido")
    return
  end
  rememberPlate(user)
  local canPlay = playable()
  if not canPlay then
    return
  end
  local wave = waveList(effect)
  if wave then
    local fit = reserve(#wave)
    if fit < 1 then
      return
    end
    local made = 0
    for i = 1, fit do
      local one = EFFECTS[wave[i]]
      local slot = freeSlot()
      if one and slot ~= nil and spawn(slot, one, i - 1, fit) then
        slotOwners[slot] = { name = tagName(user), id = one.id, born = frame + i }
        made = made + 1
      end
    end
    deleteCmd()
    if made < 1 then note("No se pudo crear") else note(effect.name .. " ×" .. made) end
    return
  end
  if effect.id == 0x9B then
    local bro, plat = prepareHammer()
    if bro == nil or plat == nil then
      return
    end
    local platform = { id = HAMMER_PLAT.id, dy = effect.dy, tweaks = HAMMER_PLAT.tweaks }
    local broOk = spawn(bro, effect)
    local platOk = broOk and spawn(plat, platform)
    if not broOk or not platOk then
      write8(0x14C8 + bro, 0)
      write8(0x14C8 + plat, 0)
      deleteCmd()
      note("No se pudo crear")
      return
    end
    local who = tagName(user)
    slotOwners[bro] = { name = who, id = effect.id, born = frame }
    slotOwners[plat] = { name = "", id = HAMMER_PLAT.id, born = frame, silent = true }
    deleteCmd()
    note(effect.name .. " · " .. who)
    return
  end
  if reserve(1) < 1 then
    return
  end
  local slot = freeSlot()
  if slot == nil then
    return
  end
  if not spawn(slot, effect) then
    note("No se pudo crear")
    return
  end
  slotOwners[slot] = { name = tagName(user), id = effect.id, born = frame }
  deleteCmd()
  note(effect.name .. " · " .. tagName(user))
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

-- El nombre usa la cámara de este frame ($1A/$1C). La X del sprite no es
-- la X de la pantalla: hay que restarle la cámara.
local function drawNames()
  if read8(0x0100) ~= 0x14 then
    for slot = 0, 11 do slotOwners[slot] = nil end
    return
  end
  local camX = read16(0x001A)
  local camY = read16(0x001C)
  if camX == nil or camY == nil then return end
  for slot = 0, 11 do
    local owner = slotOwners[slot]
    local status = read8(0x14C8 + slot)
    local id = read8(0x009E + slot)
    if not owner or status == nil or status == 0 or id ~= owner.id then
      slotOwners[slot] = nil
    elseif owner.silent or owner.name == nil or owner.name == "" then
      -- La plataforma del martillo cuenta para el tope, pero no pone otro nombre.
    else
      local xlo = read8(0x00E4 + slot)
      local xhi = read8(0x14E0 + slot)
      local ylo = read8(0x00D8 + slot)
      local yhi = read8(0x14D4 + slot)
      if xlo and xhi and ylo and yhi then
        local sx = (xlo + xhi * 256) - camX + 8
        local sy = (ylo + yhi * 256) - camY - 2
        if sx > -8 and sx < 264 and sy > -8 and sy < 220 then
          local tx = math.floor(sx)
          local ty = math.floor(sy)
          if tx < 24 then tx = 24 end
          if tx > 232 then tx = 232 end
          if ty < 14 then ty = 14 end
          local drawn = false
          local shown = tostring(owner.name or "")
          if not drawPlate(tx, ty, plateOf[shown]) then
            local safe = plainName(shown)
            pcall(gui.pixelText, math.max(4, tx - 8), math.max(4, ty - 10), safe ~= "" and safe or "?", 0xFFFFFF00, nameStyle.back)
          end
        end
      end
    end
  end
end

-- Quien está transmitiendo se queda sobre Mario.
local function drawHero()
  if heroName == "" then return end
  if read8(0x0100) ~= 0x14 then return end
  local mx = read16(0x0094)
  local my = read16(0x0096)
  local camX = read16(0x001A)
  local camY = read16(0x001C)
  if mx == nil or my == nil or camX == nil or camY == nil then return end
  local tx = math.floor(mx - camX + 8)
  local ty = math.floor(my - camY - 2)
  if tx < 24 then tx = 24 end
  if tx > 232 then tx = 232 end
  if ty < 14 then ty = 14 end
  local shown = tostring(heroName or "")
  if not drawPlate(tx, ty, heroPlate) then
    local safe = plainName(shown)
    pcall(gui.pixelText, math.max(4, tx - 8), math.max(4, ty - 10), safe ~= "" and safe or "?", 0xFFFFFF00, heroText.back)
  end
end

local function commandWaiting()
  local handle = io.open(CMD_PATH, "r")
  if not handle then return false end
  local raw = handle:read("*l")
  handle:close()
  return raw ~= nil and raw:gsub("%s", "") ~= ""
end

local function drawHud()
  pcall(function()
    if gui.drawText then
      gui.drawText(128, 4, "livepulse", 0x99FFFFFF, 0x00000000, 11, "Segoe UI", "regular", "center", "top")
      if hudUntil >= frame and hudLine ~= "" then
        gui.drawText(128, 16, hudLine, 0xFFFFFF00, 0xC0101828, 12, "Segoe UI", "bold", "center", "top")
      end
    else
      gui.pixelText(104, 4, "livepulse", 0x99FFFFFF, 0x00000000)
      if hudUntil >= frame and hudLine ~= "" then
        gui.pixelText(8, 16, plainName(hudLine), 0xFFFFFF00, 0xC0101828)
      end
    end
  end)
end

pcall(function()
  if memory.usememorydomain then memory.usememorydomain("WRAM") end
end)

deleteCmd()
pcall(os.remove, ON_PATH)
loadStyle()
local accept = false
local wasActive = false

while true do
  frame = frame + 1
  local mode = read8(0x0100)
  local active = mode == 0x14 and read8(0x13D4) == 0 and read8(0x009D) == 0 and read8(0x0071) == 0
  if active ~= wasActive then
    heartbeat(active)
    wasActive = active
  elseif active and frame % 30 == 0 then
    heartbeat(true)
  end
  if frame % 30 == 0 then loadStyle() end
  if mode ~= nil and mode ~= 0x14 then
    for slot = 0, 11 do slotOwners[slot] = nil end
  end
  if not active then
    accept = false
    if frame % 30 == 0 and commandWaiting() then note("Entra a un nivel", 45) end
  else
    accept = true
    if frame % 3 == 0 then
      local ok, err = pcall(poll)
      if not ok then note("Error: " .. tostring(err):sub(1, 28), 90) end
    end
  end
  drawHud()
  if accept then pcall(drawNames) end
  pcall(drawHero)
  emu.frameadvance()
end
