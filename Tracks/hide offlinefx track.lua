-- @description Show selected tracks' FX and hide unselected fully offline FX tracks
-- @version 1.1
-- @author futurewy
-- @about
--   Selected tracks with FX are shown in both TCP and mixer, with FX online.
--   Unselected tracks with all FX offline are hidden. Tracks without FX are unchanged.
-- @changelog
--   Use a Lua boolean for the offline flag; show partially hidden selected tracks.
--   Always restore UI refresh and close the undo block after errors.

if reaper.CountTracks(0) == 0 then return end
reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)
local ok, err = xpcall(function()
    for i = 0, reaper.CountTracks(0) - 1 do
        local track = reaper.GetTrack(0, i)
        local count = reaper.TrackFX_GetCount(track)
        if count > 0 then
            if reaper.IsTrackSelected(track) then
                for fx = 0, count - 1 do
                    -- Lua treats numeric zero as true: the API requires false here.
                    reaper.TrackFX_SetOffline(track, fx, false)
                end
                reaper.SetMediaTrackInfo_Value(track, 'B_SHOWINTCP', 1)
                reaper.SetMediaTrackInfo_Value(track, 'B_SHOWINMIXER', 1)
            else
                local all_offline = true
                for fx = 0, count - 1 do
                    if not reaper.TrackFX_GetOffline(track, fx) then
                        all_offline = false
                        break
                    end
                end
                if all_offline then
                    reaper.SetMediaTrackInfo_Value(track, 'B_SHOWINTCP', 0)
                    reaper.SetMediaTrackInfo_Value(track, 'B_SHOWINMIXER', 0)
                end
            end
        end
    end
end, debug.traceback)
reaper.PreventUIRefresh(-1)
reaper.TrackList_AdjustWindows(false)
reaper.UpdateArrange()
reaper.Undo_EndBlock('Show selected FX tracks and hide offline FX tracks', -1)
if not ok then reaper.ShowMessageBox(tostring(err), 'Track visibility error', 0) end
