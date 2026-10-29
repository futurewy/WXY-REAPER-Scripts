-- @description BPM Calculator - independent beats/duration conversion and tap tempo
-- @author futurewy
-- @version 1.0
-- @about
--   Independent native REAPER gfx calculator. No FX, SWS, ReaImGui or other dependencies.
--   Beats are quarter-note beats (4 beats = one 4/4 bar); duration is in seconds.
--   Convert beats + seconds to BPM, or beats + BPM to seconds.
--   Tap with the mouse or Space. Tap intervals below 0.10 seconds are ignored;
--   a gap over 3 seconds starts a new sequence. Average the latest 16 intervals.
--   Space uses physical key-down edges to avoid keyboard auto-repeat taps.
--   This utility never changes project tempo, transport, selection or media.
-- @changelog
--   v1.0: Initial independent native gfx calculator and tap-tempo implementation.

local TITLE = "BPM Calculator - futurewy"
local MIN_INTERVAL, TAP_TIMEOUT, MAX_INTERVALS = 0.10, 3.0, 16

local function positive(value)
  return type(value) == "number" and value == value and value > 0 and value < math.huge
end

local function parse_positive(text)
  if type(text) ~= "string" then return nil, "Enter a positive decimal number." end
  text = text:match("^%s*(.-)%s*$")
  if #text > 32 or not (text:match("^%d+%.?%d*$") or text:match("^%.%d+$")) then
    return nil, "Use a positive decimal number (dot separator, no units)."
  end
  local value = tonumber(text)
  if not positive(value) then return nil, "The value must be finite and greater than zero." end
  return value
end

local function calculate_bpm(beats, seconds)
  if not positive(beats) or not positive(seconds) then return nil end
  local result = (beats / seconds) * 60
  if positive(result) then return result end
end

local function calculate_seconds(beats, bpm)
  if not positive(beats) or not positive(bpm) then return nil end
  local result = (beats / bpm) * 60
  if positive(result) then return result end
end

local function new_taps()
  return {last = nil, intervals = {}, bpm = nil}
end

