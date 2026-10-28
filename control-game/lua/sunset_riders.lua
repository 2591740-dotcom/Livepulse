-- Sunset Riders (USA) SNES — LivePulse
-- El spawn es el de $82:B4B0. La clase $000A ocupa un slot libre
-- ($4E,X == 0, X de $36 a $1C de dos en dos). $03C0 es el tipo:
-- 0 placa dorada, 2 placa plateada, 6 corazon.
-- $86,X y $BE,X son la posicion del mundo. $0BA4 y $0BA6 son la camara.
-- $0118 y $011A son los dos cupos del juego. $03F8 guarda cual se uso.
-- No se escribe el arma del jugador ($0144 / $0148) ni las vidas ($1FBA).
-- El jugador las recoge. El juego aplica el efecto.

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

local CLASS_PICKUP = 0x000A
local TYPE_GOLD = 0
local TYPE_SILVER = 2
local TYPE_HEART = 6

local CLEAR_AT = {
  0x0318, 0x03C0, 0x03F8, 0x0430, 0x0468, 0x04A0, 0x04D8,
  0x0510, 0x0548, 0x0350, 0x0200, 0x0238, 0x0270
}

local EFFECTS = {
  SPAWN_RAPID = { name = "Placa dorada", types = { TYPE_GOLD } },
  SPAWN_RIFLE = { name = "Placa plateada", types = { TYPE_SILVER } },
  SPAWN_WHISKEY = { name = "Corazon", types = { TYPE_HEART } },
  LLUVIA_ARMAS = { name = "Lluvia de placas", types = { TYPE_GOLD, TYPE_SILVER, TYPE_GOLD, TYPE_SILVER } },
  LLUVIA_VIDAS = { name = "Lluvia de vidas", types = { TYPE_HEART, TYPE_HEART, TYPE_HEART, TYPE_HEART, TYPE_HEART } }
}

local frame = 0
local nameStyle = { size = 16, font = "Segoe UI", style = "regular", color = 0xFFFFFF00, back = 0x00000000 }
local hudNote = ""
local hudUntil = 0
local ramReady = false
local owned = {}
local queue = {}
local quietUntil = 0

pcall(function()
  if memory and memory.usememorydomain then
    memory.usememorydomain("WRAM")
    ramReady = true
  end
end)

local function read16(addr)
  if ramReady and memory and memory.read_u16_le then
    local ok, value = pcall(memory.read_u16_le, addr)
    if ok and type(value) == "number" then return value % 65536 end
  end
  if mainmemory and mainmemory.read_u16_le then
    local ok, value = pcall(mainmemory.read_u16_le, addr)
    if ok and type(value) == "number" then return value % 65536 end
  end
  return nil
end

local function write16(addr, value)
  local word = math.floor(value) % 65536
  if ramReady and memory and memory.write_u16_le then
    local ok = pcall(memory.write_u16_le, addr, word)
    if ok then return true end
  end
  if mainmemory and mainmemory.write_u16_le then
    local ok = pcall(mainmemory.write_u16_le, addr, word)
    if ok then return true end
  end
  return false
end

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

local function signed(value)
  local word = value % 65536
  if word >= 32768 then return word - 65536 end
  return word
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

-- El jugador 1 es el slot 0. El jugador 2 es el slot 2.
-- Las vidas estan en $1FBA,X y el juego no pasa de 16.
local function playerSlot()
  local lives = read16(0x1FBA)
  local classId = read16(0x004E)
  if lives and classId and lives > 0 and lives <= 16 and classId ~= 0 then
    return 0
  end
  lives = read16(0x1FBC)
  classId = read16(0x0050)
  if lives and classId and lives > 0 and lives <= 16 and classId ~= 0 then
    return 2
  end
  return nil
end

local function playable()
  if smb1() then return false end
  if playerSlot() == nil then return false end
  if read16(0x0BA4) == nil or read16(0x0BA6) == nil then return false end
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

