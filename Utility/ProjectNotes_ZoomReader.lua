-- @description 工程备注歌词：单Lua选字复制、连续编辑、Region跟随
-- @version 5.1.2
-- @author futurewy
-- @about
--   Requires REAPER with ReaImGui 0.10+ (install/update via ReaPack).
--   Reading mode already centers each visual line and uses an opaque black
--   background with white text; selection, copying and Region follow are preserved.
--   FangSong is optional; portable sans-serif fallback may lack CJK glyph coverage.
--   Edits update project notes, not the project file: save the project in REAPER.
--   Backups/recovery use hex-encoded persistent ExtState (not encrypted).
--   Recovery copies drafts to the clipboard; legacy recovery remains readable.
-- @changelog
--   v5.1.2: Guard optional font loading; verify note writes before marking synced;
--   preserve multiline backup/recovery data using single-line hex ExtState.
--   Existing centered, opaque high-contrast reader and follow behavior unchanged.
local R = reaper
local SECTION = 'ProjectNotes_ZoomReader'
if not R.ImGui_GetBuiltinPath then
  R.ShowMessageBox('需要 ReaImGui 扩展。请通过 ReaPack 安装或更新 ReaImGui。','工程备注',0)
  return
end
package.path = R.ImGui_GetBuiltinPath() .. '/?.lua;' .. package.path
local ok, I = pcall(function() return require('imgui')('0.10') end)
if not ok then R.ShowMessageBox(tostring(I), '需要 ReaImGui 0.10 或更新版本',0); return end
local ctx = I.CreateContext('Wxy Project Notes')
-- The reading surface owns mouse drags for text selection, not window movement.
I.SetConfigVar(ctx,I.ConfigVar_WindowsMoveFromTitleBarOnly,1)
-- File fonts and system families are optional on other machines.
local function attachedFont(create)
  local ok, value = pcall(function()
    local candidate = create()
    if not candidate then return nil end
    I.Attach(ctx, candidate)
    return candidate
  end)
  return ok and value or nil
end
local uiFont = attachedFont(function() return I.CreateFont('Microsoft YaHei') end)
  or attachedFont(function() return I.CreateFont('sans-serif') end)
if not uiFont then
  R.ShowMessageBox('无法创建字体，请检查 ReaImGui 安装。','工程备注',0)
  return
end
local font = attachedFont(function() return I.CreateFontFromFile('C:/Windows/Fonts/simfang.ttf') end)
  or uiFont
local caretCallback=I.CreateFunctionFromEEL([[
  restore >= 0 ? (
    CursorPos = restore;
    InputTextCallback_ClearSelection();
    restore = -1;
  );
  caret = CursorPos;
  selection = InputTextCallback_HasSelection();
  selstart = SelectionStart;
  selend = SelectionEnd;
]])
I.Attach(ctx,caretCallback)
I.Function_SetValue(caretCallback,'restore',-1)
local function clamp(n,a,b) return math.max(a,math.min(b,n)) end
local size = clamp(tonumber(R.GetExtState(SECTION,'size')) or 28,12,96)
local states, current, editing, active = {}, nil, false, false
local function zoom(delta)
  size=clamp(size+delta,12,96)
  R.SetExtState(SECTION,'size',tostring(size),true)
end
-- Persistent ExtState is INI-backed: raw newlines are not safe across restarts.
local function encode(text)
  return (text:gsub('.',function(ch) return string.format('%02X',ch:byte()) end))
end
local function decode(text)
  if #text%2~=0 or text:find('[^%x]') then return nil end
  return (text:gsub('%x%x',function(pair) return string.char(tonumber(pair,16)) end))
end
local function read(p) return R.GetSetProjectNotes(p,false,'') or '' end
local function valid(p) return R.ValidatePtr(p,'ReaProject*') end
local function getstate(p)
  if not states[p] then
    local t=read(p)
    states[p]={base=t,text=t,conflict=false,revision=0,status='已同步'}
  end
  return states[p]
end
-- Compare before every write. Never overwrite an unexpected outside change.
local function save(p,s,force)
  if not valid(p) then s.conflict=true; s.status='工程已关闭，草稿保留在此会话'; return false end
  local remote=read(p)
  if not force and remote~=s.base then
    s.conflict=true; s.status='发现外部修改：请选择保留哪一份'; return false
  end
  if remote~=s.text then
    -- Preserve the most recent overwritten version for recovery.
    R.SetExtState(SECTION,'last_backup_hex',encode(remote),true)
    R.Undo_BeginBlock2(p)
    -- GetSetProjectNotes returns a string, not a success boolean. Verify read-back.
    local wrote = pcall(R.GetSetProjectNotes,p,true,s.text)
    R.MarkProjectDirty(p)
    R.Undo_EndBlock2(p,'编辑工程备注歌词',-1)
    if not wrote or read(p)~=s.text then
      s.conflict=true; s.status='备注写入未确认，草稿已保留；请处理同步冲突'
      return false
    end
  end
  s.base=s.text; s.conflict=false; s.status='已同步到工程备注（请保存工程）'
  return true
