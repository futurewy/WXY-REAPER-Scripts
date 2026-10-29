-- @description Generate and audition passing-chord progressions (Arnie Berle harmony engine)
-- @version 0.7
-- @author futurewy
-- @about
--   Generate passing chords between start and target chords, with automatic,
--   ascending-step and descending-cycle modes, voicing previews and pagination.
--   Requires REAPER with Lua ReaScript support and the ReaImGui extension
--   (available through ReaPack). SWS is optional, for opening chord-reference URLs.
--   Audition uses the virtual MIDI keyboard queue: enable track monitoring and
--   select All MIDI inputs or Virtual MIDI keyboard as the track input.
-- @changelog
--   v0.7: Guard missing ReaImGui APIs before creating the GUI.
--   Reject trailing characters in slash-bass note names.
--   Encode sharp quality symbols in chord-reference URL path segments.
--   Release audition notes at their scheduled off time between queued chords.

--[[
  Arnie Berle 和声引擎  v0.7  （REAPER ReaScript + ReaImGui）

  根据「起始和弦 → 目标和弦」自动生成经过和弦链，规则取自
  Arnie Berle《Understanding Chord Progressions for Guitar》：

    · V–I / II–V / II–V–I 的级进关系
    · 三全音替代（♭II7）
    · 导音减七（VII°7）作经过和弦
    · 半音趋近（上下半音）
    · 五度循环（根音下行纯五度）
    · III 代 I、VI 级
    · 小调 IIø7–V7–I

  声部原则同样来自书中第 56 页：3 音与 7 音必须保留，5 音可以省略。

  试听走虚拟键盘队列（StuffMIDIMessage mode 0），轨道输入设为
  All MIDI inputs 或 Virtual MIDI keyboard、开启监听即可。
]]

local VERSION = "0.7"

-- Fail with an actionable message rather than calling a missing extension API.
local required_imgui = {
  "ImGui_Begin",
  "ImGui_BeginCombo",
  "ImGui_Button",
  "ImGui_Cond_Always",
  "ImGui_CreateContext",
  "ImGui_End",
  "ImGui_EndCombo",
  "ImGui_InputText",
  "ImGui_IsItemClicked",
  "ImGui_MouseButton_Right",
  "ImGui_RadioButton",
  "ImGui_SameLine",
  "ImGui_Selectable",
  "ImGui_Separator",
  "ImGui_SetNextItemWidth",
  "ImGui_SetNextWindowSize",
  "ImGui_SetNextWindowSizeConstraints",
  "ImGui_Spacing",
  "ImGui_Text",
  "ImGui_TextWrapped",
}
for _, name in ipairs(required_imgui) do
  if type(reaper[name]) ~= "function" then
    reaper.ShowMessageBox(
      "This script requires ReaImGui. Install or update ReaImGui via ReaPack, " ..
      "then restart REAPER. Missing API: " .. name,
      "Chord Progression Generator - missing dependency", 0)
    return
  end
end

----------------------------------------------------------------------
-- 1. 音名与和弦性质
----------------------------------------------------------------------

local NOTE_PC = { C = 0, D = 2, E = 4, F = 5, G = 7, A = 9, B = 11 }
local SHARP_NAMES = { "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B" }
local FLAT_NAMES  = { "C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B" }

-- iv  = 音程（半音）
-- ess = 决定和弦性质的音（书中：3 音、7 音或 6 音）
-- roman / name = 级数后缀 / 和弦符号后缀
local QUALITY = {
  maj   = { iv = {0,4,7},       ess = {4},     roman = "",      name = "" },
  min   = { iv = {0,3,7},       ess = {3},     roman = "m",     name = "m" },
  dim   = { iv = {0,3,6},       ess = {3,6},   roman = "°",     name = "dim" },
  aug   = { iv = {0,4,8},       ess = {4,8},   roman = "aug",   name = "aug" },
  sus4  = { iv = {0,5,7},       ess = {5,7},   roman = "sus4",  name = "sus4" },
  sus2  = { iv = {0,2,7},       ess = {2,7},   roman = "sus2",  name = "sus2" },
  five  = { iv = {0,7},         ess = {7},     roman = "5",     name = "5" },
  six   = { iv = {0,4,7,9},     ess = {4,9},   roman = "6",     name = "6" },
  min6  = { iv = {0,3,7,9},     ess = {3,9},   roman = "m6",    name = "m6" },
  maj7  = { iv = {0,4,7,11},    ess = {4,11},  roman = "maj7",  name = "maj7" },
  min7  = { iv = {0,3,7,10},    ess = {3,10},  roman = "m7",    name = "m7" },
  dom7  = { iv = {0,4,7,10},    ess = {4,10},  roman = "7",     name = "7" },
  m7b5  = { iv = {0,3,6,10},    ess = {3,6,10},roman = "ø7",    name = "m7b5" },
  dim7  = { iv = {0,3,6,9},     ess = {3,6,9}, roman = "°7",    name = "dim7" },
  mmaj7 = { iv = {0,3,7,11},    ess = {3,11},  roman = "m(maj7)", name = "m(maj7)" },
  dom9  = { iv = {0,4,7,10,14}, ess = {4,10},  roman = "9",     name = "9" },
  maj9  = { iv = {0,4,7,11,14}, ess = {4,11},  roman = "maj9",  name = "maj9" },
  min9  = { iv = {0,3,7,10,14}, ess = {3,10},  roman = "m9",    name = "m9" },
  add9  = { iv = {0,4,7,14},    ess = {4},     roman = "add9",  name = "add9" },
  dom7b9= { iv = {0,4,7,10,13}, ess = {4,10},  roman = "7♭9",   name = "7b9" },
  dom7s9= { iv = {0,4,7,10,15}, ess = {4,10},  roman = "7♯9",   name = "7#9" },
  dom7b5= { iv = {0,4,6,10},    ess = {4,6,10},roman = "7♭5",   name = "7b5" },
  dom7s5= { iv = {0,4,8,10},    ess = {4,8,10},roman = "7♯5",   name = "7#5" },
}

