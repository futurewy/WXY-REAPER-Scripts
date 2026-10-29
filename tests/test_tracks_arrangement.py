"""Lua 5.3 regression tests with mocked REAPER APIs; not host integration tests."""
from pathlib import Path
from lupa.lua53 import LuaRuntime
ROOT = Path(__file__).resolve().parents[1]

def run(relative, setup, checks):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(setup)
    lua.execute((ROOT / relative).read_text(encoding='utf-8'))
    lua.execute(checks)

TRACK = 'Tracks/hide offlinefx track.lua'
TRACK_SETUP = r'''
tracks={{selected=true,fx={true,true},tcp=0,mixer=1},
        {selected=false,fx={true,true},tcp=1,mixer=1},
        {selected=false,fx={false,true},tcp=1,mixer=1},
        {selected=true,fx={},tcp=0,mixer=0}}
refresh=0; undo=0; errors=0
reaper={CountTracks=function() return #tracks end,
GetTrack=function(_,i) return tracks[i+1] end,
TrackFX_GetCount=function(t) return #t.fx end,
IsTrackSelected=function(t) return t.selected end,
TrackFX_SetOffline=function(t,i,v) assert(type(v)=='boolean'); t.fx[i+1]=v end,
TrackFX_GetOffline=function(t,i) return t.fx[i+1] end,
SetMediaTrackInfo_Value=function(t,k,v) if k=='B_SHOWINTCP' then t.tcp=v else t.mixer=v end end,
Undo_BeginBlock=function() undo=undo+1 end, Undo_EndBlock=function() undo=undo-1 end,
PreventUIRefresh=function(v) refresh=refresh+v end,
TrackList_AdjustWindows=function() end, UpdateArrange=function() end,
ShowMessageBox=function() errors=errors+1 end}
'''
run(TRACK, TRACK_SETUP, '''
assert(tracks[1].fx[1]==false and tracks[1].fx[2]==false)
assert(tracks[1].tcp==1 and tracks[1].mixer==1)
assert(tracks[2].tcp==0 and tracks[2].mixer==0)
assert(tracks[3].tcp==1 and tracks[3].mixer==1)
assert(tracks[4].tcp==0 and tracks[4].mixer==0)
assert(refresh==0 and undo==0 and errors==0)
''')
run(TRACK, TRACK_SETUP + "reaper.TrackFX_SetOffline=function() error('injected') end",
    'assert(refresh==0 and undo==0 and errors==1)')
MOVE = 'Items/Move_Items_Markers_Regions_In_TimeSelection-移动所有.lua'
MOVE_SETUP = r'''
start=10; finish=20; accepted=true; input='-1'; refresh=0; undo=0; errors=0
items={{pos=9},{pos=10},{pos=15}}
markers={{id=1,pos=10,finish=0,region=false,color=123,name='A'},
         {id=2,pos=11,finish=15,region=true,color=456,name='B'},
         {id=3,pos=9,finish=0,region=false,color=789,name='C'}}
moved={}; enumcalls=0
reaper={
GetSet_LoopTimeRange=function(set,_,s,e) if set then start=s;finish=e end return start,finish end,
GetUserInputs=function() return accepted,input end,
TimeMap2_timeToQN=function(_,t) return t end, TimeMap2_QNToTime=function(_,t) return t end,
CountMediaItems=function() return #items end, GetMediaItem=function(_,i) return items[i+1] end,
GetMediaItemInfo_Value=function(t) return t.pos end,
SetMediaItemInfo_Value=function(t,_,p) t.pos=p end,
CountProjectMarkers=function() return 3,2,1 end,
EnumProjectMarkers3=function(_,i) enumcalls=enumcalls+1; local m=markers[i+1];return 1,m.region,m.pos,m.finish,m.name,m.id,m.color end,
SetProjectMarker3=function(_,id,region,p,e,name,color)
  assert(enumcalls==3); assert(not moved[id]); moved[id]={pos=p,finish=e,color=color}
  table.sort(markers,function(a,b) return a.id>b.id end)
end,
Undo_BeginBlock=function() undo=undo+1 end, Undo_EndBlock=function() undo=undo-1 end,
PreventUIRefresh=function(v) refresh=refresh+v end, UpdateArrange=function() end,
ShowMessageBox=function() errors=errors+1 end}
'''
run(MOVE, MOVE_SETUP, '''
assert(items[1].pos==9 and items[2].pos==6 and items[3].pos==11)
assert(moved[1].pos==6 and moved[1].color==123)
assert(moved[2].pos==7 and moved[2].finish==11 and moved[2].color==456)
assert(not moved[3]);assert(start==6 and finish==16)
assert(refresh==0 and undo==0 and errors==0)
''')
for override in ["accepted=false", "finish=start", "input='invalid'", "input='1e999'", "input='-4'", "input='0'"]:
    run(MOVE, MOVE_SETUP + override, 'assert(refresh==0 and undo==0 and enumcalls==0 and items[2].pos==10)')
run(MOVE, MOVE_SETUP + "reaper.SetMediaItemInfo_Value=function() error('injected') end",
    'assert(refresh==0 and undo==0 and errors==1)')
print('PASS: tracks / arrangement (11 mocked regression scenarios)')