end
R.atexit(function()
  local drafts={}
  for p,s in pairs(states) do
    if s.conflict or s.text~=s.base then
      local name=valid(p) and R.GetProjectName(p,'') or '已关闭工程'
      drafts[#drafts+1]=(name or tostring(p))..'\n'..s.text
    end
  end
  if #drafts>0 then
    R.SetExtState(SECTION,'recovery_drafts_hex',encode(table.concat(drafts,'\n\n---\n\n')),true)
    R.ShowMessageBox('存在未解决的冲突草稿，已保存在 REAPER 扩展状态中。下次运行可用“恢复草稿”复制内容。','工程备注草稿已保留',0)
  end
end)
-- Optional FangSong keeps matching Latin glyphs; fallback uses the UI font.
local fullscreen, restore, bounds = false, false, nil
local normal = {x=100,y=100,w=900,h=760}
local function toggleFullscreen()
  if not fullscreen then
    normal.x,normal.y=I.GetWindowPos(ctx)
    normal.w,normal.h=I.GetWindowSize(ctx)
    local nx,ny=I.PointConvertNative(ctx,normal.x+normal.w/2,normal.y+normal.h/2,true)
    local l,t,r,b=R.my_getViewport(nx,ny,nx+1,ny+1,nx,ny,nx+1,ny+1,false)
    l,t=I.PointConvertNative(ctx,l,t,false)
    r,b=I.PointConvertNative(ctx,r,b,false)
    bounds={x=l,y=t,w=r-l,h=b-t}
    fullscreen=true
  else fullscreen=false; restore=true end
end
local function symbol(label,tip)
  local clicked=I.Button(ctx,label)
  if I.IsItemHovered(ctx) then I.SetTooltip(ctx,tip) end
  return clicked
end
-- Region tags are plain project-note lines: [A1] or [#12|A1].
-- Selected regions bind by ID; manually typed tags bind by exact name.
local follow, forceFollow = true, true
local layout, lastTarget = {}, nil
local manualPaused, lastEditCursor = false, nil
local function regionList(p)
  local result={}
  local _,markers,regions=R.CountProjectMarkers(p)
  for i=0,markers+regions-1 do
    local ok,isRegion,a,b,name,id,color=R.EnumProjectMarkers3(p,i)
    if ok~=0 and isRegion then result[#result+1]={id=id,name=name,start=a,finish=b,color=color or 0} end
  end
  table.sort(result,function(a,b) if a.start==b.start then return a.id<b.id end return a.start<b.start end)
  return result
end
local function parseTag(line)
  local inside=line:match('^%s*%[(.-)%]%s*$')
  if not inside then return nil end
  local id,name=inside:match('^#(%d+)|(.*)$')
  if id then return {id=tonumber(id),name=name} end
  return {name=inside}
end
local function rowsOf(text)
  local rows,pending={},nil
  local sourceOffset=0
  text=text:gsub('\r\n','\n'):gsub('\r','\n')
  for line in (text..'\n'):gmatch('(.-)\n') do
    local tag=parseTag(line)
    if tag then
      if pending then rows[#rows+1]={text='',tag=pending} end
      pending=tag
    else rows[#rows+1]={text=line,tag=pending,sourceStart=sourceOffset}; pending=nil end
    sourceOffset=sourceOffset+#line+1
  end
  if pending then rows[#rows+1]={text='',tag=pending} end
  if #rows==0 then rows[1]={text=''} end
  return rows
end
local function serialize(rows)
  local out={}
  for _,row in ipairs(rows) do
    if row.tag then
      local t=row.tag
      out[#out+1]='['..(t.id and '#'..t.id..'|' or '')..t.name..']'
    end
    out[#out+1]=row.text
  end
  return table.concat(out,'\n')
end
local function commit(p,s,rows)
  s.text=serialize(rows); s.rows=rows; s.rowsSource=s.text
  if not s.conflict then save(p,s,false) end
end
local function autoAssociate(p,s,regions)
  if s.conflict or read(p)~=s.base then
    R.ShowMessageBox('请先处理备注同步冲突，再执行自动关联。','自动关联',0)
    return
  end
  local names={}
  for _,r in ipairs(regions) do
    if r.name~='' then
      names[r.name]=names[r.name] or {}
      table.insert(names[r.name],r)
    end
  end
  local rows=rowsOf(s.text)
  local added,ambiguous,kept=0,0,0
  for index,row in ipairs(rows) do
    local start=index==1 or rows[index-1].text:match('^%s*$')~=nil
    if row.tag and row.tag.id then kept=kept+1
    elseif start or row.tag then
      local raw=row.text:match('^%s*(.-)%s*$')
      local name=row.tag and row.tag.name or (raw:match('^%-%-%-(.-)%-%-%-$') or raw)
      local candidates=names[name]
      if candidates and #candidates==1 then
        row.tag={id=candidates[1].id,name=candidates[1].name}; added=added+1
      elseif candidates and #candidates>1 then ambiguous=ambiguous+1 end
    end
  end
  if added>0 then
    commit(p,s,rows)
    s.revision=s.revision+1; forceFollow=true
  end
  R.ShowMessageBox(string.format('已关联：%d 处\n保留已有编号关联：%d 处\n跳过同名歧义：%d 处\n\n只匹配段首独立标题与 Region 的完整名称；区分大小写，不猜测相似名称。修改后请保存工程。',added,kept,ambiguous),'自动关联完成',0)
end
local function tagName(tag,regions)
  if tag.id then for _,r in ipairs(regions) do if r.id==tag.id then return r.name~='' and r.name or ('#'..r.id) end end end
  return tag.name
end
local function currentRegion(p,regions)
  local playing=(R.GetPlayStateEx(p)&1)~=0
  local pos=playing and R.GetPlayPositionEx(p) or R.GetCursorPositionEx(p)
  local best=nil
  for _,r in ipairs(regions) do
    if pos>=r.start and pos<r.finish and (not best or r.start>best.start or (r.start==best.start and r.finish<best.finish)) then best=r end
  end
  return best
end
local function matches(tag,region)
  return tag and region and ((tag.id and tag.id==region.id) or (not tag.id and tag.name==region.name))
end
local function regionColor(tag,regions)
  for _,r in ipairs(regions) do
    if (tag.id and tag.id==r.id) or (not tag.id and tag.name==r.name) then
      if r.color~=0 then
        local red,green,blue=R.ColorFromNative(r.color & 0xFFFFFF)
        return (red<<24)|(green<<16)|(blue<<8)|0xFF
      end
    end
  end
  return 0xB0B0B0FF
end
local function colorSwatch(color)
  local x,y=I.GetCursorScreenPos(ctx)
  I.Dummy(ctx,14,20)
  I.DrawList_AddRectFilled(I.GetWindowDrawList(ctx),x,y+3,x+12,y+17,color,2)
  I.SameLine(ctx)
end
local function buildLayout(text,width,regions)
  local signature={}
  for _,r in ipairs(regions) do signature[#signature+1]=r.id..'='..r.name end
  signature=table.concat(signature,'|')
  if layout.text==text and layout.width==width and layout.size==size and layout.signature==signature then return end
  local visual={}
  local function wrap(text,tag,header,sourceStart)
    local line,offset,continuation='',0,false
    local function add() visual[#visual+1]={text=line,width=I.CalcTextSize(ctx,line),tag=tag,header=header,softWrap=continuation,sourceStart=sourceStart and sourceStart+offset};offset=offset+#line;continuation=true end
    for ch in text:gmatch('[%z\1-\127\194-\244][\128-\191]*') do
      if line~='' and I.CalcTextSize(ctx,line..ch)>width then add(); line=ch else line=line..ch end
    end
    add()
  end
  local currentTag=nil
  local function blank()
    if #visual>0 and visual[#visual].text~='' then visual[#visual+1]={text='',width=0} end
  end
  for _,row in ipairs(rowsOf(text)) do
    local trimmed=row.text:match('^%s*(.-)%s*$')
    if row.tag then
      currentTag=row.tag
      local name=tagName(row.tag,regions)
      local original=row.tag.name
      local function titleMatches(candidate)
        return trimmed==candidate or trimmed=='['..candidate..']' or trimmed=='---'..candidate..'---'
      end
      local existingTitle=titleMatches(name) or titleMatches(original)
      blank()
      wrap('---'..name..'---',currentTag,true,row.sourceStart)
      if not existingTitle and trimmed~='' then wrap(row.text,currentTag,false,row.sourceStart) end
    elseif trimmed=='' then
      -- Empty lines terminate association, even if the next paragraph has no tag.
      currentTag=nil; blank()
    else wrap(row.text,currentTag,false,row.sourceStart) end
  end
  while #visual>0 and visual[#visual].text=='' do table.remove(visual) end
  layout={text=text,width=width,size=size,signature=signature,lines=visual}
  forceFollow=true
end
-- Replace centeredLyrics ONLY with this block; same lexical scope as original.
-- Optional layout metadata: softWrap=true means continuation of preceding line.
-- sourceStart is 0-based original source byte offset; sourceMap[displayByteOffset]
-- overrides it for tabs/synthetic text. Omit unknown mappings.
-- Parent consumes/reset readerPasteRequested; remove old blanket double-click handler.
local readerSelection={}
local readerPasteRequested=false
local readerRawPosition=nil
local function readerBefore(a,b)
  return a.line<b.line or (a.line==b.line and a.byte<b.byte)
end
local function readerRange()
  local a,b=readerSelection.anchor,readerSelection.focus
  if not a or not b or (a.line==b.line and a.byte==b.byte) then return nil end
  if readerBefore(b,a) then return b,a end
  return a,b
end
local function readerCopy(lines)
  local a,b=readerRange()
  if not a then return '' end
  local out={}
  for n=a.line,b.line do
    if n>a.line and not lines[n].softWrap then out[#out+1]='\n' end
    out[#out+1]=lines[n].text:sub((n==a.line and a.byte or 0)+1,n==b.line and b.byte or #lines[n].text)
  end
  return table.concat(out)
end
local function readerBounds(text)
  local bounds={0}
  for pos,ch in text:gmatch('()([%z\1-\127\194-\244][\128-\191]*)') do bounds[#bounds+1]=pos-1+#ch end
  return bounds
end
local function readerHit(lines,geo,mx,my,strict)
  if #lines==0 then return nil end
  local row=1
  while row<#lines and my>=geo[row+1].y do row=row+1 end
  local g,line=geo[row],lines[row]
  if strict and (my<g.y or my>=g.y+g.h or mx<g.x or mx>=g.x+line.width or line.text=='') then return nil end
  if line.readerText~=line.text or line.readerSize~=size then
    line.readerText,line.readerSize=line.text,size
    line.readerBounds=readerBounds(line.text); line.readerWidths={0}
    for n=2,#line.readerBounds do line.readerWidths[n]=I.CalcTextSize(ctx,line.text:sub(1,line.readerBounds[n])) end
  end
  for n=2,#line.readerBounds do
    if mx-g.x<(line.readerWidths[n-1]+line.readerWidths[n])/2 then return {line=row,byte=line.readerBounds[n-1]} end
  end
  return {line=row,byte=#line.text}
end
local function readerWord(lines,pos)
  local first,last=pos.line,pos.line
  while first>1 and lines[first].softWrap do first=first-1 end
  while last<#lines and lines[last+1].softWrap do last=last+1 end
  local text,offset='',pos.byte
  for n=first,last do
    if n<pos.line then offset=offset+#lines[n].text end
    text=text..lines[n].text
  end
  local bounds=readerBounds(text)
  if #bounds<2 then return pos,pos end
  local index=#bounds-1
  for n=1,#bounds-1 do if offset<bounds[n+1] then index=n; break end end
  local function class(n)
    local ch=text:sub(bounds[n]+1,bounds[n+1])
    if ch:match('^%s$') or ch=='　' then return 'space' end
    if ch:match('^[%w_]$') then return 'latin' end
    if #ch>1 then return 'unicode' end
    return 'punct'
  end
  local lo,hi,kind=index,index,class(index)
  if kind~='punct' then
    while lo>1 and class(lo-1)==kind do lo=lo-1 end
    while hi<#bounds-1 and class(hi+1)==kind do hi=hi+1 end
  end
  local function point(byte)
    for n=first,last do
      if byte<=#lines[n].text or n==last then return {line=n,byte=math.min(byte,#lines[n].text)} end
      byte=byte-#lines[n].text
    end
  end
  return point(bounds[lo]),point(bounds[hi+1])
end
local function readerSourcePoint(lines,pos)
  if not pos then return nil end
  local line=lines[pos.line]
  if line.sourceMap and line.sourceMap[pos.byte]~=nil then return line.sourceMap[pos.byte] end
  if line.sourceStart~=nil then return line.sourceStart+(line.header and 0 or pos.byte) end
end
local function centeredLyrics(p,text,regions)
  local availableWidth=I.GetContentRegionAvail(ctx)
  local width=math.max(1,availableWidth)
  buildLayout(text,width,regions)
  local lines,sel=layout.lines,readerSelection
  if sel.project~=p or sel.lines~=lines then
    sel.anchor,sel.focus,sel.press,sel.pending=nil,nil,nil,nil
    sel.dragging=false; sel.project=p; sel.lines=lines; readerRawPosition=nil
  end
  local region=currentRegion(p,regions)
  local key=tostring(p)..':'..(region and tostring(region.id) or '-')
  local hovered,focused=I.IsWindowHovered(ctx),I.IsWindowFocused(ctx)
  local mx,my=I.GetMousePos(ctx)
  local wx,wy=I.GetWindowPos(ctx)
  local ww,wh=I.GetWindowSize(ctx)
  local sx,sy=I.GetCursorScreenPos(ctx)
  local left=I.GetCursorPosX(ctx)
  local height,step=I.GetTextLineHeight(ctx),I.GetTextLineHeightWithSpacing(ctx)
  -- The current window is the reader child, not its parent/control strip.
  -- Draw clipping additionally intersects the actual ImGui window clip rectangle.
  local clip={x1=math.max(wx+1,sx),y1=wy+1,x2=math.min(wx+ww-1,sx+width),y2=wy+wh-1}
  local inside=hovered and mx>=clip.x1 and mx<clip.x2 and my>=clip.y1 and my<clip.y2
  local geo={}
  for n,line in ipairs(lines) do geo[n]={x=sx+math.max(0,(width-line.width)/2),y=sy+(n-1)*step,h=height} end
  local exact=inside and readerHit(lines,geo,mx,my,true) or nil
  local down,double=I.IsMouseClicked(ctx,0),I.IsMouseDoubleClicked(ctx,0)
  local held,released=I.IsMouseDown(ctx,0),I.IsMouseReleased(ctx,0)
  local now=I.GetTime(ctx)
  if down then sel.pending=nil end
  if inside and down then
    local point=readerHit(lines,geo,mx,my,false)
    sel.press={x=mx,y=my,header=exact and lines[exact.line].header and exact.line or nil,double=double,moved=false}
    sel.dragging=point~=nil
    if double and exact then
      sel.anchor,sel.focus=readerWord(lines,exact)
      sel.press.wordAnchor,sel.press.wordFocus=sel.anchor,sel.focus
    elseif double then
      sel.anchor,sel.focus=nil,nil; sel.dragging=false; toggleFullscreen()
    else sel.anchor,sel.focus=point,point end
  end
  if sel.press and (held or released) then
    local press=sel.press
    if (mx-press.x)^2+(my-press.y)^2>=16 then press.moved=true end
    if sel.dragging and press.moved then
      local point=readerHit(lines,geo,mx,my,false)
      if point then
        if press.wordAnchor then
          local a,b=readerWord(lines,point)
          if readerBefore(point,press.wordAnchor) then sel.anchor,sel.focus=press.wordFocus,a
          else sel.anchor,sel.focus=press.wordAnchor,b end
        else sel.focus=point end
      end
      manualPaused=true
      if held and my<clip.y1+12 then I.SetScrollY(ctx,math.max(0,I.GetScrollY(ctx)-step*0.5))
      elseif held and my>clip.y2-12 then I.SetScrollY(ctx,I.GetScrollY(ctx)+step*0.5) end
    end
    if released then
      if not press.double and not press.moved and press.header and exact and exact.line==press.header then
        local destination=nil
        for _,r in ipairs(regions) do
          if matches(lines[press.header].tag,r) and (not destination or (region and r.id==region.id)) then destination=r end
        end
        if destination then sel.pending={at=now+math.max(0.30,I.GetConfigVar(ctx,I.ConfigVar_MouseDoubleClickTime)),project=p,id=destination.id,start=destination.start} end
      end
      sel.press=nil; sel.dragging=false
    end
  elseif sel.press and not held then sel.press=nil; sel.dragging=false end
  if focused and not I.IsAnyItemActive(ctx) then
    local ctrl=I.IsKeyDown(ctx,I.Mod_Ctrl)
    if ctrl and I.IsKeyPressed(ctx,I.Key_A,false) and #lines>0 then
      sel.anchor={line=1,byte=0}; sel.focus={line=#lines,byte=#lines[#lines].text}; sel.pending=nil
    end
    if ctrl and I.IsKeyPressed(ctx,I.Key_C,false) and readerRange() then I.SetClipboardText(ctx,readerCopy(lines)) end
    if ctrl and I.IsKeyPressed(ctx,I.Key_V,false) then
      readerRawPosition=readerSourcePoint(lines,sel.focus)
      readerPasteRequested=true; sel.pending=nil -- no clipboard read, no text insertion
    end
    if I.IsKeyPressed(ctx,I.Key_Escape,false) then sel.anchor,sel.focus,sel.pending=nil,nil,nil end
  end
  if sel.pending and now>=sel.pending.at then
    local pending=sel.pending; sel.pending=nil
    if focused and pending.project==p and not readerRange() and not held then
      for _,r in ipairs(regions) do if r.id==pending.id and r.start==pending.start then
        R.SetEditCurPos2(p,r.start,true,true); manualPaused=false; forceFollow=true; break
      end end
    end
  end
  local editCursor=R.GetCursorPositionEx(p)
  local cursorChanged=lastEditCursor~=nil and editCursor~=lastEditCursor
  lastEditCursor=editCursor
  if cursorChanged then manualPaused=false end
  local wheel=I.GetMouseWheel(ctx)
  if hovered and ((wheel~=0 and not I.IsKeyDown(ctx,I.Mod_Ctrl)) or (held and mx>wx+ww-24)) then manualPaused=true end
  local scrollRegion=region
  if cursorChanged then
    scrollRegion=nil
    for _,r in ipairs(regions) do if editCursor>=r.start and editCursor<r.finish and (not scrollRegion or r.start>scrollRegion.start) then scrollRegion=r end end
  end
  local a,b=readerRange()
  local draw,target=I.GetWindowDrawList(ctx),nil
  I.DrawList_PushClipRect(draw,clip.x1,clip.y1,clip.x2,clip.y2,true)
  for n,line in ipairs(lines) do
    local y=I.GetCursorPosY(ctx)
    if not target and matches(line.tag,scrollRegion) then target=y end
    local g=geo[n]
    I.SetCursorPosX(ctx,left+math.max(0,(width-line.width)/2))
    -- Highlight is submitted BEFORE Text, behind glyphs rather than over them.
    if a and n>=a.line and n<=b.line then
      local first,last=n==a.line and a.byte or 0,n==b.line and b.byte or #line.text
      local x1=g.x+I.CalcTextSize(ctx,line.text:sub(1,first))
      local x2=g.x+I.CalcTextSize(ctx,line.text:sub(1,last))
      if n<b.line and not lines[n+1].softWrap then x2=x2+math.max(4,height*0.22) end
      if x2>x1 then I.DrawList_AddRectFilled(draw,x1,g.y,x2,g.y+height,0x397AC699) end
    end
    if line.text=='' then I.Dummy(ctx,0,height)
    else
      I.Text(ctx,line.text)
      if exact and exact.line==n and line.header then I.SetTooltip(ctx,'单击跳转到 Region 起点；拖动选择；双击选词') end
      if not line.header and matches(line.tag,region) then
        local x1,y1=I.GetItemRectMin(ctx)
        local x2,y2=I.GetItemRectMax(ctx)
        I.DrawList_AddLine(draw,x1,y2-1,x2,y2-1,0xFFFFFFFF,1.5)
      end
    end
  end
  I.DrawList_PopClipRect(draw)
  if follow and not manualPaused and not a and not sel.dragging and target and (key~=lastTarget or forceFollow or cursorChanged) then I.SetScrollY(ctx,math.max(0,target-12)) end
  if not a and not sel.dragging then lastTarget=key; forceFollow=false end
  return readerPasteRequested
end
-- A single full-height InputTextMultiline inside a scrollable child: following scrolls
-- the containing viewport, NEVER moves the text cursor or truncates the buffer.
local function sourceLines(text)
  local result,offset={},0
  for line in (text..'\n'):gmatch('(.-)\n') do
    result[#result+1]={text=line,start=offset};offset=offset+#line+1
  end
  return result
end
local function paragraphAt(text,caret)
  local lines=sourceLines(text);local index=1
  for i,line in ipairs(lines) do if line.start<=caret then index=i else break end end
  while index>1 and not lines[index-1].text:match('^%s*$') do index=index-1 end
  return lines,index
end
local function associateAt(p,s,tag)
  local lines,index=paragraphAt(s.text,s.caret or 0)
  local first=lines[index];local existing=parseTag(first.text)
  local replacement=tag and ('['..(tag.id and '#'..tag.id..'|' or '')..tag.name..']') or nil
  local start=first.start;local finish=start+(existing and #first.text+((index<#lines) and 1 or 0) or 0)
  s.text=s.text:sub(1,start)..(replacement and replacement..'\n' or '')..s.text:sub(finish+1)
  s.caret=start;s.restoreCaret=start;s.focusEditor=true;s.revision=s.revision+1
  if not s.conflict then save(p,s,false) end
end
local function unifiedEditor(p,s,regions,h)
  local lines=sourceLines(s.text)
  local selected=currentRegion(p,regions);local cursor=R.GetCursorPositionEx(p)
  local cursorChanged=s.editorCursor~=nil and s.editorCursor~=cursor;s.editorCursor=cursor
  if cursorChanged then
    manualPaused=false;selected=nil
    for _,r in ipairs(regions) do if cursor>=r.start and cursor<r.finish and (not selected or r.start>selected.start) then selected=r end end
  end
  local key=selected and tostring(selected.id) or '-'
  if key~=s.editorRegion or cursorChanged or forceFollow then s.editorPending=true;s.editorTarget=selected end
  s.editorRegion=key
  local show=I.BeginChild(ctx,'unified_editor_'..tostring(p),0,h,I.ChildFlags_None,I.WindowFlags_AlwaysVerticalScrollbar)
  if show then
    local wheel=I.GetMouseWheel(ctx)
    local mx=I.GetMousePos(ctx);local wx=I.GetWindowPos(ctx);local ww=I.GetWindowSize(ctx)
    if I.IsWindowHovered(ctx,I.HoveredFlags_ChildWindows) and ((wheel~=0 and not I.IsKeyDown(ctx,I.Mod_Ctrl)) or (I.IsMouseDown(ctx,0) and mx>wx+ww-24)) then manualPaused=true end
    local width=I.GetContentRegionAvail(ctx);local top=I.GetCursorPosY(ctx)
    if s.focusEditor then
      I.SetKeyboardFocusHere(ctx);I.Function_SetValue(caretCallback,'restore',s.restoreCaret or s.caret or 0)
      s.focusEditor=nil;s.restoreCaret=nil
    end
    local textHeight=I.GetTextLineHeight(ctx)
    local inputHeight=math.max(h-4,#lines*textHeight+20)
    local wasActive=active
    local escapePressed=I.IsKeyPressed(ctx,I.Key_Escape,false)
    local changed,value=I.InputTextMultiline(ctx,'##continuous_'..tostring(p)..'_'..s.revision,s.text,math.max(40,width),inputHeight,I.InputTextFlags_AllowTabInput|I.InputTextFlags_CallbackAlways,caretCallback)
    active=I.IsItemActive(ctx)
    if active then s.caret=I.Function_GetValue(caretCallback,'caret');s.hasSelection=I.Function_GetValue(caretCallback,'selection')~=0 end
    local now=R.time_precise()
    if escapePressed and (active or wasActive) then
      -- InputText normally reverts to its activation-time value on Escape. Never
      -- write that rollback; recreate from our already-saved authoritative buffer.
      changed=false;s.revision=s.revision+1;s.focusEditor=true;s.restoreCaret=s.caret or 0
    end
    if changed then
      s.text=value;s.lastTyped=now;s.lastCaret=s.caret
      if not s.conflict then save(p,s,false) end
    end
    local usingMouse=I.IsMouseDown(ctx,0)
    if active and s.previousCaret~=nil and s.previousCaret~=s.caret then s.lastNavigation=now end
    local busy=(active and (usingMouse or s.hasSelection or now-(s.lastTyped or -10)<1.2 or now-(s.lastNavigation or -10)<1.2))
    s.followBusy=busy and s.editorPending or false
    if follow and not manualPaused and s.editorPending and not busy then
      local target=nil
      for i,line in ipairs(lines) do if matches(parseTag(line.text),s.editorTarget) then target=i;break end end
      if target then I.SetScrollY(ctx,math.max(0,top+(target-1)*textHeight-12)) end
      s.editorPending=nil
    end
    -- Keep the actual caret visible only for user navigation/editing, never playback.
    if active and not usingMouse and not s.hasSelection and (changed or (s.previousCaret~=nil and s.previousCaret~=s.caret)) then
      local row=1;for i,line in ipairs(sourceLines(s.text)) do if line.start<=s.caret then row=i else break end end
      local y=top+(row-1)*textHeight;local scroll=I.GetScrollY(ctx)
      if y<scroll+6 then I.SetScrollY(ctx,math.max(0,y-6)) elseif y+textHeight>scroll+h-12 then I.SetScrollY(ctx,y+textHeight-h+16) end
    end
    s.previousCaret=s.caret
    I.EndChild(ctx)
  end
  forceFollow=false
end
local function loop()
  local p=R.EnumProjects(-1,'')
  if not p then R.defer(loop); return end
  if p~=current then current=p; active=false; layout={}; lastTarget=nil; lastEditCursor=nil; manualPaused=false; forceFollow=true end
  local s=getstate(p)
  local remote=read(p)
  if remote~=s.base and not s.conflict then
    if active or s.text~=s.base then s.conflict=true
    else s.base=remote; s.text=remote; s.revision=s.revision+1 end
  end
  local flags=I.WindowFlags_NoScrollWithMouse | I.WindowFlags_HorizontalScrollbar
  if fullscreen then
    I.SetNextWindowDockID(ctx,0)
    I.SetNextWindowPos(ctx,bounds.x,bounds.y)
    I.SetNextWindowSize(ctx,bounds.w,bounds.h)
    flags=flags | I.WindowFlags_NoDecoration | I.WindowFlags_NoMove | I.WindowFlags_NoSavedSettings
  elseif restore then
    I.SetNextWindowPos(ctx,normal.x,normal.y)
    I.SetNextWindowSize(ctx,normal.w,normal.h)
    restore=false
  else I.SetNextWindowSize(ctx,900,760,I.Cond_FirstUseEver) end
  I.PushStyleVar(ctx,I.StyleVar_Alpha,1)
  I.PushStyleColor(ctx,I.Col_WindowBg,0x000000FF)
  I.PushStyleColor(ctx,I.Col_ChildBg,0x000000FF)
  I.PushStyleColor(ctx,I.Col_FrameBg,0x000000FF)
  I.PushStyleColor(ctx,I.Col_PopupBg,0x000000FF)
  I.PushStyleColor(ctx,I.Col_Text,0xFFFFFFFF)
  I.SetNextWindowBgAlpha(ctx,1)
  I.PushFont(ctx,uiFont,20)
  local visible,open=I.Begin(ctx,'工程备注 · 歌词',true,flags)
  if visible then
    local w,h=I.GetContentRegionAvail(ctx)
    I.PushFont(ctx,font,size)
    local regions=regionList(p)
    if editing then
      unifiedEditor(p,s,regions,math.max(40,h-52))
    else
      active=false
      if I.BeginChild(ctx,'reader_'..tostring(p),0,math.max(40,h-52),I.ChildFlags_None,I.WindowFlags_AlwaysVerticalScrollbar) then
        centeredLyrics(p,s.text,regions)
        I.EndChild(ctx)
      end
      if readerPasteRequested then
        readerPasteRequested=false;editing=true;active=false;s.focusEditor=true
        s.restoreCaret=readerRawPosition or s.caret or 0;forceFollow=false
      end
    end
    I.PopFont(ctx)
    local hovered=I.IsWindowHovered(ctx,I.HoveredFlags_ChildWindows)
    if hovered and I.IsKeyDown(ctx,I.Mod_Ctrl) then
      local wheel=I.GetMouseWheel(ctx)
      if wheel~=0 then zoom(wheel>0 and 2 or -2) end
    end
    if fullscreen and I.IsKeyPressed(ctx,I.Key_Escape) then toggleFullscreen() end
    if I.IsKeyPressed(ctx,I.Key_F11,false) then toggleFullscreen() end
    -- One readable 48px strip; narrow windows can scroll it horizontally.
    I.PushStyleVar(ctx,I.StyleVar_FramePadding,9,6)
    I.PushStyleColor(ctx,I.Col_Text,0xFFFFFFFF)
    I.PushStyleColor(ctx,I.Col_Button,0x303038FF)
    if symbol('−','缩小字号（Ctrl + 滚轮）') then zoom(-2) end
    I.SameLine(ctx)
    if symbol('+','放大字号（Ctrl + 滚轮）') then zoom(2) end
    I.SameLine(ctx)
    if symbol('↺','恢复默认字号') then zoom(28-size) end
    I.SameLine(ctx)
    if symbol(editing and '阅读' or '编辑','连续文本编辑：跨行选择、全选、复制粘贴；不拆成逐行输入') then
      editing=not editing;active=false;forceFollow=true
      if editing then s.focusEditor=true;s.restoreCaret=s.caret or 0 end
    end
    I.SameLine(ctx)
    local selectionPaused=(not editing and readerRange()~=nil) or (editing and s.followBusy)
    local paused=manualPaused or selectionPaused
    local followText=not follow and '跟随 关' or paused and '跟随 暂停' or '跟随 开'
    I.PushStyleColor(ctx,I.Col_Button,not follow and 0x883C3CFF or paused and 0x946A19FF or 0x24764AFF)
    if symbol(followText,'绿色开启 / 红色关闭 / 黄色暂停。选字或输入时暂缓；手动滚动后点击恢复。') then
      if paused or not follow then
        follow=true;manualPaused=false;readerSelection.anchor=nil;readerSelection.focus=nil
      else follow=false end
      forceFollow=true
    end
    I.PopStyleColor(ctx)
    I.SameLine(ctx)
    if symbol(fullscreen and '还原' or '全屏','F11；双击空白全屏；双击文字选词；Esc 退出全屏') then toggleFullscreen() end
    if editing then
      I.SameLine(ctx)
      local lines,index=paragraphAt(s.text,s.caret or 0)
      local paragraphTag=parseTag(lines[index].text)
      if paragraphTag then colorSwatch(regionColor(paragraphTag,regions)) end
      if symbol(paragraphTag and ('['..tagName(paragraphTag,regions)..']') or '关联','将当前光标所在段落关联到 Region；不改变连续编辑') then I.OpenPopup(ctx,'paragraph_region') end
      I.SameLine(ctx)
      if symbol('自动','按段首独立标题自动关联同名 Region') then autoAssociate(p,s,regions);active=false end
    end
    if s.conflict then
      I.SameLine(ctx)
      if symbol('!','同步冲突：点击处理，两份内容均未自动覆盖') then I.OpenPopup(ctx,'sync_conflict') end
    end
    local recovery=decode(R.GetExtState(SECTION,'recovery_drafts_hex')) or ''
    if recovery=='' then recovery=R.GetExtState(SECTION,'recovery_drafts') end
    if recovery~='' then
      I.SameLine(ctx)
      if symbol('↧','复制上次未同步的草稿到剪贴板') then I.SetClipboardText(ctx,recovery) end
    end
    I.PopStyleColor(ctx,2)
    I.PopStyleVar(ctx)
    if I.BeginPopup(ctx,'paragraph_region') then
      local lines,index=paragraphAt(s.text,s.caret or 0)
      local tag=parseTag(lines[index].text)
      I.Text(ctx,tag and ('已关联：'..tagName(tag,regions)) or '当前段落：未关联')
      if I.Selectable(ctx,'[ ] 手动输入…') then s.manualName=tag and tag.name or '';s.openManual=true end
      if I.Selectable(ctx,'清除关联') then associateAt(p,s,nil) end
      for _,r in ipairs(regions) do
        colorSwatch(regionColor({id=r.id},regions))
        if I.Selectable(ctx,(r.name~='' and r.name or '(未命名)')..'##pick_'..r.id) then associateAt(p,s,{id=r.id,name=r.name}) end
      end
      I.EndPopup(ctx)
    end
    if s.openManual then I.OpenPopup(ctx,'manual_region');s.openManual=nil end
    if I.BeginPopup(ctx,'manual_region') then
      local changed,value=I.InputText(ctx,'名称',s.manualName or '')
      if changed then s.manualName=value end
      if I.Button(ctx,'确定') then
        local name=(s.manualName or ''):match('^%s*(.-)%s*$')
        if name~='' and not name:find('[%[%]\r\n]') then associateAt(p,s,{name=name});I.CloseCurrentPopup(ctx) end
      end
      I.SameLine(ctx)
      if I.Button(ctx,'取消') then I.CloseCurrentPopup(ctx) end
      I.EndPopup(ctx)
    end
    if I.BeginPopup(ctx,'sync_conflict') then
      I.TextWrapped(ctx,'工程备注也有修改。请选择采用哪份内容。')
      if I.Button(ctx,'复制本窗口草稿') then I.SetClipboardText(ctx,s.text) end
      if I.Button(ctx,'采用工程备注') then
        s.text=read(p); s.base=s.text; s.conflict=false; s.revision=s.revision+1; I.CloseCurrentPopup(ctx)
      end
      if I.Button(ctx,'用本窗口覆盖工程备注') then
        if R.ShowMessageBox('确定覆盖？原工程备注将保留为最近备份。','确认覆盖',4)==6 then save(p,s,true); I.CloseCurrentPopup(ctx) end
      end
      I.EndPopup(ctx)
    end
    I.End(ctx)
  end
  I.PopFont(ctx)
  I.PopStyleColor(ctx,5)
  I.PopStyleVar(ctx)
  if open then R.defer(loop) end
end
loop()
