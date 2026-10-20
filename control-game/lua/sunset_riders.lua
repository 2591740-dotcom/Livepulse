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
local nameStyle = { size = 16, font = "Segoe UI Emoji", style = "regular", color = 0xFFFFFF00 }
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
  drawHud()
  emu.frameadvance()
end
