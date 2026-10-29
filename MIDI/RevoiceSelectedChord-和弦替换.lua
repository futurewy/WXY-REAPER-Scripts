-- @description 选中和弦就近替换（含分解和弦与外音）
-- @version 4.0.1
-- Optimize collision checks for large groups of overlapping existing unisons.
-- Compact target-only panel with uniform font and editable detected source.
-- Add explicit seventh-plus-ninth aliases (7add9, m7add9, maj7add9).
-- Fix: allow octave-doubled triads when converting seventh chords.
-- @author futurewy
-- @about
--   Revoice selected notes independently in each editable MIDI-editor take.
--   Native gfx chord panel, external-note strategies and collision-safe additions.
--   REAPER 6/7, Lua 5.3+. No SWS/ReaPack dependencies.
-- @changelog
--   Standardize package metadata.
--   No runtime behavior changes.

local R = reaper
local TITLE = "选中和弦就近替换"
local NAMES = {"C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"}
local ROOTS = {C=0, D=2, E=4, F=5, G=7, A=9, B=11}
local QUALITIES = {
  [""]={0,4,7}, m={0,3,7}, dim={0,3,6}, aug={0,4,8},
  ["5"]={0,7}, sus2={0,2,7}, sus4={0,5,7},
  ["6"]={0,4,7,9}, m6={0,3,7,9},
  ["7"]={0,4,7,10}, maj7={0,4,7,11}, m7={0,3,7,10},
  mMaj7={0,3,7,11}, dim7={0,3,6,9}, m7b5={0,3,6,10},
  add9={0,4,7,2}, madd9={0,3,7,2},
  ["9"]={0,4,7,10,2}, maj9={0,4,7,11,2}, m9={0,3,7,10,2},
  ["11"]={0,4,7,10,2,5}, m11={0,3,7,10,2,5},
  ["13"]={0,4,7,10,2,5,9}, m13={0,3,7,10,2,5,9},
  ["7sus4"]={0,5,7,10}, ["7b5"]={0,4,6,10},
  ["7#5"]={0,4,8,10}, ["7b9"]={0,4,7,10,1}, ["7#9"]={0,4,7,10,3},
}

-- Categorized presets share exactly the same interval data as the converter.
local GROUPS = {
  {name="三和弦 / 五度", items={
    {"", "大三和弦"}, {"m", "小三和弦"}, {"dim", "减三和弦"}, {"aug", "增三和弦"}, {"5", "五度和弦"}}},
  {name="七和弦", items={
    {"7", "属七"}, {"maj7", "大七"}, {"m7", "小七"}, {"mMaj7", "小大七"},
    {"m7b5", "半减七"}, {"dim7", "减七"},
    {"7#5", "增五属七"}, {"maj7#5", "增大七", {0,4,8,11}}}},
  {name="六和弦 / 加音（无隐含七音）", items={
    {"6", "大六"}, {"m6", "小六"}, {"6add9", "六加九", {0,4,7,9,2}},
    {"m6add9", "小六加九", {0,3,7,9,2}}, {"add9", "大三加九"}, {"madd9", "小三加九"},
    {"add11", "大三加十一", {0,4,7,5}}, {"madd11", "小三加十一", {0,3,7,5}},
    {"add#11", "大三加升十一", {0,4,7,6}}, {"addb9", "大三加降九", {0,4,7,1}},
    {"add13", "大三加十三（音级同六和弦）", {0,4,7,9}}}},
  {name="九 / 十一 / 十三（含七音）", items={
    {"9", "属九 = 7add9"}, {"maj9", "大九 = maj7add9"}, {"m9", "小九 = m7add9"},
    {"mMaj9", "小大九", {0,3,7,11,2}}, {"11", "属十一（完整叠置）"},
    {"maj11", "大十一（完整叠置）", {0,4,7,11,2,5}}, {"m11", "小十一"},
    {"13", "属十三（完整叠置）"}, {"maj13", "大十三（完整叠置）", {0,4,7,11,2,5,9}}, {"m13", "小十三"},
    {"mMaj11", "小大十一", {0,3,7,11,2,5}}, {"mMaj13", "小大十三", {0,3,7,11,2,5,9}}}},
  {name="挂留和弦（替代三音）", items={
    {"sus2", "挂二"}, {"sus4", "挂四"}, {"7sus4", "属七挂四"},
    {"7sus2", "属七挂二", {0,2,7,10}}, {"maj7sus2", "大七挂二", {0,2,7,11}},
    {"maj7sus4", "大七挂四", {0,5,7,11}}, {"9sus4", "属九挂四", {0,5,7,10,2}},
    {"13sus4", "属十三挂四", {0,5,7,10,2,9}}, {"sus4add9", "挂四加九", {0,5,7,2}}}},
  {name="属七变化音 / 组合变化", items={
    {"7b5", "属七降五"}, {"7#5", "属七升五"}, {"7b9", "属七降九"}, {"7#9", "属七升九"},
    {"7#11", "属七升十一（保留五音）", {0,4,7,10,6}},
    {"7b13", "属七降十三（保留五音）", {0,4,7,10,8}},
    {"7b9b5", "属七降九降五", {0,4,6,10,1}}, {"7b9#5", "属七降九升五", {0,4,8,10,1}},
    {"7#9b5", "属七升九降五", {0,4,6,10,3}}, {"7#9#5", "属七升九升五", {0,4,8,10,3}},
    {"7b9#11", "属七降九升十一", {0,4,7,10,1,6}},
    {"7#9#11", "属七升九升十一", {0,4,7,10,3,6}},
    {"7b9b13", "属七降九降十三", {0,4,7,10,1,8}},
    {"7#9b13", "属七升九降十三", {0,4,7,10,3,8}},
    {"7alt", "变化属七集合（非唯一配音）", {0,4,10,1,3,6,8}}}},
  {name="其他扩展 / 加音 / 省略", items={
    {"9b5", "属九降五", {0,4,6,10,2}}, {"9#5", "属九升五", {0,4,8,10,2}},
    {"9#11", "属九升十一", {0,4,7,10,2,6}}, {"9b13", "属九降十三", {0,4,7,10,2,8}},
    {"13b9", "属十三降九（省十一）", {0,4,7,10,1,9}},
    {"13#9", "属十三升九（省十一）", {0,4,7,10,3,9}},
    {"13#11", "属十三升十一", {0,4,7,10,2,6,9}},
    {"maj7#11", "大七升十一", {0,4,7,11,6}}, {"maj9#11", "大九升十一", {0,4,7,11,2,6}},
    {"maj13#11", "大十三升十一", {0,4,7,11,2,6,9}},
    {"m9b5", "小九降五", {0,3,6,10,2}}, {"dim7add9", "减七加九", {0,3,6,9,2}},
    {"7add11", "属七加十一（不含九）", {0,4,7,10,5}},
    {"m7add11", "小七加十一（不含九）", {0,3,7,10,5}},
    {"7add13", "属七加十三（不含九/十一）", {0,4,7,10,9}},
    {"no3", "大三省三（五度）", {0,7}}, {"7no3", "属七省三", {0,7,10}},
    {"7no5", "属七省五", {0,4,10}}, {"maj7no5", "大七省五", {0,4,11}},
    {"m7no5", "小七省五", {0,3,10}}, {"9no5", "属九省五", {0,4,10,2}}}}
}
for _,group in ipairs(GROUPS) do
  for _,item in ipairs(group.items) do
    if item[3] then QUALITIES[item[1]]=item[3] end
  end