local function tap(state, now)
  if type(now) ~= "number" or now ~= now or math.abs(now) == math.huge then return false end
  if not state.last then state.last = now; return true end
  local interval = now - state.last
  if interval < 0 or interval > TAP_TIMEOUT then
    state.last, state.intervals, state.bpm = now, {}, nil
    return true
  end
  -- Ignore accidental double clicks without moving the last accepted timestamp.
  if interval < MIN_INTERVAL then return false end
  state.last = now
  state.intervals[#state.intervals + 1] = interval
  if #state.intervals > MAX_INTERVALS then table.remove(state.intervals, 1) end
  local total = 0
  for _, value in ipairs(state.intervals) do total = total + value end
  state.bpm = 60 * #state.intervals / total
  return true
end

local function expire_taps(state, now)
  if state.last and now - state.last > TAP_TIMEOUT then
    state.last, state.intervals, state.bpm = nil, {}, nil
    return true
  end
  return false
end

local function rising(down, previous)
  return down and not previous
end

local beats, seconds, bpm = 4, 2, 120
local taps = new_taps()
local status = "Ready. Project tempo is never changed."
local previous_mouse, previous_space = false, false
local closed = false
local buttons = {}

local function shutdown()
  if not closed then closed = true; gfx.quit() end
end

local function edit_value(name, value)
  local ok, text = reaper.GetUserInputs(TITLE, 1, name .. ":", string.format("%.12g", value))
  if not ok then return nil end
  local result, err = parse_positive(text)
  if not result then status = err end
  return result
end

local function reset()
  beats, seconds, bpm = 4, 2, 120
  taps = new_taps()
  status = "Reset. Ready for a new tap sequence."
end

local function do_tap()
  if tap(taps, reaper.time_precise()) then
    status = taps.bpm and "Tap estimate ready; click Use tap BPM to copy it." or "First tap. Keep tapping..."
  end
end

local function text(x, y, value, size, dim)
  gfx.setfont(1, "Arial", size or 17)
  if dim then gfx.set(0.65, 0.70, 0.76, 1) else gfx.set(0.92, 0.94, 0.97, 1) end
  gfx.x, gfx.y = x, y
  gfx.drawstr(value)
end

local function button(x, y, w, h, label, action)
  local hover = gfx.mouse_x >= x and gfx.mouse_x < x+w and gfx.mouse_y >= y and gfx.mouse_y < y+h
  gfx.set(hover and 0.25 or 0.17, hover and 0.36 or 0.25, hover and 0.48 or 0.33, 1)
  gfx.rect(x,y,w,h,1)
  text(x+10, y+(h-18)/2, label, 16)
  buttons[#buttons+1] = {x=x,y=y,w=w,h=h,action=action}
end

local function draw()
  gfx.set(0.08, 0.10, 0.13, 1); gfx.rect(0,0,gfx.w,gfx.h,1)
  buttons = {}
  if gfx.w < 520 or gfx.h < 475 then
    text(12, 15, "Enlarge window to at least 520 x 475.", 16)
    text(12, 45, "Space: tap | Esc: close", 16)
    return
  end
  text(20, 16, "BPM Calculator", 26)
  text(20, 53, "Quarter-note beats / seconds. Click a value to edit.", 16, true)
  button(20, 84, 480, 35, string.format("Beats: %.10g", beats), function()
    beats = edit_value("Quarter-note beats", beats) or beats
  end)
  button(20, 127, 480, 35, string.format("Duration (seconds): %.10g", seconds), function()
    seconds = edit_value("Duration in seconds", seconds) or seconds
  end)
  button(20, 170, 480, 35, string.format("BPM: %.10g", bpm), function()
    bpm = edit_value("BPM", bpm) or bpm
  end)
  button(20, 217, 235, 36, "Beats + seconds -> BPM", function()
    local result = calculate_bpm(beats, seconds)
    if result then bpm = result; status = "BPM calculated." else status = "Result out of range; use less extreme values." end
  end)
  button(265, 217, 235, 36, "Beats + BPM -> seconds", function()
    local result = calculate_seconds(beats, bpm)
    if result then seconds = result; status = "Duration calculated." else status = "Result out of range; use less extreme values." end
  end)
  local estimate = taps.bpm and string.format("%.2f BPM", taps.bpm) or "-- BPM"
  text(20, 273, "Tap: " .. estimate .. "   (" .. #taps.intervals .. " intervals)", 23)
  button(20, 311, 235, 44, "TAP / Space", do_tap)
  button(265, 311, 235, 44, "Use tap BPM", function()
    if taps.bpm then bpm = taps.bpm; status = "Tap estimate copied to BPM." else status = "Tap at least twice first." end
  end)
  button(20, 367, 150, 34, "Reset all", reset)
  text(185, 375, "Esc: close | No project changes", 15, true)
  -- Wrap status rather than allowing a long error to spill outside the window.
  local line, y = "", 419
  gfx.setfont(1, "Arial", 15)
  for word in status:gmatch("%S+") do
    local candidate = line == "" and word or line .. " " .. word
    if gfx.measurestr(candidate) > gfx.w-40 then text(20,y,line,15,true); line=word; y=y+19 else line=candidate end
  end
  text(20,y,line,15,true)
end

local function loop()
  if closed then return end
  local key = gfx.getchar()
  if key < 0 or key == 27 then shutdown(); return end
  -- Drain character repeats, but derive Space taps from its actual held state.
  for _ = 1, 63 do
    if key == 0 then break end
    key = gfx.getchar()
    if key < 0 or key == 27 then shutdown(); return end
  end
  local now = reaper.time_precise()
  if expire_taps(taps, now) then status = "Tap timeout. Start a new sequence." end
  local space = gfx.getchar(32) == 1
  local mouse = (gfx.mouse_cap & 1) ~= 0
  draw()
  if rising(space, previous_space) then do_tap() end
  if rising(mouse, previous_mouse) then
    for _, item in ipairs(buttons) do
      if gfx.mouse_x >= item.x and gfx.mouse_x < item.x+item.w and gfx.mouse_y >= item.y and gfx.mouse_y < item.y+item.h then
        item.action(); break
      end
    end
  end
  previous_space, previous_mouse = space, mouse
  gfx.update()
  reaper.defer(loop)
end

reaper.atexit(shutdown)
gfx.init(TITLE, 540, 480, 0)
gfx.setfont(1, "Arial", 17)
loop()