-- 后缀表：区分大小写，长后缀在前（"m7b5" 必须在 "m7" 之前）
local SUFFIX_TABLE = {
  { "m(maj7)", "mmaj7" }, { "mmaj7", "mmaj7" }, { "mMaj7", "mmaj7" },
  { "m7b5", "m7b5" }, { "ø7", "m7b5" }, { "ø", "m7b5" },
  { "maj7", "maj7" }, { "Maj7", "maj7" }, { "M7", "maj7" }, { "Δ7", "maj7" },
  { "maj9", "maj9" }, { "Maj9", "maj9" }, { "M9", "maj9" },
  { "m7", "min7" }, { "min7", "min7" }, { "-7", "min7" },
  { "m9", "min9" }, { "min9", "min9" }, { "-9", "min9" },
  { "dim7", "dim7" }, { "°7", "dim7" }, { "o7", "dim7" },
  { "dim", "dim" }, { "°", "dim" }, { "o", "dim" },
  { "aug", "aug" }, { "+", "aug" },
  { "sus4", "sus4" }, { "sus2", "sus2" }, { "sus", "sus4" },
  { "add9", "add9" },
  { "7b9", "dom7b9" }, { "7#9", "dom7s9" }, { "7b5", "dom7b5" }, { "7#5", "dom7s5" },
  { "13", "dom9" }, { "11", "min9" }, { "9", "dom9" },
  { "6", "six" }, { "m6", "min6" }, { "min6", "min6" },
  { "m", "min" }, { "min", "min" }, { "-", "min" },
  { "7", "dom7" },
  { "5", "five" },
  { "", "maj" },
}

local SCALE_MAJOR = { 0, 2, 4, 5, 7, 9, 11 }
local SCALE_MINOR = { 0, 2, 3, 5, 7, 8, 10 }
local ROMAN = { "I", "II", "III", "IV", "V", "VI", "VII" }

----------------------------------------------------------------------
-- 2. 小工具
----------------------------------------------------------------------

local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function copy_table(t)
  local out = {}
  for i, v in ipairs(t) do out[i] = v end
  return out
end

----------------------------------------------------------------------
-- 3. 和弦解析（严格：不认识的写法直接报错）
----------------------------------------------------------------------

local function parse_note_name(text)
  local s = trim(text)
  if s == "" or #s > 2 then return nil end
  local base = NOTE_PC[s:sub(1, 1):upper()]
  if not base then return nil end
  local acc = 0
  local second = s:sub(2, 2)
  if second == "#" then acc = 1
  elseif second == "b" then acc = -1
  elseif second ~= "" then return nil end
  return (base + acc) % 12
end

-- 返回 chord 或 nil, 错误信息
local function parse_chord(text)
  local s = trim(text)
  if s == "" then return nil, "和弦不能为空" end

  local base = NOTE_PC[s:sub(1, 1):upper()]
  if not base then return nil, "根音必须是 A–G：" .. s end

  local pos = 2
  local acc = 0
  local second = s:sub(pos, pos)
  if second == "#" then
    acc = 1
    pos = pos + 1
  elseif second == "b" then
    acc = -1
    pos = pos + 1
  end
  local root = (base + acc) % 12

  local rest = s:sub(pos)
  local bass = nil

  local slash = rest:find("/", 1, true)
  if slash then
    local bass_text = rest:sub(slash + 1)
    rest = rest:sub(1, slash - 1)
    bass = parse_note_name(bass_text)
    if not bass then return nil, "斜杠低音无法识别：" .. text end
  end

  local quality
  for _, entry in ipairs(SUFFIX_TABLE) do
    if rest == entry[1] then
      quality = entry[2]
      break
    end
  end
  if not quality then
    return nil, "无法识别的和弦后缀：\"" .. rest .. "\"（在 " .. text .. " 里）"
  end

  return { pc = root, q = quality, bass = bass }
end

----------------------------------------------------------------------
-- 4. 调性、级数、显示
----------------------------------------------------------------------

-- key = { pc = 0..11, minor = true/false }
local function uses_flats(key)
  if key.minor then
    -- 小调里 E、B、F#、C#、G# 用小调习惯用升号，其余用降号
    local sharp_minor = { 4, 11, 6, 1, 8 }
    for _, v in ipairs(sharp_minor) do
      if key.pc == v then return false end
    end
    return true
  end
  local flat_keys = { 5, 10, 3, 8, 1, 6 } -- F Bb Eb Ab Db Gb
  for _, v in ipairs(flat_keys) do
    if key.pc == v then return true end
  end
  return false
end

local LETTERS = { "C", "D", "E", "F", "G", "A", "B" }
local LETTER_PC = { C = 0, D = 2, E = 4, F = 5, G = 7, A = 9, B = 11 }

-- 变化音的习惯拼法：大调用降号（♭II ♭III ♭VI ♭VII），
-- 小调用升号（♯III ♯VI），唯独 ♭II 两种调都按降号写。
local CHROMATIC_MAJOR = { [1] = {2, -1}, [3] = {3, -1}, [6] = {4, 1}, [8] = {6, -1}, [10] = {7, -1} }
local CHROMATIC_MINOR = { [1] = {2, -1}, [4] = {3, 1}, [6] = {4, 1}, [9] = {6, 1}, [11] = {7, 0} }