end

local ALIASES = {maj="", M="", min="m", ["-"]="m", ["+"]="aug",
  sus="sus4", M7="maj7", M9="maj9", min7="m7", min9="m9",
  ["7add9"]="9", ["7(add9)"]="9",
  m7add9="m9", ["m7(add9)"]="m9", min7add9="m9",
  maj7add9="maj9", ["maj7(add9)"]="maj9", M7add9="maj9",
  ["M7(add9)"]="maj9", ["6/9"]="6add9", ["m6/9"]="m6add9",
  aug7="7#5", augMaj7="maj7#5",
  ["o"]="dim", o7="dim7", ["ø"]="m7b5", ["ø7"]="m7b5",
  ["m(maj7)"]="mMaj7", ["mM7"]="mMaj7"}
local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
local function msg(s) R.ShowMessageBox(s, TITLE, 0) end
local function parse(s)
  s = trim(s):gsub("♯", "#"):gsub("♭", "b"):gsub("%s+", "")
  local letter, accidental, suffix = s:match("^([A-Ga-g])([#b]?)(.*)$")
  if not letter then return nil, "和弦必须以 A–G 开头，例如 G、Cm、F#maj7。" end
  suffix = ALIASES[suffix] or suffix
  if suffix:find("/", 1, true) then
    return nil, "本版不支持斜线低音和弦（如 C/E）。请输入 C；低音由就近排列决定。"
  end
  suffix = ALIASES[suffix] or suffix
  local intervals = QUALITIES[suffix]
  if not intervals then return nil, "不支持的和弦后缀：" .. suffix .. "\n例如：m、7、maj7、m7、dim、sus4、add9、9、m9。" end
  local root = (ROOTS[letter:upper()] + (accidental == "#" and 1 or accidental == "b" and -1 or 0)) % 12
  local c = {root=root, suffix=suffix, rootname=letter:upper()..accidental, pcs={}, set={}, importance={}, name=letter:upper()..accidental..suffix}
  for _, d in ipairs(intervals) do
    local pc = (root+d)%12
    c.pcs[#c.pcs+1], c.set[pc] = pc, true
    c.importance[pc] = d == 0 and 3 or (d == 3 or d == 4) and 5 or (d == 10 or d == 11) and 4 or 1
  end
  table.sort(c.pcs)
  return c
end

-- Presence, not duration/onset, is used so arpeggios work like block chords.
-- This is only a suggestion: C6/Am7, inversions and passing notes are ambiguous.
local function detect(notes)
  local present, bass = {}, 128
  for _, n in ipairs(notes) do present[n.pitch%12]=true; bass=math.min(bass,n.pitch) end
  local candidates = {}
  local suffixes = {"", "m", "7", "maj7", "m7", "dim", "aug", "sus2", "sus4", "6", "m6", "m7b5", "dim7", "add9", "madd9", "9", "maj9", "m9"}
  for root=0,11 do
    for rank, suffix in ipairs(suffixes) do
      local c = assert(parse(NAMES[root+1]..suffix))
      local missing, outside = 0, 0
      for pc in pairs(present) do if not c.set[pc] then outside=outside+1 end end
      for _, pc in ipairs(c.pcs) do if not present[pc] then missing=missing+1 end end
      local score=outside*3 + missing*2 + (#c.pcs-3)*0.18 + (bass%12==root and -0.12 or 0) + rank*0.0001
      candidates[#candidates+1]={name=c.name,score=score}
    end
  end
  table.sort(candidates,function(a,b) return a.score<b.score end)
  return candidates[1].name
end

-- Dense fallback uses actual MIDI pitches, not a cyclic one-octave PC map.
-- Equal original pitches stay together, but different octaves may move differently.
local function solve_actual(source,target,notes,limit,feasible)
  local groups,bypitch,present={},{},{}
  for _,n in ipairs(notes) do
    if source.set[n.pitch%12] then
      local g=bypitch[n.pitch]
      if not g then
        g={pitch=n.pitch,weight=0,channels={}}; bypitch[n.pitch]=g
        groups[#groups+1]=g; present[n.pitch%12]=true
      end
      g.weight=g.weight+1
      local intervals=g.channels[n.channel] or {}; g.channels[n.channel]=intervals
      intervals[#intervals+1]={n.startppq,n.endppq}
    end
  end
  table.sort(groups,function(a,b) return a.pitch<b.pitch end)
  local actual_count=0
  for _ in pairs(present) do actual_count=actual_count+1 end
  local required=math.min(actual_count,#target.pcs)
  if #groups==0 then return nil,false end
  local lists,suffixcost,suffixmask={},{[#groups+1]=0},{[#groups+1]=0}
  for i,g in ipairs(groups) do
    lists[i]={}
    for q=math.max(0,g.pitch-limit),math.min(127,g.pitch+limit) do
      if target.set[q%12] then
        local d=q-g.pitch
        lists[i][#lists[i]+1]={q=q,cost=g.weight*(math.abs(d)+0.12*d*d)}
      end
    end
    table.sort(lists[i],function(a,b)
      if a.cost==b.cost then return a.q<b.q end
      return a.cost<b.cost
    end)
    if #lists[i]==0 then return nil,false end
    -- Merge existing-unison intervals before pairwise collision pruning.
    for channel,intervals in pairs(g.channels) do
      table.sort(intervals,function(a,b) return a[1]<b[1] end)
      local merged={}
      for _,v in ipairs(intervals) do
        local last=merged[#merged]
        if last and v[1]<=last[2] then last[2]=math.max(last[2],v[2])
        else merged[#merged+1]={v[1],v[2]} end
      end
      g.channels[channel]=merged
    end
  end
  for i=#groups,1,-1 do
    local mask=0
    for _,v in ipairs(lists[i]) do mask=mask | (1<<(v.q%12)) end
    suffixmask[i]=suffixmask[i+1] | mask
    suffixcost[i]=suffixcost[i+1]+lists[i][1].cost
  end
  local conflicts={}
  local function overlap(i,j)
    local key=i*128+j
    if conflicts[key]~=nil then return conflicts[key] end
    for channel,a in pairs(groups[i].channels) do
      local b=groups[j].channels[channel]
      if b then
        local x,y=1,1
        while a[x] and b[y] do
          if a[x][1]<b[y][2] and b[y][1]<a[x][2] then
            conflicts[key]=true; return true
          end
          if a[x][2]<=b[y][2] then x=x+1 else y=y+1 end
        end
      end
    end
    conflicts[key]=false; return false
  end
  -- Numeric PC entries are retained for external-note anchors and old consumers.
  local base={}
  for _,pc in ipairs(source.pcs) do
    local best
    for q=pc-12,pc+12 do
      if target.set[q%12] and (not best or math.abs(q-pc)<math.abs(best-pc)) then best=q end
    end
    base[pc]=best-pc
  end
  local best,bestscore,path=nil,math.huge,{}
  local nodes,truncated=0,false
  local function visit(i,previous,mask,count,score)
    nodes=nodes+1
    if nodes>250000 then truncated=true; return end
    if score+suffixcost[i]>=bestscore or count+(#groups-i+1)<required then return end
    local possible,available=mask | suffixmask[i],0
    for _,pc in ipairs(target.pcs) do if (possible & (1<<pc))~=0 then available=available+1 end end
    if available<required then return end
    if i>#groups then
      if count~=required then return end
      for _,pc in ipairs(target.pcs) do
        if (mask & (1<<pc))==0 then score=score+target.importance[pc]*3 end
      end
      if score<bestscore then
        local proposed={actual={}}
        for pc,d in pairs(base) do proposed[pc]=d end
        local anchored={}
        for j,g in ipairs(groups) do
          proposed.actual[g.pitch]=path[j]
          local pc=g.pitch%12
          if not anchored[pc] then proposed[pc]=path[j]-g.pitch; anchored[pc]=true end
        end
        if not feasible or feasible(proposed) then best,bestscore=proposed,score end
      end
      return
    end
    for _,v in ipairs(lists[i]) do
      if truncated then return end
      local q,ok=v.q,true
      if not previous or q>=previous then
        for j=i-1,1,-1 do
          if path[j]~=q then break end
          if overlap(i,j) then ok=false; break end
        end
        if ok then
          local bit=1<<(q%12)
          path[i]=q
          visit(i+1,q,mask | bit,count+((mask & bit)==0 and 1 or 0),score+v.cost)
        end
      end
    end
  end
  visit(1,nil,0,0,0)
  return best,truncated
end

-- Preserve successful octave-periodic maps first, then try actual-note voicing.
local function solve(source, target, notes, limit, feasible)
  local weights, bounds = {}, {}
  for _, pc in ipairs(source.pcs) do weights[pc]=0.05 end
  for _, n in ipairs(notes) do
    local pc=n.pitch%12
    if source.set[pc] then
      weights[pc]=weights[pc]+1
      local b=bounds[pc] or {lo=127,hi=0}
      b.lo=math.min(b.lo,n.pitch); b.hi=math.max(b.hi,n.pitch); bounds[pc]=b
    end
  end
  local lists = {}
  for i,pc in ipairs(source.pcs) do
    lists[i]={}
    -- Unplayed source tones are only needed to define external-note anchors.
    -- Do not let a phantom tone fail the selected notes' movement limit.
    local radius=bounds[pc] and limit or 12
    for q=pc-radius,pc+radius do
      local d=q-pc; local b=bounds[pc]
      if target.set[q%12] and (not b or (b.lo+d>=0 and b.hi+d<=127)) then
        lists[i][#lists[i]+1]={q=q, cost=weights[pc]*(math.abs(d)+0.12*d*d)}
      end
    end
    table.sort(lists[i],function(a,b)
      if a.cost==b.cost then return a.q<b.q end
      return a.cost<b.cost
    end)
  end
  local actual_count=0
  for _ in pairs(bounds) do actual_count=actual_count+1 end
  local required=math.min(actual_count,#target.pcs)
  local best, bestscore, path = nil, math.huge, {}
  local nodes,truncated=0,false
  local function visit(i,first,previous,mask,count,score)
    nodes=nodes+1
    if nodes>250000 then truncated=true; return end
    if score>=bestscore or count+(#source.pcs-i+1)<required then return end
    if i>#source.pcs then
      if count~=required then return end
      local penalty=0
      for _,pc in ipairs(target.pcs) do
        if (mask & (1<<pc))==0 then penalty=penalty+target.importance[pc]*3 end
      end
      score=score+penalty
      if score<bestscore then
        local proposed={}
        for j,pc in ipairs(source.pcs) do proposed[pc]=path[j]-pc end
        if not feasible or feasible(proposed) then
          bestscore=score; best=proposed
        end
      end
      return
    end
    for _, candidate in ipairs(lists[i]) do
      local q=candidate.q
      -- Include the octave endpoint: four voices may become a triad with
      -- octave doubling (e.g. C E G B -> D F# A D), not a unison merge.
      -- Actual overlapping same-pitch events are still checked by feasible().
      if not previous or (q>=previous and q<=first+12) then
        local bit=bounds[source.pcs[i]] and (1<<(q%12)) or 0
        local fresh=bit~=0 and (mask & bit)==0
        path[i]=q
        visit(i+1,first or q,q,mask | bit,count+(fresh and 1 or 0),score+candidate.cost)
      end
    end
  end
  visit(1,nil,nil,0,0,0)
  if not best and not truncated then return solve_actual(source,target,notes,limit,feasible) end
  return best,truncated
end

local function nearest_target(pitch,target,limit)
  local best, distance
  for q=math.max(0,pitch-limit),math.min(127,pitch+limit) do
    if target.set[q%12] and (not distance or math.abs(q-pitch)<distance) then
      best,distance=q,math.abs(q-pitch)
    end
  end
  return best
end
local function transform(notes,source,target,map,mode,limit)
  local result, external = {}, 0
  for i,n in ipairs(notes) do
    local pc=n.pitch%12; local q
    if source.set[pc] and map.actual and map.actual[n.pitch]~=nil then q=map.actual[n.pitch]
    elseif map[pc] then q=n.pitch+map[pc]
    else
      external=external+1
      if mode==3 then q=n.pitch
      elseif mode==2 then q=nearest_target(n.pitch,target,limit)
      else
        -- Anchor at nearest source chord tone; tie prefers the lower anchor.
        -- Preserve signed chromatic interval, NOT inferred scale degree/function.
        local anchor, offset
        for d=-6,6 do
          local apc=(pc-d)%12
          if source.set[apc] and (not offset or math.abs(d)<math.abs(offset) or (math.abs(d)==math.abs(offset) and d>offset)) then
            anchor,offset=apc,d
          end
        end
        q=n.pitch+map[anchor]
      end
    end
    if not q or q<0 or q>127 or math.abs(q-n.pitch)>limit then
      return nil, "有音符无法在移动上限内转换，或会超出 MIDI 0–127。\n请增大移动上限、换一种外音策略，或缩小选择范围。"
    end
    result[i]=q
  end
  return result, external
end

local function has_collision(notes,all,pitches)
  -- Refuse newly-created same-channel, overlapping unisons, including collisions
  -- with unselected notes. Existing unisons are allowed if they move together.
  local selected_lookup={}
  for i,n in ipairs(notes) do selected_lookup[n.index]=pitches[i] end
  local groups={}
  for _,n in ipairs(all) do
    local q=selected_lookup[n.index] or n.pitch
    local key=n.channel*128+q
    groups[key]=groups[key] or {}; groups[key][#groups[key]+1]=n
  end
  for _,group in pairs(groups) do
    table.sort(group,function(a,b) return a.startppq<b.startppq end)
    -- Keep the latest note-off per ORIGINAL pitch, rather than every active
    -- note. Thousands of overlapping existing unisons now use one entry.
    -- Different original pitches converging onto this final pitch are unsafe.
    local latest_end={}
    for _,n in ipairs(group) do
      for original_pitch,ending in pairs(latest_end) do
        if original_pitch~=n.pitch and ending>n.startppq then return true end
      end
      latest_end[n.pitch]=math.max(latest_end[n.pitch] or -math.huge,n.endppq)
    end
  end
  return false
end


-- Native gfx panel: no extension, popup menus or chord-name typing required.
local SPELLINGS={"C","C#","Db","D","D#","Eb","E","F","F#","Gb","G","G#","Ab","A","A#","Bb","B"}
local DEGREE_NAMES={"1", "b2 / b9", "2 / 9", "b3 / #9", "3", "4 / 11", "b5 / #11", "5", "#5 / b13", "6 / 13 / bb7", "b7", "7"}
local function pitch_summary(c)
  local out={}
  for _,pc in ipairs(c.pcs) do out[#out+1]=NAMES[pc+1] end
  return table.concat(out," ")
end
local function custom_chord(rootname, intervals)
  local root=assert(parse(rootname)).root
  local c={root=root,rootname=rootname,suffix="custom",name=rootname.."[自定义音级]",pcs={},set={},importance={},custom=true}
  for d=0,11 do
    if intervals[d] then
      local pc=(root+d)%12
      c.pcs[#c.pcs+1]=pc; c.set[pc]=true
      c.importance[pc]=d==0 and 3 or (d==3 or d==4) and 5 or (d==10 or d==11) and 4 or 1
    end
  end
  table.sort(c.pcs)
  return c
end
-- Compact one-page panel: editable detected source, one target selector, advanced movement cap.
local function panel_model(guess)
  local state={source=assert(parse(guess)),detected=guess,source_text="",target=assert(parse("C")),mode=1,limit=7,advanced=false,focus=false}
  local function set_root(name)
    local c=state.target
    if c.custom then
      local ints={}; for pc in pairs(c.set) do ints[(pc-c.root)%12]=true end
      state.target=custom_chord(name,ints)
    else state.target=assert(parse(name..c.suffix)) end
  end
  local function degree(d)
    local c=state.target; local ints={}
    for pc in pairs(c.set) do ints[(pc-c.root)%12]=true end
    ints[d]=not ints[d]
    local changed=custom_chord(c.rootname,ints)
    if #changed.pcs>0 then state.target=changed else state.status="至少保留一个目标音级。" end
  end
  local function commit_source()
    local c,err=parse(trim(state.source_text)=="" and state.detected or state.source_text)
    if c then state.source=c; state.source_error=nil; state.status="原和弦已更新："..c.name
    else state.source_error=err or "无法识别该和弦符号。" end
  end
  local function controls()
    local out={}
    local function add(id,label,x,y,w,h,on,fn,tip)
      out[#out+1]={id=id,label=label,x=x,y=y,w=w,h=h,on=on,click=fn,tip=tip}
    end
    add("source.input",state.source_text,400,16,190,36,state.focus,function() state.focus=true end,"自动检测："..guess.."；点击输入框手动修改，回车确认。")
    add("source.commit","确认",600,16,72,36,false,commit_source,"确认输入的原和弦名称")
    for i,name in ipairs(SPELLINGS) do
      add("target.root."..name,name,110+(i-1)*54,100,50,36,state.target.rootname==name,function() set_root(name) end)
    end
    local seen={};local index=0
    for _,group in ipairs(GROUPS) do
      for _,item in ipairs(group.items) do
        local suffix=item[1]
        if not seen[suffix] then
          seen[suffix]=true
          local x=12+(index%8)*128;local y=150+math.floor(index/8)*34
          add("target.type."..suffix,suffix=="" and "major" or suffix,x,y,122,30,
            state.target.suffix==suffix,
            function() state.target=assert(parse(state.target.rootname..suffix));state.status=nil end,
            (suffix=="" and "major" or suffix).."（"..item[2].."）")
          index=index+1
        end
      end
    end
    for i,label in ipairs({"相对音程","就近和弦音","保留外音"}) do
      add("mode."..i,label,110+(i-1)*154,525,148,36,state.mode==i,function() state.mode=i end)
    end
    add("advanced","高级设置",590,525,140,36,state.advanced,function() state.advanced=not state.advanced end,"移动上限：限制单个音符最多改变的半音数。默认 7 半音；脚本仍优先选择移动较小的排列。")
    if state.advanced then
      for i=1,12 do
        add("limit."..i,tostring(i),110+(i-1)*62,605,56,34,state.limit==i,function() state.limit=i end,
          "单音最大移动 "..i.." 个半音")
      end
    end
    add("apply","预览并应用",750,665,170,40,false,function() state.action="apply" end)
    add("cancel","取消",930,665,98,40,false,function() state.action="cancel" end)
    return out
  end
  return state,controls,commit_source
end

local function select_panel(guess,apply,batch_count)
  local state,controls,commit_source=panel_model(guess)
  local W,H=1040,720
  gfx.init(TITLE.." — 简洁和弦选择",1040,680,0)
  local last_down=false;local stopped=false
  local function stop() if not stopped then stopped=true;gfx.quit() end end
  if R.atexit then R.atexit(stop) end
  local function frame()
    local key=gfx.getchar()
    if key<0 or key==27 then stop();return end
    if state.focus and key>0 then
      if key==13 then commit_source();state.focus=false
      elseif key==8 then state.source_text=state.source_text:sub(1,-2);state.source_error=nil
      elseif key>=32 and key<=126 and #state.source_text<32 then state.source_text=state.source_text..string.char(key);state.source_error=nil end
    end
    local scale=math.min(gfx.w/W,gfx.h/H)
    if scale<=0 then R.defer(frame);return end
    local ox=(gfx.w-W*scale)/2;local oy=(gfx.h-H*scale)/2
    local mx=(gfx.mouse_x-ox)/scale;local my=(gfx.mouse_y-oy)/scale
    local down=(gfx.mouse_cap & 1)~=0;local pressed=down and not last_down;last_down=down
    gfx.set(0.08,0.09,0.12,1);gfx.rect(0,0,gfx.w,gfx.h,1)
    local function text(s,x,y,size,r,g,b)
      gfx.setfont(1,"Microsoft YaHei",math.max(12,math.floor(20*scale)))
      gfx.set(r or 0.93,g or 0.94,b or 0.97,1);gfx.x=ox+x*scale;gfx.y=oy+y*scale;gfx.drawstr(s)
    end
    text("原和弦：",12,23,20,0.45,0.75,1)
    text(guess,110,23,20,0.94,0.95,1)
    text("手改：",325,23,20,0.7,0.73,0.79)
    text("根音",12,108,20,0.4,0.92,0.62)
    text("目标："..state.target.name,12,67,20,0.4,0.92,0.62)
    if batch_count and batch_count>1 then text(batch_count.." item 独立识别；手改框覆盖全部",325,67,20,0.7,0.8,0.95) end


    text("外音",12,534,20)
    if state.source_error then text(state.source_error,12,570,20,1,0.45,0.38)
    elseif state.status then text(state.status,12,570,20,0.55,0.84,1) end
    if state.focus and not state.source_error then text("留空使用检测结果，Enter 确认",690,23,20,0.7,0.8,0.95) end
    local hover_tip
    for _,c in ipairs(controls()) do
      local hover=mx>=c.x and mx<c.x+c.w and my>=c.y and my<c.y+c.h
      if c.on then gfx.set(0.12,0.4,0.66,1)
      elseif hover then gfx.set(0.28,0.32,0.4,1) else gfx.set(0.16,0.18,0.23,1) end
      gfx.rect(ox+c.x*scale,oy+c.y*scale,c.w*scale,c.h*scale,1)
      local label=c.label
      if c.id=="source.input" then
        label=state.source_text:sub(-13)..(state.focus and "▏" or "")
      end
      if c.on and c.id~="source.input" then label="✓ "..label end
      text(label,c.x+5,c.y+4,20)
      if hover then hover_tip=c.tip end
      if pressed and hover then c.click();if c.id~="source.input" then state.focus=false end end
    end
    if state.advanced then text("移动上限：每个音符最多移动的半音数；12 表示最多一个八度。",12,646,20,0.74,0.78,0.84)
    elseif hover_tip and not state.source_error and not state.status then text(hover_tip,12,570,20,0.74,0.78,0.84)
    end
    gfx.update()
    if state.action=="cancel" then stop();return end
    if state.action=="apply" then
      commit_source()
      if state.source_error then state.action=nil;return R.defer(frame) end
      stop();apply(state.source,state.target,state.mode,state.limit,trim(state.source_text)~="");return
    end
    R.defer(function()local ok,err=xpcall(frame,debug.traceback);if not ok then stop();msg("面板出错，未继续修改。\n"..tostring(err)) end end)
  end
  local ok,err=xpcall(frame,debug.traceback)
  if not ok then stop();msg("面板出错，未继续修改。\n"..tostring(err)) end
end

-- Pure insertion planner: original source membership, transformed register, no MIDI writes.
local function plan_additions(notes,all,pitches,source,target)
  local donors,present,selected,selected_indices={},{},{},{}
  local earliest,latest,ending=math.huge,-math.huge,math.huge
  local center=0
  for i,n in ipairs(notes) do
    selected[n]=true
    if n.index~=nil then selected_indices[n.index]=true end
    if source.set[n.pitch%12] then
      local q=pitches[i]
      donors[#donors+1]={note=n,pitch=q}
      present[q%12]=true; center=center+q
      earliest=math.min(earliest,n.startppq)
      latest=math.max(latest,n.startppq)
      ending=math.min(ending,n.endppq)
    end
  end
  local missing={}
  for pc=0,11 do
    if target.set[pc] and not present[pc] then missing[#missing+1]=pc end
  end
  if #missing==0 then return {},nil end
  if #donors==0 then return nil,"没有选中的原和弦内音可作为补音参考。" end
  center=center/#donors
  -- Tiny PPQ tolerance accommodates floating-point onset noise, not rolled chords.
  local block=latest-earliest<=1e-7 and ending>latest
  local occupied={}
  local function occupy(n,q)
    local key=n.channel*128+q
    local group=occupied[key] or {}; occupied[key]=group
    group[#group+1]={n.startppq,n.endppq}
  end
  for i,n in ipairs(notes) do occupy(n,pitches[i]) end
  for _,n in ipairs(all) do
    if not selected[n] and not (n.index~=nil and selected_indices[n.index]) then
      occupy(n,n.pitch)
    end
  end
  local additions={}
  for _,pc in ipairs(missing) do
    local candidates={}
    -- Additions are not moved notes: search every legal octave, without a movement cap.
    for q=pc,127,12 do
      local donor,distance
      for _,d in ipairs(donors) do
        local delta=math.abs(q-d.pitch)
        if not distance or delta<distance then donor,distance=d.note,delta end
      end
      candidates[#candidates+1]={pitch=q,donor=donor,distance=distance}
    end
    table.sort(candidates,function(a,b)
      if a.distance~=b.distance then return a.distance<b.distance end
      local ac,bc=math.abs(a.pitch-center),math.abs(b.pitch-center)
      if ac~=bc then return ac<bc end
      return a.pitch<b.pitch
    end)
    local addition
    for _,candidate in ipairs(candidates) do
      local d=candidate.donor
      local first,last=d.startppq,d.endppq
      if block then first,last=latest,ending end
      local safe=last>first
      for _,interval in ipairs(occupied[d.channel*128+candidate.pitch] or {}) do
        -- Existing unisons grant no exception to newly inserted notes.
        if first<interval[2] and interval[1]<last then safe=false; break end
      end
      if safe then
        addition={pitch=candidate.pitch,startppq=first,endppq=last,
          velocity=d.velocity,channel=d.channel,muted=d.muted,selected=true}
        break
      end
    end
    if not addition then
      return nil,"无法在 MIDI 0–127 内安全补齐目标音级："..NAMES[pc+1].."（同通道重叠冲突）。"
    end
    additions[#additions+1]=addition
    occupy(addition,addition.pitch)
  end
  return additions,nil
end

local function plan_conversion(entry,source,target,mode,limit)
  local notes,all=entry.notes,entry.all
  local why
  local map,truncated=solve(source,target,notes,limit,function(candidate)
    local pitches,err=transform(notes,source,target,candidate,mode,limit)
    if not pitches then why=err;return false end
    if has_collision(notes,all,pitches) then why="同通道重叠同音";return false end
    local additions,err=plan_additions(notes,all,pitches,source,target)
    if not additions then why=err;return false end
    return true
  end)
  if truncated then return nil,"搜索达到预算，未作修改。" end
  if not map then return nil,"找不到满足移动上限和安全条件的排列："..(why or "请调整选择或上限") end
  local pitches,err=transform(notes,source,target,map,mode,limit)
  if not pitches then return nil,err end
  local additions,add_error=plan_additions(notes,all,pitches,source,target)
  if not additions then return nil,add_error end
  local changed,maxmove=0,0
  for i,n in ipairs(notes) do
    if n.pitch~=pitches[i] then changed=changed+1 end
    maxmove=math.max(maxmove,math.abs(n.pitch-pitches[i]))
  end
  return {entry=entry,source=source,target=target,pitches=pitches,additions=additions,changed=changed,maxmove=maxmove}
end

local function valid_entry(entry)
  if R.ValidatePtr2 and not R.ValidatePtr2(0,entry.take,"MediaItem_Take*") then return false end
  local ok,raw=R.MIDI_GetAllEvts(entry.take,"")
  return ok and raw==entry.raw
end

local function apply_batch(entries,source_override,target,mode,limit)
  local plans,lines={},{}
  local changed,added=0,0
  for i,entry in ipairs(entries) do
    if not valid_entry(entry) then msg("面板打开期间 MIDI 已改变或片段已失效，请重新运行。未作修改。");return end
    local source=source_override or assert(parse(entry.guess))
    local plan,err=plan_conversion(entry,source,target,mode,limit)
    if not plan then msg(entry.label.."："..tostring(err).."\n全部未作修改。");return end
    plans[#plans+1]=plan;changed=changed+plan.changed;added=added+#plan.additions
    if i<=24 then lines[#lines+1]=entry.label.."："..source.name.." → "..target.name.."；改 "..plan.changed.."，补 "..#plan.additions.."，最大移动 "..plan.maxmove.." 半音" end
  end
  if changed==0 and added==0 then msg("当前排列无需修改，所有 item 均已包含目标和弦音。");return end
  if #entries>24 then lines[#lines+1]="……其余 item 省略显示" end
  local preview="独立转换 "..#entries.." 个 item；修改 "..changed.." 个音符，新增 "..added.." 个音符。\n"..table.concat(lines,"\n").."\n\n补音沿用本 item 的节奏/力度/通道。原有音符不删除。\n池化 MIDI 的共享实例也可能联动；建议先解除池化。\n确认应用？（一次撤销）"
  if R.ShowMessageBox(preview,TITLE,1)~=1 then return end
  -- Recheck after confirmation as well: no stale indices may be written.
  for _,entry in ipairs(entries) do
    if not valid_entry(entry) then msg("确认期间 MIDI 已改变或片段已失效，全部未作修改。");return end
  end
  R.Undo_BeginBlock2(0);R.PreventUIRefresh(1)
  local success,err=xpcall(function()
    for _,plan in ipairs(plans) do
      local entry=plan.entry
      -- Pooled/shared sources modified by an earlier write cannot be safely written twice.
      if not valid_entry(entry) then error("item 内容因共享源或外部编辑改变，停止并回滚") end
      for i,n in ipairs(entry.notes) do
        if n.pitch~=plan.pitches[i] then
          if not R.MIDI_SetNote(entry.take,n.index,nil,nil,nil,nil,nil,plan.pitches[i],nil,true) then error("MIDI_SetNote 写入失败") end
        end
      end
      for _,n in ipairs(plan.additions) do
        if not R.MIDI_InsertNote(entry.take,true,n.muted,n.startppq,n.endppq,n.channel,n.pitch,n.velocity,true) then error("MIDI_InsertNote 写入失败") end
      end
      R.MIDI_Sort(entry.take)
    end
  end,debug.traceback)
  local restored=true
  if not success then
    for i=#entries,1,-1 do
      local e=entries[i]
      local ok,result=pcall(R.MIDI_SetAllEvts,e.take,e.raw)
      if not ok or not result then restored=false end
    end
  end
  R.PreventUIRefresh(-1);R.Undo_EndBlock2(0,TITLE.."："..#entries.." item → "..target.name,-1)
  R.UpdateArrange()
  for _,entry in ipairs(entries) do if R.MIDI_RefreshEditors then R.MIDI_RefreshEditors(entry.take) end end
  if not success then msg((restored and "转换失败，已恢复全部 MIDI。\n" or "转换失败，部分恢复失败！请立即撤销并检查。\n")..tostring(err)) end
end

local function read_entries(editor)
  local takes,seen={},{}
  if R.MIDIEditor_EnumTakes then
    local i=0
    while true do
      local take=R.MIDIEditor_EnumTakes(editor,i,true)
      if not take then break end
      if not seen[take] then seen[take]=true;takes[#takes+1]=take end
      i=i+1
    end
  else
    local take=R.MIDIEditor_GetTake(editor)
    if take then takes[1]=take end
  end
  local entries={}
  for _,take in ipairs(takes) do
    if R.TakeIsMIDI(take) then
      local ok,count=R.MIDI_CountEvts(take)
      if not ok then return nil,"读取 MIDI 失败。" end
      local notes,all={},{}
      for i=0,count-1 do
        local got,selected,muted,startppq,endppq,channel,pitch,velocity=R.MIDI_GetNote(take,i)
        if not got then return nil,"读取音符失败。" end
        local n={index=i,selected=selected,muted=muted,startppq=startppq,endppq=endppq,channel=channel,pitch=pitch,velocity=velocity}
        all[#all+1]=n;if selected then notes[#notes+1]=n end
      end
      if #notes>0 then
        local saved,raw=R.MIDI_GetAllEvts(take,"")
        if not saved then return nil,"无法备份 MIDI。" end
        entries[#entries+1]={take=take,notes=notes,all=all,guess=detect(notes),raw=raw,label="item "..(#entries+1)}
      end
    end
  end
  return entries
end

local function main()
  local editor=R.MIDIEditor_GetActive()
  if not editor then msg("请打开 MIDI 编辑器，并选择音符。");return end
  local entries,err=read_entries(editor)
  if not entries then msg(err);return end
  if #entries==0 then msg("没有选中的音符。请在可编辑的 MIDI item 中选择要转换的音符。");return end
  local guess=entries[1].guess
  if gfx and gfx.init and R.defer then
    select_panel(guess,function(s,t,m,l,override)
      apply_batch(entries,override and s or nil,t,m,l)
    end,#entries)
    return
  end
  local defaults=(#entries==1 and guess or "")..",C,1,7"
  while true do
    local accepted,csv=R.GetUserInputs(TITLE,4,"原和弦（留空各 item 自动识别）,目标和弦,外音策略（1-3）,移动上限（1-12）,extrawidth=230",defaults)
    if not accepted then return end
    local fields={};for s in (csv..","):gmatch("([^,]*),") do fields[#fields+1]=trim(s) end
    local source,e1;if fields[1]~="" then source,e1=parse(fields[1] or "") end
    local target,e2=parse(fields[2] or "")
    local mode,limit=tonumber(fields[3]),tonumber(fields[4])
    if not e1 and target and mode and mode%1==0 and mode>=1 and mode<=3 and limit and limit%1==0 and limit>=1 and limit<=12 and #fields==4 then
      apply_batch(entries,source,target,mode,limit);return
    end
    msg(e1 or e2 or "外音策略需为1–3，移动上限需为1–12整数。");defaults=csv
  end
end

main()
