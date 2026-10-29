-- @description MIDI Notation Sanitizer - MIDI记谱清洗器
-- @version 2.2.1
-- @author futurewy
-- @about
--   Quantize selected MIDI items for notation using the native gfx options panel.
--   Supports polyphonic/monophonic cleanup and optional copies on new tracks.
--   Normalizes retained velocities to 100; removes CC-class events except pitch bend.
--   Text, lyrics and SysEx are preserved. No extensions required.
-- @changelog
--   Abort on failed note reads before cleanup; reliably write fractional-PPQ rounding.

--[[
MIDI Notation Sanitizer 2.2 -- REAPER / Lua / no extensions required
复音 / 单音；纯 gfx 选项界面；项目绝对网格；记谱优先。
先按原始力度和时值删除误触，再把保留音符力度设为 100。
清除 MIDI CC 类事件（控制器、触后、程序切换），只保留弯音。
保留文本、歌词和 SysEx。复制模式不改原 Item；单次 Undo 撤销。
注意：低力度不一定是误触。默认只删力度 <=5，可在下拉菜单关闭。
极短音清理默认关闭，以免删除真实装饰音。
]]

local SCRIPT_NAME  = "MIDI Notation Sanitizer"
local EXT_SECTION  = "MIDI_Notation_Sanitizer"
local PROJ         = 0
local PPQ_FALLBACK = 960


--==============================================================================
-- 一、通用工具
--==============================================================================

local function showMsg(text)
  reaper.ShowMessageBox(text, SCRIPT_NAME, 0)
end


-- 取整到整数 tick（REAPER 内部 PPQ 是浮点，写回前取整更干净）
local function iround(v)
  return math.floor(v + 0.5)
end

--==============================================================================
-- 二、时间 / QN / PPQ 换算
--     统一在 QN（四分音符）域里算：
--     1/16 音符恒等于 0.25 QN，与速度、拍号变化无关。
--==============================================================================

local function timeToQN(t)  return reaper.TimeMap2_timeToQN(PROJ, t) end
local function qnToTime(q)  return reaper.TimeMap2_QNToTime(PROJ, q) end

local function ppqToQN(take, ppq)
  return timeToQN(reaper.MIDI_GetProjTimeFromPPQPos(take, ppq))
end

local function qnToPPQ(take, qn)
  return reaper.MIDI_GetPPQPosFromProjTime(take, qnToTime(qn))
end

local function snapQN(qn, grid)
  if grid <= 0 then return qn end
  return math.floor(qn / grid + 0.5) * grid
end

-- 一个四分音符对应多少 tick
local function getPPQperQN(take)
  local p0 = reaper.MIDI_GetPPQPosFromProjTime(take, qnToTime(0.0))
  local p1 = reaper.MIDI_GetPPQPosFromProjTime(take, qnToTime(1.0))
  local d = p1 - p0
  if not d or d <= 0 then return PPQ_FALLBACK end
  return d
end

--==============================================================================
-- 三、读取 / 写回音符
--==============================================================================

local function readNotes(take)
  local notes = {}
  local counted, notecnt = reaper.MIDI_CountEvts(take)
  if not counted or not notecnt then error("无法统计音符。") end
  for i = 0, notecnt - 1 do
    local ret, sel, mute, s, e, ch, pitch, vel = reaper.MIDI_GetNote(take, i)
    if not ret then error("无法读取音符。") end
    if ret then
      notes[#notes + 1] = {
        idx     = i,
        sel     = sel,
        mute    = mute,
        s       = s,
        e       = e,
        ch      = ch,
        pitch   = pitch,
        vel     = vel,
        sq      = 0.0,
        eq      = 0.0,
        del     = false,
        changed = false,
      }
    end
  end
  return notes
end

-- 把 QN 结果换算回 tick，写进 n.s / n.e
local function writeBack(take, notes)
  local moved = 0
  for _, n in ipairs(notes) do
    if not n.del then
      local ns = iround(qnToPPQ(take, n.sq))
      local ne = iround(qnToPPQ(take, n.eq))
      if ne <= ns then ne = ns + 1 end
      if ns ~= n.s or ne ~= n.e then
        n.changed = true
        moved = moved + 1
      end
      n.s, n.e = ns, ne
    end
  end
  return moved
end

