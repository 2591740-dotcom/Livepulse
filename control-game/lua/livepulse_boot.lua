-- Arranque de todos los juegos. BizHawk carga este archivo y luego el script del juego.
-- Acelerar no pasa por livepulse_cmd.txt: cada juego borra un comando que no conoce.
-- C:\LivePulse\livepulse_speed.txt trae la hora unix en que vuelve la velocidad normal.
-- 100 es la velocidad normal. 400 es cuatro veces. Otro regalo reemplaza el plazo y no suma velocidad.
-- El aviso grande cae al centro 5 s antes. En Acelerar el nombre baila despacio con la cuenta de esos segundos.
-- Tras el soft reset el nombre sigue 4 s, se mueve despacio y cambia de tamaño. El movimiento usa el reloj real.
-- Terremoto lee livepulse_quake.txt y sacude la imagen hasta esa hora unix.
-- Rewinder lee livepulse_rewind.txt. No hay aviso de 5 s: la cuenta es el tiempo que retrocede.
-- Guarda un estado cada 4 cuadros en los últimos 10 s, y uno cada 2 s más atrás.
-- Al retroceder apaga el sonido y la imagen va cuadro a cuadro, sin el golpe de cada segundo.

local SPEED_PATH = "C:\\LivePulse\\livepulse_speed.txt"
local QUAKE_PATH = "C:\\LivePulse\\livepulse_quake.txt"
local REWIND_PATH = "C:\\LivePulse\\livepulse_rewind.txt"
local stepRewind
local wipeRewind
local GAME_PATH = "C:\\LivePulse\\livepulse_game.txt"
local ANNOUNCE_PATH = "C:\\LivePulse\\livepulse_announce.txt"
local ACT_PATH = "C:\\LivePulse\\livepulse_emu_act.txt"
local FAST = 400
local NORMAL = 100
local SCALE = 2
local FALL_FRAMES = 45
local applied = nil
local endsAt = 0
local frame = 0
local tick = 0
local spanOf = {}
local announce = nil
local announceKey = ""
local fall = 0
local PHRASE = {
  acelerar = "aceleró el emulador",
  reiniciar = "hizo soft reset",
  cerrar = "cerró el emulador",
  terremoto = "hizo un terremoto",
  rewinder = "hizo rewinder"
}

