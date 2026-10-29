"""Lua 5.3 mocked regressions; no REAPER installation or project writes.
Run with bundled Python and PYTHONPATH pointing to workspace .reaper-test-tools.
Private helpers are exposed by test-side injection ONLY, never production hooks.
"""
from pathlib import Path
import unittest
from lupa.lua53 import LuaRuntime

SOURCE = Path(__file__).resolve().parents[1] / "Utility" / "ProjectNotes_ZoomReader.lua"
SCRIPT = SOURCE.read_text(encoding="utf-8")
EXPORT = """
return {save=save,getstate=getstate,encode=encode,decode=decode,rowsOf=rowsOf,
  buildLayout=buildLayout,layout=function() return layout end,
  readerCopy=readerCopy,readerBounds=readerBounds,readerWord=readerWord,
  selection=readerSelection,currentRegion=currentRegion,matches=matches,
  font=font,uiFont=uiFont,loop=loop}
"""


def fixture(font_failure=False, family_failure=False, all_fonts_fail=False):
    lua = LuaRuntime(unpack_returned_tuples=True)
    g = lua.globals()
    g.font_failure, g.family_failure, g.all_fonts_fail = font_failure, family_failure, all_fonts_fail
    lua.execute(r'''
notes, ext, writes, dirty, begins, ends, messages = 'original', {}, 0, 0, 0, 0, 0
closed, write_failure, write_error = false, false, false
playing, position, cursor = 0, 0, 0
I = {
 CreateContext=function() return {} end, SetConfigVar=function() end,
 CreateFontFromFile=function(path)
   if font_failure or all_fonts_fail then error('missing font') end
   return 'file-font'
 end,
 CreateFont=function(name)
   if all_fonts_fail or (family_failure and name=='Microsoft YaHei') then error('family unavailable') end
   return name
 end,
 Attach=function(ctx,object) assert(object) end,
 CreateFunctionFromEEL=function() return {} end, Function_SetValue=function() end,
 CalcTextSize=function(ctx,text) return utf8.len(text)*10 end,
}
package.preload.imgui=function() return function(version) assert(version=='0.10'); return I end end
reaper = {
 ImGui_GetBuiltinPath=function() return '.' end,
 ShowMessageBox=function() messages=messages+1;return 0 end,
 GetExtState=function(section,key) return ext[key] or '' end,
 SetExtState=function(section,key,value,persist) assert(persist);ext[key]=value end,
 ValidatePtr=function(p,kind) assert(kind=='ReaProject*');return not closed end,
 GetSetProjectNotes=function(p,set,value)
   assert(p==1 and type(set)=='boolean' and type(value)=='string')
   if set then
     writes=writes+1
     if write_error then error('write error') end
     if not write_failure then notes=value end
   end
   return notes
 end,
 Undo_BeginBlock2=function() begins=begins+1 end,
 Undo_EndBlock2=function() ends=ends+1 end,
 MarkProjectDirty=function() dirty=dirty+1 end,
 atexit=function(fn) exitfn=fn end,
 GetProjectName=function() return 'Project' end,
 GetPlayStateEx=function() return playing end,
 GetPlayPositionEx=function() return position end,
 GetCursorPositionEx=function() return cursor end,
}
''')
    prefix, final = SCRIPT.rsplit("\nloop()", 1)
    assert final.strip() == ""
    api = lua.execute(prefix + "\n" + EXPORT)
    return lua, g, api