-- 相对主音的半音数 -> 级数, 升降（-1 降、0 原位、1 升）
-- prefer_sharp：上行时用升号拼写（G♯dim7 而不是 A♭dim7）
local function spell_degree(rel, minor, prefer_sharp)
  local scale = minor and SCALE_MINOR or SCALE_MAJOR
  for i, v in ipairs(scale) do
    if v == rel then return i, 0 end
  end

  if prefer_sharp then
    for i, v in ipairs(scale) do
      if (v + 1) % 12 == rel then return i, 1 end
    end
  end

  local table_ = minor and CHROMATIC_MINOR or CHROMATIC_MAJOR
  local hit = table_[rel]
  if hit then return hit[1], hit[2] end

  if not prefer_sharp then
    for i, v in ipairs(scale) do
      if (v + 1) % 12 == rel then return i, 1 end
    end
  end

  local best_i, best_d = 1, 99
  for i, v in ipairs(scale) do
    local d = math.min((rel - v) % 12, (v - rel) % 12)
    if d < best_d then best_i, best_d = i, d end
  end
  if (rel - scale[best_i] + 12) % 12 > 6 then return best_i, -1 end
  return best_i, 1
end

local function key_letter_index(key)
  local names = uses_flats(key) and FLAT_NAMES or SHARP_NAMES
  local letter = names[key.pc + 1]:sub(1, 1)
  for i, l in ipairs(LETTERS) do
    if l == letter then return i end
  end
  return 1
end

-- 按级数的字母拼写音名，保证名字和级数标注一致（♭II 一定显示成 Db 而不是 C#）
local function name_for_pc(pc, key, prefer_sharp)
  local rel = (pc - key.pc) % 12
  local degree = spell_degree(rel, key.minor, prefer_sharp)
  local idx = ((key_letter_index(key) - 1) + (degree - 1)) % 7 + 1
  local letter = LETTERS[idx]
  local delta = (pc - LETTER_PC[letter] + 12) % 12
  if delta == 1 then return letter .. "#" end
  if delta == 11 then return letter .. "b" end
  if delta == 0 then return letter end
  local names = uses_flats(key) and FLAT_NAMES or SHARP_NAMES
  return names[pc + 1]
end

-- 级数（选项 B：级数恒为大写，性质用后缀表达）
local function roman_of(chord, key)
  local rel = (chord.pc - key.pc) % 12
  local degree, accidental = spell_degree(rel, key.minor, chord.sharp)

  local prefix = ""
  if accidental == -1 then prefix = "♭"
  elseif accidental == 1 then prefix = "♯" end

  return prefix .. ROMAN[degree] .. QUALITY[chord.q].roman
end

local function chord_name(chord, key)
  local s = name_for_pc(chord.pc, key, chord.sharp) .. QUALITY[chord.q].name
  if chord.bass then
    s = s .. "/" .. name_for_pc(chord.bass, key)
  end
  return s
end

