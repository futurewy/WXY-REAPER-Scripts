"""Independent BPM regressions using Lua 5.3; no REAPER installation required.
Run: python tests/test_futurewy_bpm_calculator_independent_20261029.py
Requires lupa.lua53 on PYTHONPATH. Helpers are exported only by source injection.
"""
from pathlib import Path
import unittest
from lupa.lua53 import LuaRuntime

SOURCE = Path(__file__).resolve().parents[1] / "Utility" / "futurewy_BPM Calculator.lua"
SCRIPT = SOURCE.read_text(encoding="utf-8")
MARKER = "reaper.atexit(shutdown)"
EXPORT = """
__helpers = {parse=parse_positive, bpm=calculate_bpm, seconds=calculate_seconds,
 new_taps=new_taps, tap=tap, expire=expire_taps, rising=rising,
 snapshot=function() return beats, seconds, bpm, taps, status end,
 reset=reset, shutdown=shutdown}
"""


def runtime(inject=True, close=0):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("""
      clock, held, exit_code = 0, false, 0
      quit_count, init_count, updates = 0, 0, 0
      input_ok, input_text = true, "bad"
      queued = {}
      reaper = {
        time_precise=function() return clock end,
        atexit=function(fn) exit_fn=fn end,
        defer=function(fn) next_frame=fn end,
        GetUserInputs=function() return input_ok, input_text end,
      }
      gfx = {
        w=540, h=480, mouse_x=0, mouse_y=0, mouse_cap=0,
        init=function() init_count=init_count+1 end,
        quit=function() quit_count=quit_count+1 end,
        setfont=function() end, set=function() end, rect=function() end,
        drawstr=function() end, measurestr=function(s) return #s*8 end,
        update=function() updates=updates+1 end,
        getchar=function(char)
          if char == 32 then return held and 1 or 0 end
          if #queued > 0 then return table.remove(queued,1) end
          return exit_code
        end,
      }
    """)
    lua.globals().exit_code = close
    assert SCRIPT.count(MARKER) == 1
    lua.execute(SCRIPT.replace(MARKER, EXPORT + MARKER) if inject else SCRIPT)
    return lua, lua.globals(), lua.globals().__helpers