class ProjectNotesZoomReaderRegression(unittest.TestCase):
    def test_full_source_compiles_and_version(self):
        lua, _, _ = fixture()
        lua.execute("assert(load(...))", SCRIPT)
        self.assertIn("-- @author futurewy", SCRIPT)
        self.assertIn("-- @version 5.1.2", SCRIPT)

    def test_optional_file_font_falls_back(self):
        _, _, a = fixture(font_failure=True)
        self.assertEqual(a.font, a.uiFont)

    def test_portable_family_fallback(self):
        _, _, a = fixture(font_failure=True, family_failure=True)
        self.assertEqual(a.font, "sans-serif")

    def test_all_font_failures_exit_without_throw(self):
        _, g, a = fixture(all_fonts_fail=True)
        self.assertIsNone(a)
        self.assertEqual(g.messages, 1)

    def test_save_readback_and_backup(self):
        _, g, a = fixture()
        s = a.getstate(1)
        s.text = "歌词\nsecond\r\nthird"
        self.assertTrue(a.save(1, s, False))
        self.assertEqual(g.notes, s.text)
        self.assertEqual(s.base, s.text)
        self.assertEqual(a.decode(g.ext.last_backup_hex), "original")
        self.assertEqual((g.writes, g.dirty, g.begins, g.ends), (1, 1, 1, 1))
        self.assertTrue(a.save(1, s, False))
        self.assertEqual(g.writes, 1)

    def test_external_conflict_never_overwritten(self):
        _, g, a = fixture()
        s = a.getstate(1); s.text = "draft"; g.notes = "external"
        self.assertFalse(a.save(1, s, False))
        self.assertTrue(s.conflict)
        self.assertEqual((g.notes, g.writes, s.base), ("external", 0, "original"))
        self.assertTrue(a.save(1, s, True))
        self.assertEqual(a.decode(g.ext.last_backup_hex), "external")

    def test_failed_and_throwing_writes_keep_draft_and_balance_undo(self):
        for mode in ("write_failure", "write_error"):
            _, g, a = fixture()
            s = a.getstate(1); s.text = "draft\n中文"; g[mode] = True
            self.assertFalse(a.save(1, s, False))
            self.assertEqual((s.base, s.text, s.conflict), ("original", "draft\n中文", True))
            self.assertEqual((g.begins, g.ends), (1, 1))
            g.exitfn()
            self.assertEqual(a.decode(g.ext.recovery_drafts_hex), "Project\ndraft\n中文")
            self.assertNotIn("\n", g.ext.recovery_drafts_hex)

    def test_closed_project_preserves_draft_without_write(self):
        _, g, a = fixture()
        s = a.getstate(1);s.text = "draft";g.closed = True
        self.assertFalse(a.save(1, s, False))
        self.assertEqual(g.writes, 0)
        g.exitfn()
        self.assertIn("draft", a.decode(g.ext.recovery_drafts_hex))

    def test_hex_roundtrip_and_invalid_payload(self):
        _, _, a = fixture()
        value = "中文\n\r\t=;" + chr(0) + "end"
        self.assertEqual(a.decode(a.encode(value)), value)
        self.assertIsNone(a.decode("0"))
        self.assertIsNone(a.decode("GG"))
        self.assertEqual(a.decode(""), "")

    def test_layout_wrapping_tags_and_copy_selection(self):
        lua, _, a = fixture()
        a.buildLayout("[#3|Verse]\nabcdef\n\nnext", 30, lua.table())
        lines = a.layout().lines
        self.assertTrue(lines[1].header)
        body = next(i for i in range(1, len(lines)+1) if lines[i].text == "abc")
        self.assertEqual(lines[body+1].text, "def")
        self.assertTrue(lines[body+1].softWrap)
        a.selection.anchor = lua.table(line=body, byte=0)
        a.selection.focus = lua.table(line=body+1, byte=3)
        self.assertEqual(a.readerCopy(lines), "abcdef")
        self.assertIsNone(lines[len(lines)].tag)

    def test_unicode_word_and_bounds(self):
        lua, _, a = fixture()
        bounds = a.readerBounds("中A文")
        self.assertEqual([bounds[i] for i in range(1, len(bounds)+1)], [0, 3, 4, 7])
        lines = lua.table_from([lua.table(text="hello "), lua.table(text="world!", softWrap=True)])
        lo, hi = a.readerWord(lines, lua.table(line=2, byte=2))
        self.assertEqual((lo.line, lo.byte, hi.line, hi.byte), (1, 6, 2, 5))

    def test_region_follow_matching_and_overlap(self):
        lua, g, a = fixture()
        regions = lua.table_from([lua.table(id=1,name="Verse",start=0,finish=20),
                                  lua.table(id=2,name="Inner",start=5,finish=10)])
        g.cursor = 6
        self.assertEqual(a.currentRegion(1, regions).id, 2)
        g.playing, g.position = 1, 12
        self.assertEqual(a.currentRegion(1, regions).id, 1)
        self.assertTrue(a.matches(lua.table(id=1,name="old"), regions[1]))
        self.assertFalse(a.matches(lua.table(id=9,name="Verse"), regions[1]))

    def test_reader_surface_and_interaction_code_unchanged(self):
        self.assertIn("I.PushStyleVar(ctx,I.StyleVar_Alpha,1)", SCRIPT)
        self.assertIn("I.Col_ChildBg,0x000000FF", SCRIPT)
        self.assertIn("I.Col_Text,0xFFFFFFFF", SCRIPT)
        self.assertIn("(width-line.width)/2", SCRIPT)
        self.assertIn("not a and not sel.dragging and target", SCRIPT)
        self.assertIn("readerPasteRequested=true; sel.pending=nil", SCRIPT)
        self.assertIn("GetExtState(SECTION,'recovery_drafts')", SCRIPT)


if __name__ == "__main__":
    unittest.main(verbosity=2)