-- 组成音：可省略的音（5 音、9 音）用括号包起来
local function chord_notes_text(chord, key)
  local q = QUALITY[chord.q]
  local intervals = {}
  for _, iv in ipairs(q.iv) do intervals[#intervals + 1] = iv end
  table.sort(intervals)

  local parts = {}
  for _, iv in ipairs(intervals) do
    local name = name_for_pc((chord.pc + iv) % 12, key)
    local simple = iv % 12
    if simple == 7 or (iv >= 12 and simple == 2) then
      name = "(" .. name .. ")"
    end
    parts[#parts + 1] = name
  end
  return table.concat(parts, " ")
end

----------------------------------------------------------------------
-- 4b. 和弦指法查询（右键和弦时打开网站）
----------------------------------------------------------------------

-- 网址模板：{root} 是根音（c、f-sharp…），{quality} 是性质（major、m7…）。
-- 如果打开后是 404，把浏览器地址栏里的真实地址发我，或者直接改这一行。
local CHORD_SITE = "https://www.all-guitar-chords.com/chords/index/{root}/{quality}"

local SITE_ROOTS = { "c", "c-sharp", "d", "d-sharp", "e", "f", "f-sharp",
                     "g", "g-sharp", "a", "a-sharp", "b" }

local SITE_QUALITY = {
  maj = "major", min = "minor", dim = "dim", aug = "aug",
  sus2 = "sus2", sus4 = "sus4", five = "5",
  six = "6", min6 = "m6",
  maj7 = "maj7", min7 = "m7", dom7 = "7",
  m7b5 = "m7b5", dim7 = "dim7", mmaj7 = "mmaj7",
  dom9 = "9", maj9 = "maj9", min9 = "m9", add9 = "add9",
  dom7b9 = "7b9", dom7s9 = "7#9", dom7b5 = "7b5", dom7s5 = "7#5",
}

local function chord_site_url(chord)
  local root = SITE_ROOTS[chord.pc + 1] or "c"
  -- A literal # starts a URL fragment, not part of the quality path segment.
  local quality = (SITE_QUALITY[chord.q] or "major"):gsub("#", "%%23")
  return (CHORD_SITE:gsub("{root}", root):gsub("{quality}", function() return quality end))
end

local function open_url(url)
  if reaper.CF_ShellExecute then        -- 装了 SWS 就用它，不会闪命令行窗口
    reaper.CF_ShellExecute(url)
    return
  end
  local os_name = reaper.GetOS() or ""
  local quoted = '"' .. url .. '"'
  if os_name:match("Win") then
    os.execute('start "" ' .. quoted)
  elseif os_name:match("OSX") or os_name:match("macOS") then
    os.execute("open " .. quoted)
  else
    os.execute("xdg-open " .. quoted)
  end
end

----------------------------------------------------------------------
-- 5. 前驱算子（书中的和声手段）
----------------------------------------------------------------------

-- 为一个和弦生成"可放在它前面"的候选和弦
local function predecessors(chord, key)
  local out = {}
  local seen = {}

  local function add(pc, q, rule, weight)
    pc = pc % 12
    local tag = pc .. ":" .. q
    if seen[tag] then return end
    seen[tag] = true
    out[#out + 1] = { pc = pc, q = q, rule = rule, weight = weight }
  end

  local is_minor_target = (chord.q == "min" or chord.q == "min7" or chord.q == "m7b5"
    or chord.q == "dim" or chord.q == "dim7" or chord.q == "mmaj7")

  add(chord.pc + 7, "dom7", "属七 V7", 0)                       -- 最标准的终止
  if is_minor_target then
    add(chord.pc + 2, "m7b5", "小调 IIø7", 1)
    add(chord.pc + 2, "min7", "II–V 的 II", 3)
  else
    add(chord.pc + 2, "min7", "II–V 的 II", 1)
  end
  add(chord.pc + 1, "dom7", "三全音替代 ♭II7", 2)
  add(chord.pc + 11, "dim7", "导音减七 VII°7", 2)
  add(chord.pc + 11, "m7b5", "导音半减七 VIIø7", 4)
  add(chord.pc - 1, "dom7", "半音趋近（下方）", 3)
  add(chord.pc + 5, "dom7", "五度循环（下行五度）", 2)
  add(chord.pc + 9, "min7", "VI 级", 3)
  add(chord.pc + 4, "min7", "III 级（可代 I）", 3)

  -- 同根音改性质（书中 S2：小七改属七增强张力）
  if chord.q == "min7" or chord.q == "min" then
    add(chord.pc, "dom7", "同根音改属七", 4)
  end

  return out
end

----------------------------------------------------------------------
-- 6. 链搜索与评分
----------------------------------------------------------------------

local MAX_CHAINS = 20000      -- 生成上限（4 个经过和弦时约 1.4 万条，够用）
local EVALUATE_LIMIT = 800    -- 只给排在前面的这些做声部排列与完整评分

-- 从目标往回推 n 个前驱，返回候选链（每链含 start 与 target）
local function build_chains(start, target, n, key)
  local results = {}

  local function rec(seq, depth)
    if #results >= MAX_CHAINS then return end
    if depth == n then
      local chain = { start }
      for i, c in ipairs(seq) do chain[#chain + 1] = c end
      results[#results + 1] = chain
      return
    end

    local first = seq[1]
    for _, p in ipairs(predecessors(first, key)) do
      -- 不能和前一个和弦完全重复
      if not (p.pc == first.pc and p.q == first.q) then
        local new_seq = { p }
        for i, c in ipairs(seq) do new_seq[#new_seq + 1] = c end
        rec(new_seq, depth + 1)
      end
    end
  end

  local seq = { target }
  rec(seq, 0)
  return results
end

-- 根音运动代价：下行五度最顺，其次级进，再次半音/三全音
local function motion_cost(from_pc, to_pc)
  local interval = (to_pc - from_pc) % 12
  if interval == 5 then return 0 end      -- 下行五度（书中的循环）
  if interval == 7 then return 1 end      -- 上行四度
  if interval == 2 or interval == 10 then return 1.5 end
  if interval == 1 or interval == 11 then return 2 end
  if interval == 6 then return 3 end      -- 三全音
  if interval == 3 or interval == 9 then return 3 end
  return 4
end

----------------------------------------------------------------------
-- 7. 声部排列（3/7 音必须保留，5 音可省）
----------------------------------------------------------------------

local RANGE_LO, RANGE_HI = 48, 72   -- C3 – C5

local function pitches_with_pc(pc)
  local list = {}
  for p = RANGE_LO, RANGE_HI do
    if p % 12 == pc then list[#list + 1] = p end
  end
  return list
end

-- 选 4 个音级：必备音优先，然后 9 音/根音/五音
local function voice_pcs(chord)
  local q = QUALITY[chord.q]
  local pcs = {}
  for _, iv in ipairs(q.ess) do
    pcs[#pcs + 1] = (chord.pc + iv) % 12
  end
  if #q.iv >= 5 then
    pcs[#pcs + 1] = (chord.pc + q.iv[5]) % 12   -- 九音
  end
  pcs[#pcs + 1] = chord.pc
  local fifth = (chord.pc + 7) % 12
  local has_fifth = false
  for _, pc in ipairs(pcs) do if pc == fifth then has_fifth = true end end
  if not has_fifth then pcs[#pcs + 1] = fifth end

  while #pcs > 4 do table.remove(pcs) end
  while #pcs < 4 do pcs[#pcs + 1] = chord.pc end
  return pcs
end

local function voice_chord(chord, previous)
  local pcs = voice_pcs(chord)

  local best, best_cost

  -- 对每个音级，取范围内所有八度，做一个简单的贪心由低到高排列
  local function try_order(order)
    local voicing = {}
    local cursor = RANGE_LO
    for _, pc in ipairs(order) do
      local placed
      for p = cursor, RANGE_HI do
        if p % 12 == pc then placed = p break end
      end
      if not placed then return nil end
      voicing[#voicing + 1] = placed
      cursor = placed + 1
    end
    return voicing
  end

  -- 升序与几种转位都试一遍，取移动最小的
  local orders = { pcs }
  for i = 2, #pcs do
    local rotated = {}
    for j = i, #pcs do rotated[#rotated + 1] = pcs[j] end
    for j = 1, i - 1 do rotated[#rotated + 1] = pcs[j] end
    orders[#orders + 1] = rotated
  end

  for _, order in ipairs(orders) do
    local voicing = try_order(order)
    if voicing then
      local cost = 0
      if previous then
        local a = copy_table(voicing)
        local b = copy_table(previous)
        table.sort(a)
        table.sort(b)
        for i = 1, math.min(#a, #b) do
          cost = cost + math.abs(a[i] - b[i])
        end
      else
        cost = math.abs(voicing[1] - 60)
      end
      if not best_cost or cost < best_cost then
        best, best_cost = voicing, cost
      end
    end
  end

  return best or { 60, 64, 67 }
end

local function chain_voicings(chain)
  local out = {}
  local previous
  for _, chord in ipairs(chain) do
    local v = voice_chord(chord, previous)
    out[#out + 1] = v
    previous = v
  end
  return out
end

local function chain_cost(chain, voicings, target, direction)
  local cost = 0
  for i = 2, #chain do
    cost = cost + motion_cost(chain[i - 1].pc, chain[i].pc)
    cost = cost + (chain[i].weight or 0) * 0.9
    if chain[i].pc == chain[i - 1].pc then cost = cost + 0.6 end

    -- 方向偏好：下行模式鼓励根音往下走，上行模式由 generate_up 单独处理
    if direction == "down" then
      local interval = (chain[i].pc - chain[i - 1].pc) % 12
      if interval == 5 then
        cost = cost - 0.7            -- 下行五度最顺
      elseif interval == 7 then
        cost = cost + 0.8            -- 上行四度要罚
      elseif interval == 1 then
        cost = cost + 0.7            -- 半音上行也罚
      elseif interval == 11 then
        cost = cost - 0.4
      elseif interval == 2 then
        cost = cost + 0.3
      elseif interval == 10 then
        cost = cost - 0.3
      end
    end

    if voicings then
      local a = copy_table(voicings[i - 1])
      local b = copy_table(voicings[i])
      table.sort(a)
      table.sort(b)
      for k = 1, math.min(#a, #b) do
        cost = cost + math.abs(a[k] - b[k]) * 0.08
      end
    end
  end

  -- 起点重复（把起始和弦又弹一遍）没有意义
  if chain[2] and chain[2].pc == chain[1].pc and chain[2].q == chain[1].q then
    cost = cost + 2.0
  end

  -- 终止式加权：目标前一个是 V7 / ♭II7 / 导音减七 才算解决
  local last = chain[#chain - 1]
  if last and target then
    local cadential =
      (last.q == "dom7" and (last.pc == (target.pc + 7) % 12 or last.pc == (target.pc + 1) % 12)) or
      (last.q == "dom7b9" or last.q == "dom7s9" or last.q == "dom7b5" or last.q == "dom7s5") or
      ((last.q == "dim7" or last.q == "m7b5") and last.pc == (target.pc + 11) % 12)
    if cadential then
      cost = cost - 3.0
    else
      cost = cost + 3.5
    end
  end

  return cost
end

local function chain_rules(chain)
  local parts = {}
  for i = 2, #chain - 1 do
    if chain[i].rule then parts[#parts + 1] = chain[i].rule end
  end
  return table.concat(parts, " + ")
end

----------------------------------------------------------------------
-- 8. 生成入口
----------------------------------------------------------------------

local function generate(start_chord, target_chord, n, key, direction)
  local chains = build_chains(start_chord, target_chord, n, key)

  -- 第一步：只算便宜的分数（根音运动、规则、终止式），不做声部排列
  local scored = {}
  local seen = {}

  for _, chain in ipairs(chains) do
    local tag = ""
    for _, c in ipairs(chain) do tag = tag .. c.pc .. c.q .. "|" end
    if not seen[tag] then
      seen[tag] = true
      scored[#scored + 1] = {
        chain = chain,
        cheap = chain_cost(chain, nil, target_chord, direction),
      }
    end
  end

  table.sort(scored, function(a, b) return a.cheap < b.cheap end)

  -- 第二步：只给排在前面的这些算声部，避免几千条全做排列
  local evaluated = math.min(#scored, EVALUATE_LIMIT)
  local out = {}
  for i = 1, evaluated do
    local item = scored[i]
    local voicings = chain_voicings(item.chain)
    out[#out + 1] = {
      chain = item.chain,
      voicings = voicings,
      cost = chain_cost(item.chain, voicings, target_chord, direction),
      rules = chain_rules(item.chain),
    }
  end

  table.sort(out, function(a, b) return a.cost < b.cost end)
  return out, #scored
end

----------------------------------------------------------------------
-- 8b. 上行阶梯生成（把上行音程拆成 1–2 个半音的若干步）
----------------------------------------------------------------------

-- 调内七和弦的性质
local function diatonic_seventh(pc, key)
  local scale = key.minor and SCALE_MINOR or SCALE_MAJOR
  local major_q = { "maj7", "min7", "min7", "maj7", "dom7", "min7", "m7b5" }
  local minor_q = { "min7", "m7b5", "maj7", "min7", "dom7", "maj7", "dom7" }
  local rel = (pc - key.pc) % 12
  for i, v in ipairs(scale) do
    if v == rel then
      return (key.minor and minor_q or major_q)[i]
    end
  end
  return nil
end

-- 把 d 拆成 parts 份，每份 1 或 2
local function decompose(d, parts, prefix, out)
  if parts == 1 then
    if d >= 1 and d <= 2 then
      local seq = {}
      for i, v in ipairs(prefix) do seq[i] = v end
      seq[#seq + 1] = d
      out[#out + 1] = seq
    end
    return
  end
  for step = 1, 2 do
    local rest = d - step
    if rest >= (parts - 1) and rest <= 2 * (parts - 1) then
      local seq = {}
      for i, v in ipairs(prefix) do seq[i] = v end
      seq[#seq + 1] = step
      decompose(rest, parts - 1, seq, out)
    end
  end
end

-- 每个中间位置可用的和弦性质：调内七和弦优先，其次导音减七、属七
local function up_options(root, next_root, key)
  local options = {}
  local step = (next_root - root + 12) % 12
  local diatonic = diatonic_seventh(root, key)

  if step == 1 then
    options[#options + 1] = { q = "dim7", rule = "半音上行（减七）", penalty = 0.0, sharp = true }
    if diatonic then
      options[#options + 1] = { q = diatonic, rule = "半音上行（调内）", penalty = 0.9 }
    end
    options[#options + 1] = { q = "dom7", rule = "半音上行（属七）", penalty = 1.4, sharp = true }
  else
    if diatonic then
      options[#options + 1] = { q = diatonic, rule = "级进上行（调内）", penalty = 0.0 }
    end
    options[#options + 1] = { q = "dom7", rule = "级进上行（属七）", penalty = 0.7 }
    options[#options + 1] = { q = "dim7", rule = "级进上行（减七）", penalty = 1.8 }
  end

  return options
end

-- 给每个中间位置挑一种性质，做笛卡尔积
local function build_combos(roots, index, acc, out, key)
  local last_index = #roots - 1
  if index > last_index then
    local copy = {}
    for i, v in ipairs(acc) do copy[i] = v end
    out[#out + 1] = copy
    return
  end
  for _, option in ipairs(up_options(roots[index], roots[index + 1], key)) do
    acc[#acc + 1] = option
    build_combos(roots, index + 1, acc, out, key)
    acc[#acc] = nil
  end
end

-- 返回：结果表, 候选总数, 上行半音数（失败时为 nil, nil, d）
local function generate_up(start_chord, target_chord, n, key)
  local d = (target_chord.pc - start_chord.pc + 12) % 12
  if d == 0 then d = 12 end

  local steps_count = n + 1
  if d < steps_count or d > 2 * steps_count then
    return nil, nil, d
  end

  local paths = {}
  decompose(d, steps_count, {}, paths)

  local scored, seen = {}, {}

  for _, path in ipairs(paths) do
    local roots = { start_chord.pc }
    for _, step in ipairs(path) do
      roots[#roots + 1] = (roots[#roots] + step) % 12
    end

    local combos = {}
    build_combos(roots, 2, {}, combos, key)

    for _, combo in ipairs(combos) do
      local chain = { start_chord }
      for index, option in ipairs(combo) do
        chain[#chain + 1] = {
          pc = roots[index + 1],
          q = option.q,
          rule = option.rule,
          weight = 0,
          sharp = option.sharp,
        }
      end
      chain[#chain + 1] = target_chord

      local tag = ""
      for _, c in ipairs(chain) do tag = tag .. c.pc .. c.q .. "|" end
      if not seen[tag] then
        seen[tag] = true

        local voicings = chain_voicings(chain)
        local cost = 0

        for _, option in ipairs(combo) do
          cost = cost + option.penalty
        end

        for i = 2, #chain do
          local step = (chain[i].pc - chain[i - 1].pc) % 12
          cost = cost + (step - 1) * 0.9   -- 全音步比半音步贵一点

          local a = copy_table(voicings[i - 1])
          local b = copy_table(voicings[i])
          table.sort(a)
          table.sort(b)
          for k = 1, math.min(#a, #b) do
            cost = cost + math.abs(a[k] - b[k]) * 0.08
          end
        end

        -- 连着两个减七会显得很飘
        for i = 3, #chain do
          if chain[i].q == "dim7" and chain[i - 1].q == "dim7" then
            cost = cost + 1.2
          end
        end

        -- 最后一步用半音解决最好
        local last = chain[#chain - 1]
        if last then
          local last_step = (target_chord.pc - last.pc + 12) % 12
          if last_step == 1 then
            if last.q == "dim7" then
              cost = cost - 0.9
            elseif last.q == "dom7" then
              cost = cost - 0.5
            end
          end
        end

        scored[#scored + 1] = {
          chain = chain,
          voicings = voicings,
          cost = cost,
          rules = chain_rules(chain),
        }
      end
    end
  end

  table.sort(scored, function(a, b) return a.cost < b.cost end)

  -- 同一条低音路径只把最优的一条排在前面，避免前几条全是同一个模子
  local ordered = {}
  local taken = {}
  local per_path = {}
  for i, item in ipairs(scored) do
    local path_key = ""
    for _, c in ipairs(item.chain) do path_key = path_key .. c.pc .. "," end
    if not per_path[path_key] then
      per_path[path_key] = true
      ordered[#ordered + 1] = item
      taken[i] = true
    end
  end
  for i, item in ipairs(scored) do
    if not taken[i] then ordered[#ordered + 1] = item end
  end

  return ordered, #scored, d
end

----------------------------------------------------------------------
-- 9. 试听
----------------------------------------------------------------------

local active_notes = {}
local queue = {}
local next_time = 0

local function panic()
  for _, p in ipairs(active_notes) do
    reaper.StuffMIDIMessage(0, 0x80, p, 0)
  end
  reaper.StuffMIDIMessage(0, 0xB0, 120, 0)
  reaper.StuffMIDIMessage(0, 0xB0, 123, 0)
  active_notes = {}
  queue = {}
end

local function stop_current()
  for _, p in ipairs(active_notes) do
    reaper.StuffMIDIMessage(0, 0x80, p, 0)
  end
  active_notes = {}
end

local function play_voicing(notes, duration)
  stop_current()
  for _, p in ipairs(notes) do
    reaper.StuffMIDIMessage(0, 0x90, math.floor(p), 85)
    active_notes[#active_notes + 1] = math.floor(p)
  end
  queue = {}
  next_time = reaper.time_precise() + duration
end

local function play_chain(voicings)
  stop_current()
  queue = {}
  for i, v in ipairs(voicings) do
    local onset = reaper.time_precise() + (i - 1) * 1.0
    queue[#queue + 1] = { notes = v, at = onset, off = onset + 0.95 }
  end
  next_time = 0
end

local function update_playback()
  local now = reaper.time_precise()

  -- 单和弦 / 链中每一步到达 off 时间后收音（包括下一步之前的间隙）
  if #active_notes > 0 and now >= next_time then
    stop_current()
  end

  while #queue > 0 and now >= queue[1].at do
    local step = table.remove(queue, 1)
    stop_current()
    for _, p in ipairs(step.notes) do
      reaper.StuffMIDIMessage(0, 0x90, math.floor(p), 85)
      active_notes[#active_notes + 1] = math.floor(p)
    end
    next_time = step.off
  end
end

----------------------------------------------------------------------
-- 10. 界面
----------------------------------------------------------------------

local ctx = reaper.ImGui_CreateContext("Arnie Berle 和声引擎 v" .. VERSION)

local KEYS = {}
for pc = 0, 11 do
  KEYS[#KEYS + 1] = { label = SHARP_NAMES[pc + 1] .. " 大调", pc = pc, minor = false }
end
for pc = 0, 11 do
  KEYS[#KEYS + 1] = { label = SHARP_NAMES[pc + 1] .. " 小调", pc = pc, minor = true }
end
KEYS[#KEYS + 1] = { label = "自动（按目标和弦判定）", pc = nil, minor = nil }

local N_CHOICES = { 1, 2, 3, 4 }
local LIMIT_CHOICES = { 3, 5, 10, 20 }
local DIRECTION_CHOICES = {
  { value = "auto", label = "自动" },
  { value = "up",   label = "上行阶梯" },
  { value = "down", label = "下行循环" },
}

local state = {
  key_index = #KEYS,
  start_text = "G",
  target_text = "Cm",
  n = 1,
  limit = 5,
  direction = "auto",
  results = {},
  total = 0,
  error = "",
  info = "",
  autofit = true,
  page = 1,
}

local function infer_key(target_chord)
  local minor_q = { min = true, min7 = true, m7b5 = true, dim = true, dim7 = true, mmaj7 = true }
  return { pc = target_chord.pc, minor = minor_q[target_chord.q] == true }
end

local function do_generate()
  state.error = ""
  state.info = ""
  state.results = {}
  state.total = 0

  local start_chord, err1 = parse_chord(state.start_text)
  if not start_chord then state.error = "起始和弦：" .. err1 return end

  local target_chord, err2 = parse_chord(state.target_text)
  if not target_chord then state.error = "目标和弦：" .. err2 return end

  local key_choice = KEYS[state.key_index]
  local key
  if key_choice.pc then
    key = { pc = key_choice.pc, minor = key_choice.minor }
  else
    key = infer_key(target_chord)
  end

  local results, total

  if state.direction == "up" then
    local up_results, up_total, distance = generate_up(start_chord, target_chord, state.n, key)
    if up_results then
      results, total = up_results, up_total
      state.info = string.format("上行阶梯：%d 个半音分成 %d 步，共 %d 条候选",
        distance, state.n + 1, total)
    else
      results, total = generate(start_chord, target_chord, state.n, key, "auto")
      state.info = string.format(
        "从 %s 到 %s 上行 %d 个半音，分成 %d 步时每步会超过 2 个半音，做不出阶梯，已改用自动模式（%d 条候选）",
        state.start_text, state.target_text, distance or 0, state.n + 1, total)
    end
  else
    results, total = generate(start_chord, target_chord, state.n, key, state.direction)
    state.info = string.format("生成 %d 条候选，评分前 %d 条，可翻页查看", total, #results)
  end

  state.results = results
  state.total = total
  state.key = key
  state.page = 1
  state.autofit = true     -- 下一帧按新内容重新适配窗口大小
end

local function loop()
  update_playback()

  -- 生成后让窗口按内容自动调整：宽/高设 0 表示自动适配，
  -- 再用约束把尺寸压在合理范围内，超出部分 ImGui 会自动出现滚动条。
  if state.autofit then
    reaper.ImGui_SetNextWindowSize(ctx, 0, 0, reaper.ImGui_Cond_Always())
    reaper.ImGui_SetNextWindowSizeConstraints(ctx, 620, 0, 1600, 900)
    state.autofit = false
  end

  local visible, open = reaper.ImGui_Begin(ctx, "Arnie Berle 和声引擎 v" .. VERSION, true)
  if visible then
    reaper.ImGui_SetNextItemWidth(ctx, 220)
    if reaper.ImGui_BeginCombo(ctx, "调性", KEYS[state.key_index].label) then
      for i, k in ipairs(KEYS) do
        if reaper.ImGui_Selectable(ctx, k.label, i == state.key_index) then
          state.key_index = i
        end
      end
      reaper.ImGui_EndCombo(ctx)
    end

    reaper.ImGui_SetNextItemWidth(ctx, 120)
    local changed_start, new_start = reaper.ImGui_InputText(ctx, "起始和弦", state.start_text)
    if changed_start then state.start_text = new_start end

    reaper.ImGui_SetNextItemWidth(ctx, 120)
    local changed_target, new_target = reaper.ImGui_InputText(ctx, "目标和弦", state.target_text)
    if changed_target then state.target_text = new_target end

    -- 单选按钮：点一下即选，不用拖动
    reaper.ImGui_Text(ctx, "经过和弦")
    for _, value in ipairs(N_CHOICES) do
      reaper.ImGui_SameLine(ctx)
      if reaper.ImGui_RadioButton(ctx, tostring(value) .. "##n", state.n == value) then
        state.n = value
      end
    end

    reaper.ImGui_Text(ctx, "每页条数")
    for _, value in ipairs(LIMIT_CHOICES) do
      reaper.ImGui_SameLine(ctx)
      if reaper.ImGui_RadioButton(ctx, tostring(value) .. "##limit", state.limit == value) then
        state.limit = value
      end
    end

    reaper.ImGui_Text(ctx, "方向")
    for _, option in ipairs(DIRECTION_CHOICES) do
      reaper.ImGui_SameLine(ctx)
      if reaper.ImGui_RadioButton(ctx, option.label .. "##dir", state.direction == option.value) then
        state.direction = option.value
      end
    end

    if reaper.ImGui_Button(ctx, "生成") then
      -- 生成过程出错也不能让脚本中断，否则这一帧的 End 就漏掉了
      local ok, err = pcall(do_generate)
      if not ok then
        state.error = "生成出错：" .. tostring(err)
      end
    end

    if state.error ~= "" then
      reaper.ImGui_TextWrapped(ctx, "错误：" .. state.error)
    elseif state.info ~= "" then
      reaper.ImGui_Text(ctx, state.info)
    end

    reaper.ImGui_Separator(ctx)
    reaper.ImGui_Text(ctx, "括号里的是可省略音（书中原则：3 音、7 音必须保留，5 音可省）")
    reaper.ImGui_Text(ctx, "左键和弦＝试听，右键和弦＝到 all-guitar-chords.com 查指法")

    -- 分页：显示条数 = 每页条数
    local per_page = state.limit
    local pages = math.max(1, math.ceil(#state.results / per_page))
    if state.page > pages then state.page = pages end
    local first = (state.page - 1) * per_page + 1
    local last = math.min(#state.results, first + per_page - 1)

    for index = first, last do
      local item = state.results[index]
      local chain = item.chain

      -- 只保留播放图标，链名由后面的和弦按钮表达
      if reaper.ImGui_Button(ctx, "▶##play" .. index) then
        play_chain(item.voicings)
      end

      for ci, chord in ipairs(chain) do
        reaper.ImGui_SameLine(ctx)
        if ci > 1 then
          reaper.ImGui_Text(ctx, "→")
          reaper.ImGui_SameLine(ctx)
        end
        -- 和弦名和组成音放在同一个按钮里（两行），这样永远对齐，
        -- 点按钮任意位置都能单独试听这个和弦。
        local label = string.format("%s (%s)\n%s##%d_%d",
          chord_name(chord, state.key),
          roman_of(chord, state.key),
          chord_notes_text(chord, state.key),
          index, ci)
        local clicked = reaper.ImGui_Button(ctx, label)
        local right_clicked = reaper.ImGui_IsItemClicked(ctx, reaper.ImGui_MouseButton_Right())
        if clicked then
          play_voicing(item.voicings[ci], 1.0)
        end
        if right_clicked then
          open_url(chord_site_url(chord))   -- 右键：到网站查这个和弦的指法
        end
      end

      if item.rules and item.rules ~= "" then
        reaper.ImGui_Text(ctx, "   规则：" .. item.rules)
      end
      reaper.ImGui_Text(ctx, string.format("   #%d  评分 %.2f", index, item.cost))
      reaper.ImGui_Spacing(ctx)
    end

    -- 翻页
    if pages > 1 then
      reaper.ImGui_Separator(ctx)
      if reaper.ImGui_Button(ctx, "◀ 上一页##prev") and state.page > 1 then
        state.page = state.page - 1
      end
      reaper.ImGui_SameLine(ctx)
      reaper.ImGui_Text(ctx, string.format("第 %d / %d 页　（共 %d 条）",
        state.page, pages, #state.results))
      reaper.ImGui_SameLine(ctx)
      if reaper.ImGui_Button(ctx, "下一页 ▶##next") and state.page < pages then
        state.page = state.page + 1
      end
    end

    -- ReaImGui 的要求：End 必须和 Begin 成对，且只在窗口可见时调用。
    -- 窗口被折叠或关闭时，内部已经收尾，再调 End 就会报
    -- "Calling End() too many times!"。
    reaper.ImGui_End(ctx)
  end

  if open then
    reaper.defer(loop)
  else
    panic()
  end
end

reaper.atexit(panic)
reaper.defer(loop)

-- 离线测试入口：只有宿主主动设置 ARNIE_TEST_HOOK 时才会填值，
-- 在 REAPER 里正常运行不会触发。
if rawget(_G, "ARNIE_TEST_HOOK") ~= nil then
  _G.ARNIE_TEST_HOOK = {
    parse_chord = parse_chord,
    parse_note_name = parse_note_name,
    roman_of = roman_of,
    chord_name = chord_name,
    generate = generate,
    generate_up = generate_up,
    chord_site_url = chord_site_url,
    voice_chord = voice_chord,
    QUALITY = QUALITY,
  }
end