local function trim(text)
  return tostring(text or ""):gsub("^\239\187\191", ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function readLine(path)
  if io == nil or io.open == nil then return nil end
  local handle = io.open(path, "r")
  if not handle then return nil end
  local line = handle:read("*l")
  handle:close()
  return trim(line)
end

local function refreshEnd()
  local line = readLine(SPEED_PATH)
  if line == nil then
    endsAt = 0
    return
  end
  local n = tonumber(line)
  if n and n > 0 then endsAt = n end
end

local function apply()
  frame = frame + 1
  if frame % 8 == 1 then refreshEnd() end
  local now = os.time()
  local want = NORMAL
  if endsAt > now then want = FAST end
  if want ~= applied then
    local ok = pcall(function() client.speedmode(want) end)
    if ok then applied = want end
  end
  if stepRewind then stepRewind() end
end

local function restore()
  pcall(function() client.speedmode(NORMAL) end)
  applied = NORMAL
  pcall(function() client.SetGameExtraPadding(0, 0, 0, 0) end)
  if wipeRewind then wipeRewind() end
end

local function loadSpans(path)
  if path == nil or path == "" then return nil end
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

local function screenSize()
  local w, h = 256, 224
  if client == nil then return w, h end
  local okW, bw = pcall(client.bufferwidth)
  local okH, bh = pcall(client.bufferheight)
  if okW and type(bw) == "number" and bw >= 16 then w = math.floor(bw) end
  if okH and type(bh) == "number" and bh >= 16 then h = math.floor(bh) end
  return w, h
end

local function drawName(cx, top, plate, scale)
  if plate == nil or plate.path == "" then return 0 end
  if gui == nil or gui.drawLine == nil then return 0 end
  local spans = loadSpans(plate.path)
  if not spans then return 0 end
  scale = math.floor(scale or SCALE)
  if scale < 1 then scale = 1 end
  local w = math.max(1, math.floor(plate.w))
  local h = math.max(1, math.floor(plate.h))
  local x0 = math.floor(cx - (w * scale) / 2)
  local y0 = math.floor(top)
  for i = 1, #spans do
    local s = spans[i]
    local x1 = x0 + s.x * scale
    local y1 = y0 + s.y * scale
    local x2 = x1 + s.len * scale - 1
    for row = 0, scale - 1 do
      gui.drawLine(x1, y1 + row, x2, y1 + row, s.color, "emucore")
    end
  end
  return h * scale
end

local function parseAnnounce(line)
  local action, path, wText, hText, untilText, mode = tostring(line):match("^([a-z]+)|([^|]*)|(%d+)|(%d+)|(%d+)|([a-z]+)$")
  if not action then
    action, path, wText, hText, untilText = tostring(line):match("^([a-z]+)|([^|]*)|(%d+)|(%d+)|(%d+)$")
    mode = "pre"
  end
  if not action or not PHRASE[action] then return nil end
  if mode ~= "dance" and mode ~= "pulse" then mode = "pre" end
  return {
    action = action,
    path = path or "",
    w = tonumber(wText) or 0,
    h = tonumber(hText) or 0,
    untilAt = tonumber(untilText) or 0,
    mode = mode,
    phrase = PHRASE[action]
  }
end

local function countdownNumber()
  if not announce or announce.mode == "pulse" then return nil end
  local now = os.time() or 0
  local left = (announce.untilAt or 0) - now
  if announce.mode == "dance" then
    if left < 1 then return nil end
    if left > 120 then return 120 end
    return left
  end
  if left < 1 then return 1 end
  if left > 5 then return 5 end
  return left
end

local function dropAnnounceFile(line)
  if readLine(ANNOUNCE_PATH) ~= line then return end
  pcall(function() os.remove(ANNOUNCE_PATH) end)
end

local function pollAnnounce()
  if announce and announce.held == true and (os.time() or 0) < (announce.untilAt or 0) then
    local line = readLine(ANNOUNCE_PATH)
    local parsed = line and parseAnnounce(line)
    if parsed and parsed.mode == "pre" then
      announceKey = line
      fall = 0
      announce = parsed
    else
      fall = fall + 1
    end
    return
  end
  local line = readLine(ANNOUNCE_PATH)
  if line == nil or line == "" then
    if not announce or announce.held ~= true then
      announce = nil
      announceKey = ""
      fall = 0
    elseif announce then
      fall = fall + 1
    end
    return
  end
  local parsed = parseAnnounce(line)
  local now = os.time() or 0
  if not parsed then
    announce = nil
    announceKey = ""
    fall = 0
    return
  end
  if line ~= announceKey and parsed.mode == "pulse" then
    parsed.untilAt = now + 4
    parsed.held = true
  end
  if parsed.mode == "dance" and parsed.untilAt > 0 and now >= parsed.untilAt then
    dropAnnounceFile(line)
    announce = nil
    announceKey = ""
    fall = 0
    return
  end
  if line ~= announceKey then
    announceKey = line
    fall = 0
    announce = parsed
  end
  if announce then fall = fall + 1 end
end

local rate = 60
local framesInSec = 0
local markedSec = nil
local fraction = 0
local motionTick = -1
local motionValue = 0

local function motionNow()
  if motionTick == tick then return motionValue end
  motionTick = tick
  local sec = os.time() or 0
  if endsAt > sec and rate < 100 then rate = 240 end
  if markedSec == nil or sec < markedSec then
    markedSec = sec
    framesInSec = 0
    fraction = 0
    motionValue = sec
    return motionValue
  end
  if sec ~= markedSec then
    local elapsed = sec - markedSec
    if elapsed < 1 then elapsed = 1 end
    if elapsed > 2 then elapsed = 1 end
    if framesInSec >= 8 then
      local learned = framesInSec / elapsed
      if learned < 20 then learned = 20 end
      if learned > 480 then learned = 480 end
      rate = learned
    end
    framesInSec = 0
    fraction = 0
    markedSec = sec
    motionValue = sec
    return motionValue
  end
  framesInSec = framesInSec + 1
  fraction = fraction + (1 / rate)
  if fraction > 0.98 then fraction = 0.98 end
  motionValue = sec + fraction
  return motionValue
end

local function nameScale(wave)
  if not announce or announce.mode ~= "pulse" then return SCALE end
  local n = math.floor(2 + math.sin((wave or 0) * 2.1) + 0.5)
  if n < 1 then return 1 end
  if n > 3 then return 3 end
  return n
end

local function drawAnnounce()
  if not announce or gui == nil then return end
  local sw, sh = screenSize()
  if announce.mode == "dance" then refreshEnd() end
  local wave = motionNow()
  local scale = nameScale(wave)
  local nameH = math.max(1, announce.h) * scale
  local phraseH = 18
  local minW = 168
  if announce.mode == "dance" then minW = 210 end
  local boxW = math.max(nameH > 1 and announce.w * scale + 28 or 0, minW)
  if boxW > sw - 8 then boxW = sw - 8 end
  local boxH = nameH + phraseH + 22
  local cx = math.floor(sw / 2)
  local top = 4
  if announce.mode == "pre" then
    local t = math.min(1, fall / FALL_FRAMES)
    t = t * t * (3 - 2 * t)
    local endTop = math.floor((sh - boxH) / 2)
    if endTop < 4 then endTop = 4 end
    top = math.floor((-boxH) + (endTop + boxH) * t)
  else
    local span = 0.62
    if announce.mode == "pulse" then span = 1 end
    local freeX = math.max(0, sw - boxW - 8)
    local freeY = math.max(0, sh - boxH - 8)
    local dx = math.sin(wave * 1.15) * freeX * 0.5 * span
    local dy = math.sin(wave * 0.82 + 0.6) * freeY * 0.5 * span
    if announce.mode == "dance" then
      dx = dx + math.sin(wave * 1.9) * math.min(14, freeX * 0.12)
      dy = dy - math.abs(math.sin(wave * 1.4)) * math.min(16, freeY * 0.22)
    end
    cx = math.floor(sw / 2 + dx)
    top = math.floor((sh - boxH) / 2 + dy)
  end
  local left = math.floor(cx - boxW / 2)
  if left < 2 then left = 2 end
  if top < 2 then top = 2 end
  if left + boxW > sw - 2 then left = math.max(0, sw - 2 - boxW) end
  if top + boxH > sh - 2 then top = math.max(0, sh - 2 - boxH) end
  cx = math.floor(left + boxW / 2)
  if gui.drawRectangle then
    gui.drawRectangle(left, top, boxW, boxH, 0xFFFFD24A, 0x28101828, "emucore")
  end
  local nameTop = top + 8
  if announce.path ~= "" and announce.w > 0 and announce.h > 0 then
    drawName(cx, nameTop, announce, scale)
  end
  if gui.drawText then
    local text = announce.phrase
    local n = countdownNumber()
    if n then text = text .. "  " .. tostring(n) end
    pcall(function()
      gui.drawText(cx, top + 10 + nameH, text, 0xFFFFFF00, 0x00000000, 14, "Segoe UI", "bold", "center", "top", "emucore")
    end)
  end
end

local lastAct = ""

local function consumeAct()
  local line = readLine(ACT_PATH)
  if line == nil or line == "" or line == lastAct then return end
  lastAct = line
  local stamp = tonumber(line:match("^reiniciar|(%d+)$"))
  pcall(function() os.remove(ACT_PATH) end)
  local now = os.time()
  if not stamp or not now then return end
  if now - stamp > 3 or stamp - now > 2 then return end
  if wipeRewind then wipeRewind() end
  pcall(function() client.reboot_core() end)
  now = os.time() or now
  if not announce or announce.mode ~= "pulse" then return end
  announce.untilAt = now + 4
  announce.held = true
  local fresh = "reiniciar|" .. (announce.path or "") .. "|" .. tostring(announce.w or 0) .. "|" .. tostring(announce.h or 0) .. "|" .. tostring(now + 4) .. "|pulse"
  pcall(function()
    local handle = io.open(ANNOUNCE_PATH, "w")
    if handle then
      handle:write(fresh .. "\n")
      handle:close()
    end
  end)
  announceKey = fresh
end

local QUAKE_AMP = 11
local quakeUntil = 0
local quakeOn = false

local function roundInt(n)
  if n >= 0 then return math.floor(n + 0.5) end
  return -math.floor(-n + 0.5)
end

local function refreshQuake()
  local line = readLine(QUAKE_PATH)
  if line == nil or line == "" then
    quakeUntil = 0
    return
  end
  local n = tonumber(line)
  local now = os.time() or 0
  if not n or n <= now then
    quakeUntil = 0
    if readLine(QUAKE_PATH) == line then
      pcall(function() os.remove(QUAKE_PATH) end)
    end
    return
  end
  quakeUntil = n
end

local function applyShake()
  if quakeOn or tick % 4 == 0 then refreshQuake() end
  local now = os.time() or 0
  if quakeUntil <= now then
    if quakeOn then
      pcall(function() client.SetGameExtraPadding(0, 0, 0, 0) end)
      quakeOn = false
    end
    return
  end
  local t = motionNow()
  local ox = roundInt(math.sin(t * 46) * 7 + math.sin(t * 27) * 4)
  local oy = roundInt(math.sin(t * 51 + 0.8) * 6 + math.sin(t * 33) * 4)
  if ox > QUAKE_AMP then ox = QUAKE_AMP end
  if ox < -QUAKE_AMP then ox = -QUAKE_AMP end
  if oy > QUAKE_AMP then oy = QUAKE_AMP end
  if oy < -QUAKE_AMP then oy = -QUAKE_AMP end
  pcall(function()
    client.SetGameExtraPadding(QUAKE_AMP + ox, QUAKE_AMP + oy, QUAKE_AMP - ox, QUAKE_AMP - oy)
  end)
  quakeOn = true
end

local REWIND_KEEP = 120
local DENSE_GAP = 4
local DENSE_SECONDS = 10
local SPARSE_GAP = 120
local rewindSlots = {}
local rewindOn = false
local rewindKey = ""
local rewindUntil = 0
local rewindFrom = 0
local rewindSeconds = 0
local rewindFps = 60
local rewindFrac = 0
local rewindSecMark = 0
local gameClock = 0
local lastCapClock = -100000
local rewindBusy = false
local rewindMuted = false
local soundBefore = true

local function frameStep()
  local n = 60
  if client and client.get_approx_framerate then
    local ok, got = pcall(client.get_approx_framerate)
    if ok and type(got) == "number" and got >= 20 and got <= 120 then
      n = math.floor(got + 0.5)
    end
  end
  if n < 20 then n = 60 end
  if n > 120 then n = 120 end
  return n
end

local function dropRewindSlot(index)
  local old = rewindSlots[index]
  table.remove(rewindSlots, index)
  if old and memorysavestate and memorysavestate.removestate then
    pcall(function() memorysavestate.removestate(old.id) end)
  end
end

local function thinOldRewind()
  local fps = frameStep()
  local denseFrom = gameClock - fps * DENSE_SECONDS
  local gap = SPARSE_GAP
  if gap < fps then gap = fps end
  local i = 1
  local lastKept = -100000
  while i <= #rewindSlots do
    local slot = rewindSlots[i]
    if slot.clock >= denseFrom then break end
    if slot.clock - lastKept < gap then
      dropRewindSlot(i)
    else
      lastKept = slot.clock
      i = i + 1
    end
  end
end

local function trimRewindSlots()
  local keepFrom = gameClock - frameStep() * REWIND_KEEP
  while #rewindSlots > 0 and rewindSlots[1].clock < keepFrom do
    dropRewindSlot(1)
  end
  if gameClock % frameStep() == 0 then thinOldRewind() end
  while #rewindSlots > 220 do
    dropRewindSlot(1)
  end
end

local function pruneRewindFuture()
  local i = 1
  while i <= #rewindSlots do
    if rewindSlots[i].clock > gameClock then
      dropRewindSlot(i)
    else
      i = i + 1
    end
  end
  lastCapClock = gameClock
end

local function rewindSlot(clock)
  if #rewindSlots < 1 then return nil end
  if rewindSlots[1].clock > clock then return rewindSlots[1] end
  local pick = rewindSlots[1]
  for i = 2, #rewindSlots do
    if rewindSlots[i].clock <= clock then
      pick = rewindSlots[i]
    else
      break
    end
  end
  return pick
end

local function rewindSound(mute)
  if not client or not client.SetSoundOn then return end
  if mute then
    if rewindMuted then return end
    local on = true
    if client.GetSoundOn then
      local ok, got = pcall(client.GetSoundOn)
      if ok and got == false then on = false end
    end
    soundBefore = on
    rewindMuted = true
    pcall(function() client.SetSoundOn(false) end)
    return
  end
  if not rewindMuted then return end
  rewindMuted = false
  if soundBefore then
    pcall(function() client.SetSoundOn(true) end)
  end
end

local function showRewind(gone)
  local back = math.floor(gone * rewindFps + 0.5)
  local span = math.floor(rewindSeconds * rewindFps + 0.5)
  if back < 0 then back = 0 end
  if back > span then back = span end
  local target = rewindFrom - back
  local pick = rewindSlot(target)
  if not pick then return end
  if memorysavestate and memorysavestate.loadcorestate then
    pcall(function() memorysavestate.loadcorestate(pick.id) end)
  end
  gameClock = pick.clock
end

local function captureRewind()
  if rewindOn then return end
  gameClock = gameClock + 1
  if memorysavestate == nil or memorysavestate.savecorestate == nil then return end
  local step = DENSE_GAP
  if step < 2 then step = 2 end
  if #rewindSlots > 0 and (gameClock - lastCapClock) < step then return end
  local ok, id = pcall(memorysavestate.savecorestate)
  if not ok or type(id) ~= "string" or id == "" then
    lastCapClock = gameClock - step + 20
    return
  end
  rewindSlots[#rewindSlots + 1] = { clock = gameClock, id = id }
  lastCapClock = gameClock
  trimRewindSlots()
end

local function runRewind()
  local line = readLine(REWIND_PATH)
  local now = os.time() or 0
  if line == nil or line == "" then
    if rewindOn then
      rewindOn = false
      rewindKey = ""
      rewindSound(false)
      pruneRewindFuture()
    end
    captureRewind()
    return
  end
  local untilAt = tonumber(line)
  if not untilAt or untilAt <= now then
    if rewindOn then
      showRewind(rewindSeconds)
      rewindOn = false
      rewindKey = ""
      rewindSound(false)
      pruneRewindFuture()
    end
    if readLine(REWIND_PATH) == line then
      pcall(function() os.remove(REWIND_PATH) end)
    end
    captureRewind()
    return
  end
  if line ~= rewindKey then
    rewindKey = line
    rewindUntil = untilAt
    rewindFrom = gameClock
    local seconds = untilAt - now
    if seconds < 1 then seconds = 1 end
    if seconds > 120 then seconds = 120 end
    rewindSeconds = seconds
    rewindFps = frameStep()
    rewindFrac = 0
    rewindSecMark = now
    rewindOn = true
    rewindSound(true)
    pcall(function() client.speedmode(100) end)
    applied = 100
  end
  if now ~= rewindSecMark then
    rewindSecMark = now
    rewindFrac = 0
  else
    rewindFrac = rewindFrac + 1
  end
  local piece = rewindFrac / rewindFps
  if piece > 0.95 then piece = 0.95 end
  local left = rewindUntil - (now + piece)
  if left < 0 then left = 0 end
  local gone = rewindSeconds - left
  if gone < 0 then gone = 0 end
  pcall(function() client.speedmode(100) end)
  applied = 100
  showRewind(gone)
end

stepRewind = function()
  if rewindBusy then return end
  rewindBusy = true
  pcall(runRewind)
  rewindBusy = false
end

wipeRewind = function()
  rewindOn = false
  rewindKey = ""
  rewindUntil = 0
  rewindFrac = 0
  rewindSound(false)
  rewindSlots = {}
  gameClock = 0
  lastCapClock = -100000
  pcall(function() os.remove(REWIND_PATH) end)
  if memorysavestate and memorysavestate.clearstatesfrommemory then
    pcall(memorysavestate.clearstatesfrommemory)
  end
end

local function paint()
  tick = tick + 1
  if announce or tick % 4 == 0 then pollAnnounce() end
  if announce and announce.held == true and (os.time() or 0) >= (announce.untilAt or 0) then
    local line = readLine(ANNOUNCE_PATH)
    local parsed = line and parseAnnounce(line)
    announce = nil
    announceKey = ""
    fall = 0
    if not parsed or (parsed.mode ~= "pre" and parsed.mode ~= "dance") then
      dropAnnounceFile(line)
    end
  end
  if announce then drawAnnounce() end
  if not announce or announce.mode ~= "pre" then consumeAct() end
  applyShake()
end

if event and event.onframestart then
  event.onframestart(apply, "livepulse-speed")
end
if event and event.onframeend then
  event.onframeend(paint, "livepulse-announce")
end
if event and event.onexit then
  event.onexit(restore, "livepulse-speed-stop")
end
apply()

local game = readLine(GAME_PATH)
if game and game ~= "" then
  dofile(game)
end