class FuturewyIndependentBPMTests(unittest.TestCase):
    def test_conversion_and_roundtrip(self):
        _, _, h = runtime()
        self.assertEqual(h.bpm(4, 2), 120)
        self.assertEqual(h.seconds(4, 120), 2)
        self.assertEqual(h.bpm(0.5, 0.25), 120)
        for beats in (0.25, 4, 32):
            for bpm in (20, 97.3, 600):
                self.assertAlmostEqual(h.bpm(beats, h.seconds(beats, bpm)), bpm)

    def test_invalid_math_and_overflow(self):
        _, _, h = runtime()
        for value in (0, -1, float("nan"), float("inf"), "2", None):
            for fn in (h.bpm, h.seconds):
                self.assertIsNone(fn(value, 2))
                self.assertIsNone(fn(2, value))
        self.assertIsNone(h.bpm(1e308, 1e-308))
        self.assertIsNone(h.seconds(1e-308, 1e308))

    def test_decimal_parser(self):
        _, _, h = runtime()
        for text, value in (("4", 4), (" 2.5 ", 2.5), (".25", .25), ("1.", 1)):
            self.assertEqual(h.parse(text), value)
        for text in ("", " ", "0", "-1", "+1", "NaN", "inf", "1e3", "1,5", "1 sec", "0x20", "9"*33, "1..2"):
            result = h.parse(text)
            self.assertIsNone(result[0], text)
            self.assertTrue(result[1], text)

    def test_taps_average_and_window(self):
        _, _, h = runtime()
        state = h.new_taps()
        self.assertTrue(h.tap(state, 0))
        self.assertIsNone(state.bpm)
        h.tap(state, .5)
        self.assertEqual(state.bpm, 120)
        h.tap(state, 1.5)
        self.assertEqual(state.bpm, 80)
        for index in range(1, 21):
            h.tap(state, 1.5 + index * .5)
        self.assertEqual(len(state.intervals), 16)
        self.assertEqual(state.bpm, 120)

    def test_tap_boundaries_and_timeout(self):
        _, _, h = runtime()
        state = h.new_taps()
        h.tap(state, 0)
        self.assertFalse(h.tap(state, .099))
        self.assertEqual(state.last, 0)
        self.assertTrue(h.tap(state, .1))
        self.assertEqual(state.bpm, 600)
        self.assertFalse(h.tap(state, .1))
        self.assertTrue(h.tap(state, 3.1))  # Exactly three seconds is valid.
        self.assertEqual(len(state.intervals), 2)
        self.assertFalse(h.expire(state, 6.1))
        self.assertTrue(h.expire(state, 6.10001))
        self.assertIsNone(state.last)
        self.assertIsNone(state.bpm)
        h.tap(state, 7)
        h.tap(state, 10.01)
        self.assertEqual(len(state.intervals), 0)
        h.tap(state, 9)  # Clock rollback starts a fresh sequence.
        self.assertEqual(state.last, 9)
        for value in (None, "bad", float("inf"), float("nan")):
            self.assertFalse(h.tap(state, value))
            self.assertEqual(state.last, 9)

    def test_startup_close_and_idempotent_cleanup(self):
        for close in (-1, 27):
            lua, g, h = runtime(close=close)
            self.assertEqual(g.init_count, 1)
            self.assertEqual(g.quit_count, 1)
            self.assertEqual(g.updates, 0)
            g.exit_fn()
            h.shutdown()
            self.assertEqual(g.quit_count, 1)
        _, g, _ = runtime(inject=False, close=-1)
        self.assertEqual(g.quit_count, 1)

    def test_space_physical_edges_ignore_queued_repeat(self):
        lua, g, h = runtime()
        g.held = True
        g.clock = 1
        g.next_frame()
        for t in (1.2, 1.5, 2):
            g.clock = t
            lua.execute("queued={32,32,32}")
            g.next_frame()
        state = h.snapshot()[3]
        self.assertEqual(len(state.intervals), 0)
        g.held = False
        g.next_frame()
        g.clock = 2.5
        g.held = True
        g.next_frame()
        self.assertEqual(state.bpm, 40)

    def test_mouse_tap_use_and_reset(self):
        _, g, h = runtime()
        def click(x, y, at):
            g.clock = at
            g.gfx.mouse_x, g.gfx.mouse_y, g.gfx.mouse_cap = x, y, 1
            g.next_frame()
            g.gfx.mouse_cap = 0
            g.next_frame()
        click(30, 330, 1)
        click(30, 330, 2)
        self.assertEqual(h.snapshot()[3].bpm, 60)
        click(280, 330, 2.1)
        self.assertEqual(h.snapshot()[2], 60)
        click(30, 380, 2.2)
        snap = h.snapshot()
        self.assertEqual(snap[:3], (4, 2, 120))
        self.assertIsNone(snap[3].last)

    def test_invalid_and_cancelled_gui_edit_preserves_value(self):
        _, g, h = runtime()
        for ok, text in ((True, "bad"), (True, "0"), (False, "80")):
            g.input_ok, g.input_text = ok, text
            g.gfx.mouse_x, g.gfx.mouse_y, g.gfx.mouse_cap = 30, 100, 1
            g.next_frame()
            self.assertEqual(h.snapshot()[0], 4)
            g.gfx.mouse_cap = 0
            g.next_frame()
        g.input_ok, g.input_text = True, "8"
        g.gfx.mouse_cap = 1
        g.next_frame()
        self.assertEqual(h.snapshot()[0], 8)

    def test_mouse_hold_is_one_tap_and_timeout_retains_copied_bpm(self):
        _, g, h = runtime()
        g.gfx.mouse_x, g.gfx.mouse_y, g.gfx.mouse_cap = 30, 330, 1
        g.clock = 1
        g.next_frame()
        for at in (1.2, 1.4, 1.6):
            g.clock = at
            g.next_frame()
        self.assertEqual(len(h.snapshot()[3].intervals), 0)
        g.gfx.mouse_cap = 0
        g.next_frame()
        g.clock, g.gfx.mouse_cap = 2, 1
        g.next_frame()
        self.assertEqual(h.snapshot()[3].bpm, 60)
        g.gfx.mouse_cap = 0
        g.next_frame()
        g.gfx.mouse_x, g.gfx.mouse_cap = 280, 1
        g.next_frame()
        self.assertEqual(h.snapshot()[2], 60)
        g.gfx.mouse_cap, g.clock = 0, 5.01
        g.next_frame()
        self.assertIsNone(h.snapshot()[3].bpm)
        self.assertEqual(h.snapshot()[2], 60)

    def test_small_window_timeout_and_queued_escape(self):
        lua, g, h = runtime()
        g.gfx.w, g.gfx.h = 300, 120
        g.held, g.clock = True, 1
        g.next_frame()
        g.held, g.clock = False, 4.01
        g.next_frame()
        self.assertIsNone(h.snapshot()[3].last)
        lua.execute("queued={32,27}")
        g.next_frame()
        self.assertEqual(g.quit_count, 1)
        self.assertTrue(h.rising(True, False))
        self.assertFalse(h.rising(True, True))


if __name__ == "__main__":
    unittest.main(verbosity=2)
