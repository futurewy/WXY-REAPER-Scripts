-- @description Move arrangement by bars from time selection start
-- @version 2.5
-- @author futurewy
-- @about
--   Moves items, markers and regions starting at or after the time selection start.
--   One bar is intentionally four quarter notes (4/4), as in the original script.
--   Automation and tempo markers are not moved. Back up your project first.
-- @changelog
--   Snapshot markers before moving to avoid index reordering and preserve colors.
--   Validate input before undo; reject negative target positions; restore UI on errors.

local start_time, end_time = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
if start_time == end_time then
    reaper.ShowMessageBox('请先创建时间选区，以其起点作为平移分界点。', '提示', 0)
    return
end
local accepted, input = reaper.GetUserInputs('平移编曲段落（按 4/4 换算）', 1,
    '移动小节数（正数向右/负数向左）:', '1.0')
if not accepted then return end
local bars = tonumber(input)
if not bars or bars ~= bars or math.abs(bars) == math.huge then
    reaper.ShowMessageBox('请输入有限的数字。', '提示', 0)
    return
end
if bars == 0 then return end
local qn = reaper.TimeMap2_timeToQN(0, start_time)
local target = reaper.TimeMap2_QNToTime(0, qn + bars * 4)
local offset = target - start_time
if offset ~= offset or math.abs(offset) == math.huge or target < 0 then
    reaper.ShowMessageBox('移动后时间选区将超出项目起点，或偏移量无效。未进行修改。', '提示', 0)
    return
end

-- Snapshot every index-sensitive collection before changing its positions.
local items, markers = {}, {}
for i = 0, reaper.CountMediaItems(0) - 1 do
    local item = reaper.GetMediaItem(0, i)
    local pos = reaper.GetMediaItemInfo_Value(item, 'D_POSITION')
    if pos >= start_time then items[#items + 1] = {item = item, pos = pos} end
end
local _, marker_count, region_count = reaper.CountProjectMarkers(0)
for i = 0, marker_count + region_count - 1 do
    local result, region, pos, finish, name, id, color = reaper.EnumProjectMarkers3(0, i)
    if result > 0 and pos >= start_time then
        markers[#markers + 1] = {region = region, pos = pos, finish = finish,
            name = name, id = id, color = color}
    end
end
reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)
local ok, err = xpcall(function()
    for _, item in ipairs(items) do
        reaper.SetMediaItemInfo_Value(item.item, 'D_POSITION', item.pos + offset)
    end
    for _, marker in ipairs(markers) do
        reaper.SetProjectMarker3(0, marker.id, marker.region, marker.pos + offset,
            marker.region and marker.finish + offset or 0, marker.name, marker.color)
    end
    reaper.GetSet_LoopTimeRange(true, false, start_time + offset, end_time + offset, false)
end, debug.traceback)
reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()
reaper.Undo_EndBlock('Move arrangement by bars (4/4)', -1)
if not ok then
    reaper.ShowMessageBox(tostring(err) .. '\n可使用撤销恢复已经执行的修改。', '移动失败', 0)
end
