"""Offline regressions; requires Python + lupa.lua53, not REAPER.
Run from repository root: python -m unittest discover -s tests -p test_chord_progression_generator_regression.py
Mocks check script control flow, not actual ReaImGui rendering or MIDI/audio routing.
"""
from pathlib import Path
import unittest
from lupa.lua53 import LuaRuntime

SCRIPT = Path(__file__).resolve().parents[1] / "MIDI" / "ChordProgressionGenerator.lua"
SOURCE = SCRIPT.read_text(encoding="utf-8")
MOCK = r'''
now = 0
messages, midi, deferred = {}, {}, {}
ends, creates = 0, 0
visible, window_open = true, true
reaper = setmetatable({}, {__index = function(_, k)
  if k:match("^ImGui_") then return function() return false end end
end})
reaper.ShowMessageBox = function(text) messages[#messages+1] = text end
reaper.ImGui_CreateContext = function() creates = creates+1 return {} end
reaper.ImGui_Begin = function() return visible, window_open end
reaper.ImGui_End = function() ends = ends+1 end
reaper.defer = function(fn) deferred[#deferred+1] = fn end
reaper.atexit = function(fn) exit_callback = fn end
reaper.time_precise = function() return now end
reaper.StuffMIDIMessage = function(mode,status,note,velocity)
  midi[#midi+1] = {mode,status,note,velocity}
end
ARNIE_TEST_HOOK = {}
function upvalue(fn, name)
  for i=1,100 do
    local n,v = debug.getupvalue(fn,i)
    if not n then break end
    if n == name then return v end
  end
  error("upvalue not found: " .. name)
end
'''

class ChordProgressionGeneratorRegression(unittest.TestCase):
    def load_script(self, setup=""):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.execute(MOCK)
        lua.execute(setup)
        lua.execute(SOURCE)
        return lua

    def test_missing_extension_exits_before_context_or_defer(self):
        lua = self.load_script('setmetatable(reaper,nil); reaper.ImGui_CreateContext=nil')
        lua.execute('assert(#messages == 1 and creates == 0 and #deferred == 0)')

    def test_partial_extension_reports_missing_api(self):
        lua = self.load_script('reaper.ImGui_TextWrapped=false')
        lua.execute('assert(#messages == 1 and messages[1]:find("ImGui_TextWrapped",1,true)); assert(creates==0)')

    def test_slash_bass_rejects_trailing_garbage(self):
        lua = self.load_script()
        lua.execute('''
for _,s in ipairs({"C#garbage", "Bb7", "C##", "C#/D"}) do
  assert(ARNIE_TEST_HOOK.parse_note_name(s)==nil)
  assert(ARNIE_TEST_HOOK.parse_chord("G/"..s)==nil)
end
assert(ARNIE_TEST_HOOK.parse_note_name(" C# ")==1)
assert(ARNIE_TEST_HOOK.parse_note_name("Bb")==10)
assert(ARNIE_TEST_HOOK.parse_chord("G/C").bass==0)
''')

    def test_sharp_quality_url_is_path_not_fragment(self):
        lua = self.load_script()
        lua.execute('''
for _,s in ipairs({"C7#9", "F#7#5"}) do
  local c=assert(ARNIE_TEST_HOOK.parse_chord(s))
  local url=ARNIE_TEST_HOOK.chord_site_url(c)
  assert(not url:find("#",1,true))
  assert(url:find("%23",1,true))
end
assert(ARNIE_TEST_HOOK.chord_site_url(ARNIE_TEST_HOOK.parse_chord("C")) ==
 "https://www.all-guitar-chords.com/chords/index/c/major")
''')

    def test_playback_honors_gap_before_next_chord(self):
        lua = self.load_script()
        lua.execute('''
local loop=deferred[1]
local update=upvalue(loop,"update_playback")
local queue=upvalue(update,"queue")
queue[1]={notes={60},at=0,off=0.95}
queue[2]={notes={62},at=1,off=1.95}
update()
assert(#midi==1 and midi[1][2]==0x90)
now=0.96; update()
assert(#midi==2 and midi[2][2]==0x80 and midi[2][3]==60)
now=1; update()
assert(#midi==3 and midi[3][2]==0x90 and midi[3][3]==62)
now=1.96; update()
assert(#midi==4 and midi[4][2]==0x80)
''')

    def test_collapsed_window_does_not_call_end(self):
        lua = self.load_script()
        lua.execute('visible=false; deferred[1](); assert(ends==0 and #deferred==2)')

    def test_visible_window_calls_end_once(self):
        lua = self.load_script()
        lua.execute('deferred[1](); assert(ends==1 and #deferred==2)')

    def test_close_panics_without_rescheduling(self):
        lua = self.load_script()
        lua.execute('''
visible=false; window_open=false; deferred[1]()
assert(#deferred==1 and #midi==2)
assert(midi[1][2]==0xB0 and midi[1][3]==120)
assert(midi[2][3]==123)
''')

    def test_exit_releases_active_notes(self):
        lua = self.load_script()
        lua.execute('''
local update=upvalue(deferred[1],"update_playback")
local queue=upvalue(update,"queue")
queue[1]={notes={60,64},at=0,off=1}
update(); exit_callback()
assert(midi[3][2]==0x80 and midi[3][3]==60)
assert(midi[4][2]==0x80 and midi[4][3]==64)
''')

    def test_generation_structure_and_ascending_constraints(self):
        lua = self.load_script()
        lua.execute('''
local h=ARNIE_TEST_HOOK
local start=assert(h.parse_chord("G"))
local target=assert(h.parse_chord("Cm"))
local key={pc=0,minor=true}
local results,total=h.generate(start,target,2,key,"auto")
assert(total>0 and #results>0 and #results<=800)
for i,item in ipairs(results) do
  assert(#item.chain==4 and #item.voicings==4)
  assert(item.chain[1]==start and item.chain[4]==target)
  if i>1 then assert(item.cost>=results[i-1].cost) end
end
local up,count,d=h.generate_up(h.parse_chord("C"),h.parse_chord("F"),2,{pc=0,minor=false})
assert(d==5 and count>0)
for _,item in ipairs(up) do
  for i=2,#item.chain do
    local step=(item.chain[i].pc-item.chain[i-1].pc)%12
    assert(step==1 or step==2)
  end
end
assert(h.generate_up(start,target,1,key)==nil)
''')

if __name__ == "__main__":
    unittest.main()
