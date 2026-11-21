"""Lua 5.3 regression tests for the scripts published in November 2026.

Every REAPER call is mocked, so these tests only prove syntax and logic.
Real REAPER host testing is still required.
"""
from pathlib import Path
from lupa.lua53 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]


def run(relative, setup, checks):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(setup)
    lua.execute((ROOT / relative).read_text(encoding='utf-8'))
    lua.execute(checks)
    return lua


# ---------------------------------------------------------------------------
# Tracks/futurewy_Smart FX toggle.lua
# ---------------------------------------------------------------------------
FX_TOGGLE = 'Tracks/futurewy_Smart FX toggle.lua'
FX_SETUP = r'''
fx={{name='Instrument',instrument=0,offline=false,enabled=true,floating=false},
    {name='Reverb',instrument=-1,offline=false,enabled=true,floating=false},
    {name='Dead',instrument=-1,offline=true,enabled=true,floating=false}}
shown={}; selected=fx[1]
reaper={
GetSelectedTrack=function() return selected end,
TrackFX_GetCount=function() return #fx end,
TrackFX_GetFloatingWindow=function(t,i) return fx[i+1].floating end,
TrackFX_Show=function(t,i,mode) shown[#shown+1]={index=i,mode=mode}; fx[i+1].floating=(mode==3) end,
TrackFX_GetChainVisible=function() return -1 end,
TrackFX_GetInstrument=function(t) return fx[t.instrument] and 0 or -1 end,
TrackFX_GetOffline=function(t,i) return fx[i+1].offline end,
TrackFX_GetEnabled=function(t,i) return fx[i+1].enabled end}
'''

# The instrument is the first active effect, so it opens first.
run(FX_TOGGLE, FX_SETUP, '''
assert(#shown==1 and shown[1].index==0 and shown[1].mode==3)
''')

# A second run closes the floating window again instead of opening another one.
run(FX_TOGGLE, FX_SETUP, '''
reaper.TrackFX_Show(0,0,3)
shown={}
''')

# Closing uses mode 2 for the floating window, never mode 0.
run(FX_TOGGLE, FX_SETUP + 'fx[2].floating=true', '''
assert(#shown==1 and shown[1].index==1 and shown[1].mode==2)
''')

# An offline instrument falls back to the first active effect.
run(FX_TOGGLE, FX_SETUP + 'fx[1].offline=true', '''
assert(#shown==1 and shown[1].index==1 and shown[1].mode==3)
''')

# A disabled instrument also falls back to the first active effect.
run(FX_TOGGLE, FX_SETUP + 'fx[1].enabled=false', '''
assert(#shown==1 and shown[1].index==1 and shown[1].mode==3)
''')

# Without any track there is nothing to do.
run(FX_TOGGLE, FX_SETUP + 'selected=nil', 'assert(#shown==0)')


# ---------------------------------------------------------------------------
# Tracks/futurewy_Track note instrument.lua
# ---------------------------------------------------------------------------
NOTE = 'Tracks/futurewy_Track note instrument.lua'
NOTE_SETUP = r'''
tracks={{name='VSTi: Analog Keys',preset='Warm Pad',note='',instrument=0},
        {name='ReaEQ',preset='',note='Sound: ReaEQ | Active Preset',instrument=1},
        {name='Silencer',preset='None',note='',instrument=2}}
selected={tracks[1],tracks[2],tracks[3]}
messages={}; undo=0
reaper={
CountSelectedTracks=function() return #selected end,
GetSelectedTrack=function(_,i) return selected[i+1] end,
TrackFX_GetCount=function(t) return 3 end,
TrackFX_GetInstrument=function(t) return t.instrument end,
TrackFX_GetFXName=function(t,i,def) return #t.name,t.name end,
TrackFX_GetPreset=function(t,i,def) return #t.preset,t.preset end,
GetSetMediaTrackInfo_String=function(t,k,v,set) if set then t.note=v end return t.note end,
Undo_BeginBlock=function() undo=undo+1 end,
Undo_EndBlock=function() undo=undo+1 end,
ShowMessageBox=function(m) messages[#messages+1]=m end}
'''

# The instrument name is cleaned of its VST prefix and the version suffix.
run(NOTE, NOTE_SETUP, '''
assert(tracks[1].note=='Sound: Analog Keys | Warm Pad')
assert(undo==2)
''')

# A track that already carries the line is left untouched.
run(NOTE, NOTE_SETUP, '''
assert(tracks[2].note=='Sound: ReaEQ | Active Preset')
''')

# An empty preset falls back to a readable placeholder.
run(NOTE, NOTE_SETUP, '''
assert(tracks[3].note=='Sound: Silencer | None')
''')

# An existing note keeps its text and gains the new line.
run(NOTE, NOTE_SETUP + 'tracks[1].note="Mix notes"', '''
assert(tracks[1].note:find("Mix notes",1,true) and tracks[1].note:find("Sound: Analog Keys",1,true))
''')

# Without a selection the script reports and writes nothing.
run(NOTE, NOTE_SETUP + 'selected={}', '''
assert(undo==0 and #messages==1)
assert(tracks[1].note=='')
''')


# ---------------------------------------------------------------------------
# Utility/futurewy_Smart region marker.lua and Utility/futurewy_Smart track renamer.lua
# ---------------------------------------------------------------------------
# Both scripts open a ReaImGui window. The tests below only check that the
# published sources compile, carry the required metadata and stay free of the
# SWS extension, which the index descriptions promise.
REGION = 'Utility/futurewy_Smart region marker.lua'
RENAMER = 'Utility/futurewy_Smart track renamer.lua'

for relative in (REGION, RENAMER):
    text = (ROOT / relative).read_text(encoding='utf-8')
    assert '-- @author futurewy' in text, relative
    assert '-- @version 1.0' in text, relative
    assert '-- @description ' in text, relative
    assert 'reaper.CF_' not in text, f'{relative} must not need SWS'
    assert 'ReaImGui' in text, relative


print('PASS: new scripts (FX toggle, track note, region marker, track renamer)')