-- 写回前最后的整理：
--   1) 单音模式：按 MIDI 通道裁切拖尾
--   2) 所有模式：同音高（同通道）的拖尾裁切 + 完全重复音去重
local function postProcess(notes, mode)
  if mode == 2 then
    -- 相同起点的音保留；它们的尾音均不得越过本通道下一组起点。
    local channels = {}
    for _, n in ipairs(notes) do
      if not n.del then
        channels[n.ch] = channels[n.ch] or {}
        table.insert(channels[n.ch], n)
      end
    end
    for _, list in pairs(channels) do
      table.sort(list, function(a,b) return a.s < b.s end)
      local i = 1
      while i <= #list do
        local j = i + 1
        while j <= #list and list[j].s == list[i].s do j = j + 1 end
        if j <= #list then
          for k = i, j - 1 do
            if list[k].e > list[j].s then
              list[k].e = list[j].s
              list[k].changed = true
            end
          end
        end
        i = j
      end
    end
  end

  table.sort(notes, function(a, b)
    if a.pitch ~= b.pitch then return a.pitch < b.pitch end
    if a.ch ~= b.ch then return a.ch < b.ch end
    if a.s ~= b.s then return a.s < b.s end
    return a.e < b.e
  end)

  local last = nil
  for _, n in ipairs(notes) do
    if not n.del then
      if last and last.pitch == n.pitch and last.ch == n.ch then
        if n.s <= last.s then
          -- 量化后完全撞在一起：只留长的那一个
          if (n.e - n.s) > (last.e - last.s) then
            last.del = true
            last = n
          else
            n.del = true
          end
        elseif n.s < last.e then
          local cut = n.s
          if cut <= last.s then
            -- 连 1 tick 的缝都挤不出来：合并成一个
            if (n.e - n.s) > (last.e - last.s) then
              n.s = last.s
              last.del = true
              last = n
            else
              last.e = math.max(last.e, n.e)
              last.changed = true
              n.del = true
            end
          else
            last.e = cut
            last.changed = true
            last = n
          end
        else
          last = n
        end
      else
        last = n
      end
    end
  end
end

