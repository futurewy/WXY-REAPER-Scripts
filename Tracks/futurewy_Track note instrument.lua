-- @description Write the instrument and preset of each selected track into its track note
-- @version 1.0
-- @author futurewy
-- @about
--   Reads the instrument of every selected track and writes a "Sound:" line
--   into the track note. Tracks that already carry the same line are left
--   untouched.
--
--   Uses only native REAPER actions, so no extension is required.
-- @changelog
--   v1.0: Track notes are read and written with the native
--   GetSetMediaTrackInfo_String action instead of the SWS extension.

local function getInstrumentInfo(track)
    -- Prefer the instrument, otherwise fall back to the first effect.
    local fx = reaper.TrackFX_GetInstrument(track)
    if fx == -1 and reaper.TrackFX_GetCount(track) > 0 then
        fx = 0
    end
    if fx == -1 then return nil end

    local _, fxName = reaper.TrackFX_GetFXName(track, fx, "")
    fxName = fxName:gsub("^%w+:%s*", ""):gsub("%s*%b()$", "")

    local _, preset = reaper.TrackFX_GetPreset(track, fx, "")
    if preset == nil or preset == "" then preset = "Active Preset" end

    return fxName .. " | " .. preset
end

local function getNote(track)
    local ok, note = pcall(reaper.GetSetMediaTrackInfo_String, track, "P_NAME", "", false)
    if ok and note then return note end
    return ""
end

local function setNote(track, note)
    reaper.GetSetMediaTrackInfo_String(track, "P_NAME", note, true)
end

local count = reaper.CountSelectedTracks(0)
if count == 0 then
    reaper.ShowMessageBox("Select the tracks to extract instrument information from.", "Nothing selected", 0)
    return
end

reaper.Undo_BeginBlock()
local written = 0

for i = 0, count - 1 do
    local track = reaper.GetSelectedTrack(0, i)
    local info = getInstrumentInfo(track)
    if info then
        local line = "Sound: " .. info
        local note = getNote(track)
        if not note:find(line, 1, true) then
            if note ~= "" then
                note = note .. string.char(10) .. line
            else
                note = line
            end
            setNote(track, note)
            written = written + 1
        end
    end
end

reaper.Undo_EndBlock("Write instrument info into track notes", -1)
reaper.ShowMessageBox(string.format("Wrote instrument information to %d of %d tracks.", written, count), "Done", 0)
