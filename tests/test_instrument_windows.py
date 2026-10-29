"""Independent instrument window routing tests using Lua 5.3 mocks."""
from pathlib import Path
import unittest
from lupa.lua53 import LuaRuntime
SOURCE = (Path(__file__).resolve().parents[1] / 'Tracks/futurewy_Toggle instrument windows.lua').read_text(encoding='utf-8')
SETUP = """
selected={};calls={};errors={};deferred=0
function track(fx,parent,sends,window) return {fx=fx or -1,parent=parent,sends=sends or {},window=window} end
reaper={CountSelectedTracks=function() return #selected end,
GetSelectedTrack=function(_,i) return selected[i+1] end,
TrackFX_GetInstrument=function(t) return t.fx end,
GetParentTrack=function(t) return t.parent end,
GetTrackNumSends=function(t,c) assert(c==0); return #t.sends end,
GetTrackSendInfo_Value=function(t,c,i,k) assert(c==0 and k=='P_DESTTRACK');return t.sends[i+1] end,
TrackFX_GetFloatingWindow=function(t,f) assert(f==t.fx); return t.window end,
TrackFX_Show=function(t,f,mode) calls[#calls+1]={track=t,fx=f,mode=mode} end,
ShowMessageBox=function(e) errors[#errors+1]=e end,
defer=function() deferred=deferred+1 end}
"""
class InstrumentWindowsTests(unittest.TestCase):
    def check(self, setup, assertions):
        lua=LuaRuntime(unpack_returned_tuples=True)
        lua.execute(SETUP+setup)
        lua.execute(SOURCE)
        lua.execute(assertions+'; assert(#errors==0 and deferred==1)')
    def test_empty_and_missing(self):
        self.check('', 'assert(#calls==0)')
        self.check('selected={track()}', 'assert(#calls==0)')
    def test_direct_has_precedence(self):
        self.check('p=track(4);a=track(2,p,{track(5)});selected={a}', 'assert(#calls==1 and calls[1].track==a and calls[1].mode==3)')
    def test_nearest_parent_and_dedup(self):
        self.check('p=track(4);a=track(nil,p);b=track(nil,p);selected={a,b,p}', 'assert(#calls==1 and calls[1].track==p)')
    def test_all_open_close(self):
        self.check('a=track(0,nil,nil,true);b=track(1,nil,nil,true);selected={a,b}', 'assert(#calls==2 and calls[1].mode==2 and calls[2].mode==2)')
    def test_mixed_show_all(self):
        self.check('a=track(0,nil,nil,true);b=track(1);selected={a,b}', 'assert(#calls==2 and calls[1].mode==3 and calls[2].mode==3)')
    def test_send_family_and_breadth_first(self):
        self.check('p=track(8);a=track();b=track();c=track(nil,p);a.sends={b,c};b.sends={track(9)};selected={a}', 'assert(#calls==1 and calls[1].track==p)')
    def test_cycles_and_zero_destinations(self):
        self.check('a=track();b=track();a.sends={0,b};b.sends={a};selected={a}', 'assert(#calls==0)')
    def test_parent_cycle(self):
        self.check('a=track();b=track();a.parent=b;b.parent=a;selected={a}', 'assert(#calls==0)')
if __name__=='__main__': unittest.main()
