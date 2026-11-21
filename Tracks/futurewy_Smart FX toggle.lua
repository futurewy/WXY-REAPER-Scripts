-- @description Smart toggle for the active FX or instrument window of the selected track
-- @version 1.5
-- @author futurewy
-- @about
--   First run: opens the floating window of the first active effect on the
--   selected track, preferring an instrument. Running it again from the same
--   shortcut closes the open effect windows.
--
--   Uses only native REAPER actions, so no extension is required.
--
--   Closing note: TrackFX_Show(..., 0) hides the FX chain window rather than
--   the floating window, so floating windows must be closed with 2.

local function Main()
    local track = reaper.GetSelectedTrack(0, 0)
    if not track then return end

    local num_fx = reaper.TrackFX_GetCount(track)
    if num_fx == 0 then return end

    -- 1. 只要这条轨道上有任何效果器的浮动窗口是打开的 → 全部关闭
    local closed_any = false
    for i = 0, num_fx - 1 do
        if reaper.TrackFX_GetFloatingWindow(track, i) then
            reaper.TrackFX_Show(track, i, 2) -- 2 = 隐藏浮动窗口
            closed_any = true
        end
    end
    if closed_any then return end

    -- 2. 如果 FX 链窗口是打开的（-1 表示已关闭）→ 关闭它
    if reaper.TrackFX_GetChainVisible(track) ~= -1 then
        reaper.TrackFX_Show(track, 0, 0) -- 0 = 隐藏 FX 链窗口
        return
    end

    -- 3. 都没打开 → 寻找目标效果器并打开
    -- 优先 VSTi（音源）
    local target_fx = reaper.TrackFX_GetInstrument(track)

    -- 没有 VSTi，或 VSTi 离线/旁通 → 扫描第一个“活跃”的 FX
    if target_fx < 0
        or reaper.TrackFX_GetOffline(track, target_fx)
        or not reaper.TrackFX_GetEnabled(track, target_fx) then
        target_fx = -1
        for i = 0, num_fx - 1 do
            if not reaper.TrackFX_GetOffline(track, i) and reaper.TrackFX_GetEnabled(track, i) then
                target_fx = i
                break
            end
        end
    end

    if target_fx < 0 then return end

    reaper.TrackFX_Show(track, target_fx, 3) -- 3 = 显示浮动窗口
end

Main()
