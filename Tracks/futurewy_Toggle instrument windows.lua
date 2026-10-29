-- @description Toggle instrument windows for selected tracks (parent and send lookup)
-- @version 1.0
-- @author futurewy
-- @about
--   Independent implementation using native REAPER APIs; no SWS required.
--   Finds the first instrument on each selected track, then its nearest parent,
--   then searches send destinations breadth-first (including their parents).
--   Send traversal handles cycles. Shared instruments are processed once.
--   If any resolved window is closed, show all; otherwise close all.
--   This changes floating windows only, not FX bypass, offline state or routing.
-- @changelog
--   Initial independent implementation with native routing lookup and deduplication.

local function instrument_in_family(track)
    local visited = {}
    while track and not visited[track] do
        visited[track] = true
        local fx = reaper.TrackFX_GetInstrument(track)
        if fx and fx >= 0 then return {track = track, fx = fx} end
        track = reaper.GetParentTrack(track)
    end
end

local function resolve_instrument(track)
    local found = instrument_in_family(track)
    if found then return found end
    local queue, seen, head = {track}, {[track] = true}, 1
    while head <= #queue do
        local current = queue[head]
        head = head + 1
        for send = 0, reaper.GetTrackNumSends(current, 0) - 1 do
            local destination = reaper.GetTrackSendInfo_Value(current, 0, send, 'P_DESTTRACK')
            if destination and destination ~= 0 and not seen[destination] then
                seen[destination] = true
                found = instrument_in_family(destination)
                if found then return found end
                queue[#queue + 1] = destination
            end
        end
    end
end

local function main()
    local targets, unique, show = {}, {}, false
    for i = 0, reaper.CountSelectedTracks(0) - 1 do
        local track = reaper.GetSelectedTrack(0, i)
        if track then
            local target = resolve_instrument(track)
            if target then
                local by_fx = unique[target.track]
                if not by_fx then by_fx = {}; unique[target.track] = by_fx end
                if not by_fx[target.fx] then
                    by_fx[target.fx] = true
                    targets[#targets + 1] = target
                    if not reaper.TrackFX_GetFloatingWindow(target.track, target.fx) then
                        show = true
                    end
                end
            end
        end
    end
    for _, target in ipairs(targets) do
        reaper.TrackFX_Show(target.track, target.fx, show and 3 or 2)
    end
end

local ok, err = xpcall(main, debug.traceback)
if not ok then reaper.ShowMessageBox(tostring(err), 'Instrument window toggle', 0) end
-- Window-only operation: do not create an unnecessary project undo point.
reaper.defer(function() end)
