"""Headless Lua 5.3 regression checks; requires lupa (PYTHONPATH may supply it).
Run: python -m unittest discover -s tests -p test_notation_revoice_review.py -v
Only final entry-point calls are replaced to expose local helpers to these tests.
"""
from pathlib import Path
import unittest
from lupa.lua53 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
SANITIZER = ROOT / "MIDI" / "MIDI Notation Sanitizer-MIDI记谱清洗器.lua"
REVOICE = ROOT / "MIDI" / "RevoiceSelectedChord-和弦替换.lua"


def load_helpers(path, entry, exports):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("reaper={}")
    source = path.read_text(encoding="utf-8")
    prefix, sep, tail = source.rpartition(entry)
    assert sep and not tail.strip(), "Unexpected script entry point"
    lua.execute(prefix + exports)
    return lua


class NotationRevoiceReviewTests(unittest.TestCase):
    def sanitizer(self):
        return load_helpers(SANITIZER, "openOptions()", "review={sanitize=sanitizeTake,write=writeBack,apply=applyNotes,post=postProcess}")

    def chord(self):
        return load_helpers(REVOICE, "main()", "review={parse=parse,plan=plan_conversion,collision=has_collision,additions=plan_additions}")

    def test_notation_fractional_ppq_writes_even_at_normalized_velocity(self):
        self.sanitizer().execute('''
          reaper.TimeMap2_QNToTime=function(_,q) return q end
          reaper.MIDI_GetPPQPosFromProjTime=function(_,q) return q*960 end
          local notes={{idx=0,s=0.1,e=240.1,sq=0,eq=0.25,vel=100}}
          local writes=0
          reaper.MIDI_SetNote=function(_,_,_,_,s,e) assert(s==0 and e==240);writes=writes+1;return true end
          assert(review.write({},notes)==1)
          review.apply({},notes)
          assert(writes==1)
        ''')

    def test_notation_failed_count_aborts_before_mutation(self):
        self.sanitizer().execute('''
          reaper.MIDI_CountEvts=function() return false,0,0,0 end
          local ok,err=pcall(review.sanitize,{}, {})
          assert(not ok and err:find("无法统计音符",1,true))
        ''')

    def test_notation_failed_note_aborts_before_mutation(self):
        self.sanitizer().execute('''
          reaper.MIDI_CountEvts=function() return true,1,0,0 end
          reaper.MIDI_GetNote=function() return false end
          local ok,err=pcall(review.sanitize,{}, {})
          assert(not ok and err:find("无法读取音符",1,true))
        ''')

    def test_notation_cleanup_retains_bend_and_short_notes(self):
        self.sanitizer().execute('''
          local deleted,writes,sorted=0,0,0
          reaper.MIDI_CountEvts=function() return true,1,2,0 end
          reaper.MIDI_GetNote=function() return true,true,false,0,5,0,60,50 end
          reaper.TimeMap2_timeToQN=function(_,t) return t end
          reaper.TimeMap2_QNToTime=function(_,q) return q end
          reaper.MIDI_GetProjTimeFromPPQPos=function(_,p) return p/960 end
          reaper.MIDI_GetPPQPosFromProjTime=function(_,q) return q*960 end
          reaper.MIDI_DisableSort=function() end
          reaper.MIDI_Sort=function() sorted=sorted+1 end
          reaper.MIDI_SetNote=function(_,_,_,_,s,e,_,_,v) assert(s==0 and e==5 and v==100);writes=writes+1;return true end
          reaper.MIDI_GetCC=function(_,i) return true,false,false,0,i==0 and 0xB0 or 0xE0 end
          reaper.MIDI_DeleteCC=function(_,i) assert(i==0);deleted=deleted+1;return true end
          local ch,dl,tot,cc=review.sanitize({}, {mode=1,gridQN=0.25,weakVelocity=5,thresholdQN=0})
          assert(ch==1 and dl==0 and tot==1 and cc==1)
          assert(writes==1 and deleted==1 and sorted==1)
        ''')

    def test_notation_duplicate_and_channel_tail_rules(self):
        self.sanitizer().execute('''
          local a={pitch=60,ch=0,s=0,e=100};local b={pitch=60,ch=0,s=0,e=200}
          local c={pitch=64,ch=0,s=100,e=300};local d={pitch=67,ch=1,s=100,e=400}
          review.post({a,b,c,d},2)
          assert(a.del or b.del)
          assert(c.e==300 and d.e==400)
        ''')

    def test_revoice_aliases_and_slash_rejection(self):
        self.chord().execute('''
          assert(review.parse("C7add9").name=="C9")
          assert(review.parse("Cm6/9").name=="Cm6add9")
          assert(review.parse("F♯maj7").root==6)
          assert(not review.parse("C/E"))
        ''')

    def test_revoice_collision_existing_vs_new_unison(self):
        self.chord().execute('''
          local a={index=0,pitch=60,channel=0,startppq=0,endppq=100}
          local b={index=1,pitch=64,channel=0,startppq=0,endppq=100}
          assert(review.collision({a,b},{a,b},{60,60}))
          b.pitch=60
          assert(not review.collision({a,b},{a,b},{62,62}))
          b.channel=1
          assert(not review.collision({a,b},{a,b},{62,62}))
        ''')

    def test_revoice_plans_seventh_addition_without_writes(self):
        self.chord().execute('''
          local notes={}
          for i,p in ipairs({60,64,67}) do notes[i]={index=i-1,pitch=p,channel=0,startppq=0,endppq=960,velocity=90,muted=false} end
          local additions,err=review.additions(notes,notes,{60,64,67},review.parse("C"),review.parse("Cmaj7"))
          assert(additions,err)
          assert(#additions==1)
          local n=additions[1]
          assert(n.pitch%12==11 and n.velocity==90 and n.startppq==0 and n.endppq==960)
        ''')


if __name__ == "__main__":
    unittest.main()