-- El juego solo tiene dos cupos de objeto recogible.
local function itemMark()
  if read16(0x0118) == 0 then return 0 end
  if read16(0x011A) == 0 then return 2 end
  return nil
end

local function findActor()
  local slot = 0x36
  while slot >= 0x1C do
    if read16(0x004E + slot) == 0 then return slot end
    slot = slot - 2
  end
  return nil
end

local function clearSlot(slot)
  local index = 1
  while index <= #CLEAR_AT do
    if not write16(CLEAR_AT[index] + slot, 0) then return false end
    index = index + 1
  end
  return true
end

local function spawnOne(item)
  local who = playerSlot()
  if not who then return false end
  local mark = itemMark()
  if not mark then return false end
  local slot = findActor()
  if not slot then return false end
  local px = read16(0x0086 + who)
  local py = read16(0x00BE + who)
  local cam = read16(0x0BA4)
  if not px or not py or not cam then return false end
  local screenX = signed(px - cam)
  local dir = 1
  if screenX > 128 then dir = -1 end
  local extra = 0
  if mark == 2 then extra = 36 end
  local x = (px + dir * (64 + extra)) % 65536
  local landed = signed(x - cam)
  if landed < 32 then x = (cam + 32) % 65536 end
  if landed > 224 then x = (cam + 224) % 65536 end
  if not clearSlot(slot) then return false end
  if not write16(0x0086 + slot, x) then return false end
  if not write16(0x00BE + slot, py) then return false end
  if not write16(0x0510 + slot, 0) then return false end
  if not write16(0x0190 + slot, 1) then return false end
  if not write16(0x03C0 + slot, item.type) then return false end
  if not write16(0x03F8 + slot, mark) then return false end
  if not write16(0x0118 + mark, 1) then return false end
  if not write16(0x011C, (slot - 2) % 65536) then return false end
  if not write16(0x004E + slot, CLASS_PICKUP) then
    write16(0x0118 + mark, 0)
    return false
  end
  owned[slot] = { name = item.user, kind = item.type, born = frame }
  return true
end

local function enqueue(effect, user)
  local index = 1
  while index <= #effect.types do
    queue[#queue + 1] = { type = effect.types[index], user = user, label = effect.name }
    index = index + 1
  end
end

local function pump()
  if not playable() then return end
  if frame < quietUntil then return end
  if #queue == 0 then return end
  if not itemMark() or not findActor() then return end
  local item = queue[1]
  if not spawnOne(item) then return end
  table.remove(queue, 1)
  quietUntil = frame + 24
  flashHud(item.label)
end

local function poll()
  pump()
  if #queue > 0 then return end
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
  enqueue(effect, user)
  deleteCmd()
  pump()
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
  local camX = read16(0x0BA4)
  local camY = read16(0x0BA6)
  if not camX or not camY then return end
  local slot = 0x1C
  while slot <= 0x36 do
    local own = owned[slot]
    if own and frame > own.born then
      local classId = read16(0x004E + slot)
      local kind = read16(0x03C0 + slot)
      if classId == CLASS_PICKUP and kind == own.kind then
        local wx = read16(0x0086 + slot)
        local wy = read16(0x00BE + slot)
        if wx and wy then
          drawLabel(signed(wx - camX), signed(wy - camY) - 8, own.name)
        end
      else
        owned[slot] = nil
      end
    end
    slot = slot + 2
  end
end

local function drawHero()
  if heroName == "" or smb1() then return end
  local who = playerSlot()
  if not who then return end
  local camX = read16(0x0BA4)
  local camY = read16(0x0BA6)
  local wx = read16(0x0086 + who)
  local wy = read16(0x00BE + who)
  if not camX or not camY or not wx or not wy then return end
  drawLabel(signed(wx - camX) + 8, signed(wy - camY) - 24, heroName, heroText)
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
  if active then
    poll()
  else
    pump()
  end
  drawNames()
  pcall(drawHero)
  drawHud()
  emu.frameadvance()
end