local function applyNotes(take, notes)
  local changed, deleted = 0, 0
  for _, n in ipairs(notes) do
    if n.del then
      deleted = deleted + 1
    elseif n.changed then
      if not reaper.MIDI_SetNote(take, n.idx, n.sel, n.mute, n.s, n.e, n.ch, n.pitch, n.vel, true) then
        error("写入音符失败。")
      end
      changed = changed + 1
    end
  end

  -- 删除必须从后往前，否则索引会错位
  local dels = {}
  for _, n in ipairs(notes) do
    if n.del then dels[#dels + 1] = n.idx end
  end
  table.sort(dels, function(a, b) return a > b end)
  for _, i in ipairs(dels) do
    if not reaper.MIDI_DeleteNote(take, i) then error("删除音符失败。") end
  end
  return changed, deleted
end

--==============================================================================
-- 四、三种清洗算法
--==============================================================================

-- 把同一声部里起点相差极小的音归成一个“和弦簇”，
-- 强制锚定到同一个网格点 —— 这就是“和弦对齐”。
-- windowQN 内部取 min(1/32 音符, 网格/2)，强制量化仍可能改变快速分解和弦；请选适当网格。
local function alignChordStarts(notes, grid, windowQN)
  local byChan = {}
  for _, n in ipairs(notes) do
    local list = byChan[n.ch]
    if not list then
      list = {}
      byChan[n.ch] = list
    end
    list[#list + 1] = n
  end

  for _, list in pairs(byChan) do
    table.sort(list, function(a, b) return a.sq < b.sq end)
    local i = 1
    while i <= #list do
      local anchor = list[i].sq
      local j = i
      local starts = {}
      while j <= #list and (list[j].sq - anchor) <= windowQN do
        starts[#starts + 1] = list[j].sq
        j = j + 1
      end
      table.sort(starts)
      local med = starts[math.floor((#starts + 1) / 2)]
      local q = snapQN(med, grid)
      for k = i, j - 1 do
        list[k].sq = q
      end
      i = j
    end
  end
end

-- 量化后如果终点塌到起点上，保留原始时值（至少 1 tick），
-- 绝不把 5 tick 的碎音硬撑成一个完整网格
local MIN_QN = 1.0 / PPQ_FALLBACK
local function fixLen(n)
  if n.eq <= n.sq then
    n.eq = n.sq + math.max(n.durQN or 0, MIN_QN)
  end
end

-- 同一和弦（同起点同通道）里“释放时间相近”的音，统一成一个时值。
-- 否则实录和弦的每个音会被量化到不同网格线，谱面上变成几个长短不一的声部。
-- 0.2 QN ≈ 1/5 拍（120BPM 下约 100ms），只合并听感上“一起放掉”的音。
local CHORD_END_WINDOW = 0.2

-- 短于 1/64 音符的碎片不参与“和弦时值投票”，否则它会把自己那一点长度
-- 摊给整个和弦（例如 5 tick 的误触把 16 分音符压成 5 tick）
local FRAGMENT_QN = 0.0625

local function unifyChordEnds(notes)
  local groups = {}
  for _, n in ipairs(notes) do
    local key = string.format("%.6f|%d", n.sq, n.ch)
    local g = groups[key]
    if not g then
      g = {}
      groups[key] = g
    end
    g[#g + 1] = n
  end

  for _, grp in pairs(groups) do
    local real = {}
    local mn, mx = math.huge, -math.huge
    for _, n in ipairs(grp) do
      if n.durQN >= FRAGMENT_QN then
        real[#real + 1] = n
        if n.eq < mn then mn = n.eq end
        if n.eq > mx then mx = n.eq end
      end
    end
    if #real > 1 and (mx - mn) <= CHORD_END_WINDOW then
      local ends = {}
      for _, n in ipairs(real) do ends[#ends + 1] = n.eq end
      table.sort(ends)
      local q = ends[math.floor((#ends + 1) / 2)]
      for _, n in ipairs(real) do n.eq = q end
    end
  end
end

-- 模式一：复音
local function modePoly(notes, grid, windowQN)
  alignChordStarts(notes, grid, windowQN)
  unifyChordEnds(notes)

  for _, n in ipairs(notes) do
    n.eq = snapQN(n.eq, grid)
    fixLen(n)
  end
end

-- 单音：每个通道单独整理为单声部
local function modeMono(notes, grid)
  for _, n in ipairs(notes) do
    if not n.del then
      n.sq = snapQN(n.sq, grid)
      n.eq = snapQN(n.eq, grid)
      fixLen(n)
    end
  end
end

--==============================================================================
-- 五、单个 Take 的处理入口
--==============================================================================

local function sanitizeTake(take, cfg)
  local notes = readNotes(take)


  local ppqPerQN = getPPQperQN(take)
  MIN_QN = 1.0 / ppqPerQN
  for _, n in ipairs(notes) do
    n.sq = ppqToQN(take, n.s)
    n.eq = ppqToQN(take, n.e)
    n.durQN = n.eq - n.sq   -- 原始时值，量化塌缩时用来兜底
  end

  for _, n in ipairs(notes) do
    if (cfg.weakVelocity > 0 and n.vel <= cfg.weakVelocity) or
       (cfg.thresholdQN > 0 and n.durQN < cfg.thresholdQN) then
      n.del = true
    end
  end
  local survivors = {}
  for _, n in ipairs(notes) do
    if not n.del then survivors[#survivors+1] = n end
  end
  local grid = cfg.gridQN
  local windowQN = math.min(0.125, grid * 0.5)

  local changed, deleted, removedCC = 0, 0, 0
  reaper.MIDI_DisableSort(take)
  local ok, err = xpcall(function()
    if cfg.mode == 1 then
      modePoly(survivors, grid, windowQN)
    else
      modeMono(survivors, grid)
    end
    writeBack(take, notes)
    postProcess(notes, cfg.mode)
    for _, n in ipairs(notes) do
      if not n.del and n.vel ~= 100 then
        n.vel = 100
        n.changed = true
      end
    end
    changed, deleted = applyNotes(take, notes)
    local counted, _, ccCount = reaper.MIDI_CountEvts(take)
    if not counted then error("无法统计控制器事件。") end
    for i = ccCount - 1, 0, -1 do
      local got, _, _, _, status = reaper.MIDI_GetCC(take, i)
      if not got then error("无法读取控制器事件。") end
      if (status & 0xF0) ~= 0xE0 then
        if not reaper.MIDI_DeleteCC(take, i) then error("无法删除控制器事件。") end
        removedCC = removedCC + 1
      end
    end
  end, debug.traceback)
  reaper.MIDI_Sort(take)
  if not ok then error(err, 0) end
  return changed, deleted, #notes, removedCC
end

--==============================================================================
-- 六、“复制到新轨再清洗”
--==============================================================================

local function createDestTrack(sourceTrack)
  local idx = reaper.CountTracks(PROJ)
  reaper.InsertTrackAtIndex(idx, true)
  local track = reaper.GetTrack(PROJ, idx)
  if not track then error("无法创建目标轨道。") end
  local _, name = reaper.GetTrackName(sourceTrack)
  reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "[Notation] " .. (name or "MIDI"), true)
  return track
end

-- CreateNewMIDIItemInProj 返回 Item，Take 必须通过 GetActiveTake 获取。
-- 复制所有原始事件（包括 CC、弯音、文本和 SysEx），只换算事件位置，
-- 保留事件消息和 flags；不移动新 Item，也不改变原始 Item。
local function copyItemTo(item, srcTake, destTrack)
  local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
  local ok, buf = reaper.MIDI_GetAllEvts(srcTake, "")
  if not ok or type(buf) ~= "string" then
    error("无法读取源 MIDI 事件，已中止复制。", 0)
  end
  local newItem = reaper.CreateNewMIDIItemInProj(destTrack, pos, pos + len, false)
  if not newItem then error("无法创建目标 MIDI Item。", 0) end
  local newTake = reaper.GetActiveTake(newItem)
  local success, failure = pcall(function()
    if not newTake or not reaper.TakeIsMIDI(newTake) then
      error("新 Item 没有有效的 MIDI Take。", 0)
    end
    local records, offset, srcPPQ, dstPPQ = {}, 1, 0, 0
    while offset <= #buf do
      local delta, flags, message
      delta, flags, message, offset = string.unpack("i4Bs4", buf, offset)
      srcPPQ = srcPPQ + delta
      local time = reaper.MIDI_GetProjTimeFromPPQPos(srcTake, srcPPQ)
      local nextPPQ = iround(reaper.MIDI_GetPPQPosFromProjTime(newTake, time))
      records[#records + 1] = string.pack("i4Bs4", nextPPQ - dstPPQ, flags, message)
      dstPPQ = nextPPQ
    end
    reaper.MIDI_DisableSort(newTake)
    local written, writeError = pcall(function()
      if not reaper.MIDI_SetAllEvts(newTake, table.concat(records)) then
        error("写入目标 MIDI 事件失败。", 0)
      end
    end)
    reaper.MIDI_Sort(newTake)
    if not written then error(writeError, 0) end
    local srcOK, srcNotes = reaper.MIDI_CountEvts(srcTake)
    local dstOK, dstNotes = reaper.MIDI_CountEvts(newTake)
    if not srcOK or not dstOK or srcNotes ~= dstNotes then
      error("复制后音符数量不一致：源=" .. tostring(srcNotes) ..
        "，目标=" .. tostring(dstNotes), 0)
    end
    reaper.SetMediaItemInfo_Value(newItem, "B_MUTE",
      reaper.GetMediaItemInfo_Value(item, "B_MUTE"))
    reaper.UpdateItemInProject(newItem)
  end)
  if not success then
    reaper.DeleteTrackMediaItem(destTrack, newItem)
    error("复制 MIDI Item 失败：" .. tostring(failure) ..
      "\n本次失败的空 Item 已移除；其他已完成操作可用 Ctrl+Z 撤销。", 0)
  end
  return { item = newItem, take = newTake }
end

--==============================================================================
-- 七、参数输入
--==============================================================================

-- REAPER 原生 gfx 单选按钮：所有选项平铺显示，一次点击直接选择。
local optionRows = {
  {label="清洗模式", hint="复音保留和弦；单音整理旋律", key="mode", default=1,
    choices={{"复音",1},{"单音",2}}},
  {label="最小节奏单位", hint="数字代表几分音符", key="gridDenominator", default=3,
    choices={{"4",4},{"8",8},{"16",16},{"32",32}}},
  {label="三连音", hint="应用于上面选定的节奏单位", key="triplet", default=2,
    choices={{"打开",true},{"关闭",false}}},
  {label="删除低力度音", hint="打开后删除力度 1–5 的音符", key="weakVelocity", default=1,
    choices={{"打开",5},{"关闭",0}}},
  {label="清除极短音", hint="打开后删除短于 1/128 音符的音", key="thresholdQN", default=2,
    choices={{"打开",1/32},{"关闭",0}}},
  {label="保留原始演奏", hint="打开则另建副本；关闭则直接修改", key="copy", default=1,
    choices={{"打开",true},{"关闭",false}}}
}

local function readOptionIndices()
  local indices = {}
  for i,row in ipairs(optionRows) do
    local saved = tonumber(reaper.GetExtState(EXT_SECTION,"ui_v3_"..row.key))
    if not saved or saved % 1 ~= 0 or saved < 1 or saved > #row.choices then saved=row.default end
    indices[i]=saved
  end
  return indices
end

local function configFromOptions(indices)
  local cfg={}
  for i,row in ipairs(optionRows) do
    cfg[row.key]=row.choices[indices[i]][2]
    reaper.SetExtState(EXT_SECTION,"ui_v3_"..row.key,tostring(indices[i]),true)
  end
  cfg.gridQN=4/cfg.gridDenominator
  if cfg.triplet then cfg.gridQN=cfg.gridQN*2/3 end
  cfg.gridText="1/"..tostring(cfg.gridDenominator)..(cfg.triplet and " 三连音" or "")
  return cfg
end


--==============================================================================
-- 八、主流程
--==============================================================================

-- 按 MIDI Source 去重：池化 Item 共享同一个源，只处理一次
local function sourceKey(take)
  local src = reaper.GetMediaItemTake_Source(take)
  local guard = 0
  while src and guard < 32 do
    local parent = reaper.GetMediaSourceParent(src)
    if not parent then break end
    src = parent
    guard = guard + 1
  end
  return tostring(src)
end

local function process(cfg)
  local selected = reaper.CountSelectedMediaItems(PROJ)
  if selected == 0 then
    showMsg("请先在 Arrange View 中选中至少一个 MIDI Item。")
    return nil
  end

  local targets, seen = {}, {}
  for i = 0, selected - 1 do
    local item = reaper.GetSelectedMediaItem(PROJ, i)
    if item then
      local take = reaper.GetActiveTake(item)
      if take and reaper.TakeIsMIDI(take) then
        local key = sourceKey(take)
        if cfg.copy or not seen[key] then
          seen[key] = true
          targets[#targets + 1] = { item = item, take = take }
        end
      end
    end
  end

  if #targets == 0 then
    showMsg("选中的 Item 里没有可用的 MIDI 数据。\n请确认 Active Take 是 MIDI。")
    return nil
  end

  local stats = { items = 0, notes = 0, changed = 0, deleted = 0, copies = 0, removedCC = 0 }

  if cfg.copy then
    local tracks, newItems = {}, {}
    for _, t in ipairs(targets) do
      local sourceTrack = reaper.GetMediaItem_Track(t.item)
      if not tracks[sourceTrack] then tracks[sourceTrack] = createDestTrack(sourceTrack) end
      local c = copyItemTo(t.item, t.take, tracks[sourceTrack])
      newItems[#newItems + 1] = c
    end

    reaper.SelectAllMediaItems(PROJ, false)
    for _, c in ipairs(newItems) do
      reaper.SetMediaItemSelected(c.item, true)
      local ch, dl, tot, cc = sanitizeTake(c.take, cfg)
      stats.items   = stats.items + 1
      stats.notes   = stats.notes + (tot or 0)
      stats.changed = stats.changed + (ch or 0)
      stats.deleted = stats.deleted + (dl or 0)
      stats.removedCC = stats.removedCC + (cc or 0)
    end
    stats.copies = #newItems
  else
    for _, t in ipairs(targets) do
      local ch, dl, tot, cc = sanitizeTake(t.take, cfg)
      stats.items   = stats.items + 1
      stats.notes   = stats.notes + (tot or 0)
      stats.changed = stats.changed + (ch or 0)
      stats.deleted = stats.deleted + (dl or 0)
      stats.removedCC = stats.removedCC + (cc or 0)
    end
  end

  return stats
end

local function applyConfig(cfg)
  -- 只在点击“开始清洗”之后开启 Undo；取消/关闭窗口不会改工程。
  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)
  local ok,result=xpcall(function() return process(cfg) end,debug.traceback)
  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()
  reaper.Undo_EndBlock("MIDI Notation Sanitizer",-1)
  if not ok then
    showMsg("清洗未完成：\n"..tostring(result).."\n\n已完成的修改可用 Ctrl+Z 撤销。")
    return
  end
  if not result then return end
  showMsg(string.format(
    "清洗完成\n\n模式：%s\n节奏：%s\n处理 Item：%d\n处理前音符：%d\n修改音符：%d\n删除音符：%d\n删除 CC 类事件：%d\n\n保留音符力度已统一为 100。\n弯音保留，其他 CC 类事件已清除。\n%s\n\nCtrl+Z 可整体撤销。",
    cfg.mode==1 and "复音" or "单音",cfg.gridText,result.items,result.notes,
    result.changed,result.deleted,result.removedCC,
    cfg.copy and "副本按来源轨道分开，原 Item 未修改。" or "已直接修改选中的 MIDI 源。"))
end

local function openOptions()
  if reaper.CountSelectedMediaItems(0)==0 then
    showMsg("请先在主界面选择需要清洗的 MIDI Items。")
    return
  end
  local project=reaper.EnumProjects(-1,"")
  local indices=readOptionIndices()
  gfx.init(SCRIPT_NAME.." 2.2",940,700,0)
  local previousDown=false
  local function loop()
    local ok,err=xpcall(function()
      local char=gfx.getchar()
      if char<0 or char==27 then gfx.quit();return end
      local down=(gfx.mouse_cap & 1)~=0
      local clicked=down and not previousDown
      previousDown=down
      -- 按统一比例缩放布局；绘制和命中检测使用相同坐标变换。
      local scale=math.max(0.1,math.min(gfx.w/940,gfx.h/700))
      local ox,oy=(gfx.w-940*scale)/2,(gfx.h-700*scale)/2
      local mx,my=(gfx.mouse_x-ox)/scale,(gfx.mouse_y-oy)/scale
      local function hit(x,y,w,h)
        return mx>=x and mx<x+w and my>=y and my<y+h
      end
      local function rect(x,y,w,h,r,g,b)
        gfx.set(r,g,b,1)
        gfx.rect(ox+x*scale,oy+y*scale,w*scale,h*scale,1)
      end
      local function text(x,y,t,size,r,g,b)
        gfx.setfont(1,"Microsoft YaHei",math.max(16,math.floor((size or 22)*scale)))
        gfx.set(r or 0.90,g or 0.93,b or 0.97,1)
        gfx.x=ox+x*scale;gfx.y=oy+y*scale
        gfx.drawstr(t)
      end
      rect(0,0,940,700,0.09,0.11,0.15)
      text(24,16,"MIDI Notation Sanitizer · 记谱清洗",26)
      text(24,52,"每组选择一项，点击圆点或选项即可。",18,0.65,0.75,0.86)
      for i,row in ipairs(optionRows) do
        local y=84+(i-1)*78
        text(24,y,row.label.."（"..row.hint.."）",22)
        for k,choice in ipairs(row.choices) do
          local width=136
          local x=24+(k-1)*(width+14)
          local cy=y+30
          local selected=indices[i]==k
          local hover=hit(x,cy,width,40)
          if selected then
            rect(x,cy,width,40,0.17,0.37,0.53)
          elseif hover then
            rect(x,cy,width,40,0.22,0.28,0.37)
          else
            rect(x,cy,width,40,0.14,0.19,0.26)
          end
          local cx,circleY=ox+(x+19)*scale,oy+(cy+20)*scale
          gfx.set(selected and 0.46 or 0.61,selected and 0.83 or 0.67,selected and 1.0 or 0.75,1)
          gfx.circle(cx,circleY,8*scale,0,1)
          if selected then gfx.circle(cx,circleY,4*scale,1,1) end
          text(x+40,cy+7,choice[1],24)
          if clicked and hover then indices[i]=k end
        end
      end
      text(24,566,"固定处理：保留音符力度 = 100；仅保留弯音，清除其他 CC。",19,0.71,0.83,0.93)
      text(24,597,"低力度也可能是轻奏；删除控制信息会改变播放效果。",18,0.89,0.74,0.49)
      rect(24,638,180,44,0.18,0.46,0.68)
      text(61,647,"开始清洗",22)
      rect(222,638,120,44,0.23,0.27,0.33)
      text(260,647,"取消",22)
      if clicked and hit(222,638,120,44) then gfx.quit();return end
      if char==13 or (clicked and hit(24,638,180,44)) then
        if reaper.EnumProjects(-1,"")~=project then
          gfx.quit();showMsg("当前工程已切换，请在目标工程重新运行脚本。");return
        end
        local cfg=configFromOptions(indices)
        gfx.quit()
        applyConfig(cfg)
        return
      end
      gfx.update()
      reaper.defer(loop)
    end,debug.traceback)
    if not ok then gfx.quit();showMsg("选项窗口出错：\n"..tostring(err)) end
  end
  loop()
end

openOptions()
