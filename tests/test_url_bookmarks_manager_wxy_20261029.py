"""Mocked REAPER regressions. Requires Python + lupa.lua53; opens no real URLs.
Run from repository root: python tests/test_url_bookmarks_manager_wxy_20261029.py
"""
from pathlib import Path
import unittest
from lupa.lua53 import LuaRuntime

SOURCE = Path(__file__).resolve().parents[1] / "Utility" / "URL_Bookmarks_Manager.lua"
SCRIPT = SOURCE.read_text(encoding="utf-8")
PAIR = "A|||https://a.example\nB|||https://b.example\n"


def run(data=PAIR, selection=0, response="", sws=True, fail=False):
    lua = LuaRuntime(unpack_returned_tuples=True)
    g = lua.globals()
    g.data, g.selection, g.response, g.has_sws, g.fail = data, selection, response, sws, fail
    lua.execute(r'''
        opened, messages, saved, menu, quit = {}, {}, nil, nil, false
        os.execute = function() error("shell execution forbidden") end
        io.popen = function() error("shell execution forbidden") end
        reaper = {
            GetExtState = function(section, key)
                assert(section == "URL_Bookmarks_Menu" and key == "Data")
                return data
            end,
            SetExtState = function(section, key, value, persist)
                assert(section == "URL_Bookmarks_Menu" and key == "Data" and persist)
                saved = value
            end,
            MB = function(message, title, kind)
                messages[#messages + 1] = message
                return kind == 4 and 6 or 0
            end,
            GetUserInputs = function() return true, response end,
            GetMousePosition = function() return 100, 200 end,
            defer = function(fn) fn() end,
        }
        if has_sws then
            reaper.CF_ShellExecute = function(url)
                if fail then error("native handler failed") end
                opened[#opened + 1] = url
                return true
            end
        end
        gfx = {
            init = function() end,
            screentoclient = function(x,y) return x,y end,
            showmenu = function(value) menu = value; return selection end,
            quit = function() quit = true end,
        }
    ''')
    lua.execute(SCRIPT)
    assert g.quit
    return g


class URLBookmarksRegression(unittest.TestCase):
    def test_menu_structure(self):
        for count in (0, 1, 2, 4):
            data = "".join(f"Name{i}|||https://n{i}.example\n" for i in range(count))
            g = run(data)
            depth = headings = leaves = 0
            for entry in g.menu.split("|"):
                if not entry:
                    continue
                if entry.startswith(">"):
                    self.assertEqual(depth, 0)
                    depth += 1
                    headings += 1
                else:
                    leaves += 1
                    if entry.startswith("<"):
                        self.assertEqual(depth, 1)
                        depth -= 1
            self.assertEqual(depth, 0)
            self.assertEqual(headings, 5 if count else 0)
            self.assertEqual(leaves, count * 6 + 1 if count else 2)

    def test_all_command_mappings(self):
        expected = {
            3: "A|||https://a.example\nB|||https://b.example\nN|||https://n.example,a,b\n",
            4: "N|||https://a.example\nB|||https://b.example\n",
            5: "A|||https://a.example\nN|||https://b.example\n",
            6: "A|||https://n.example\nB|||https://b.example\n",
            7: "A|||https://a.example\nB|||https://n.example\n",
            8: "B|||https://b.example\n",
            9: "A|||https://a.example\n",
            10: None,
            11: "B|||https://b.example\nA|||https://a.example\n",
            12: "B|||https://b.example\nA|||https://a.example\n",
            13: None,
        }
        for selection in range(1, 14):
            response = "N,https://n.example,a,b" if selection == 3 else "https://n.example" if selection in (6, 7) else "N"
            with self.subTest(selection=selection):
                g = run(selection=selection, response=response)
                if selection in (1, 2):
                    self.assertEqual(g.opened[1], f"https://{'a' if selection == 1 else 'b'}.example")
                else:
                    self.assertEqual(g.saved, expected[selection])

    def test_empty_and_cancelled_menu(self):
        self.assertIsNone(run(selection=0).saved)
        self.assertIsNone(run("", 1).saved)
        self.assertEqual(run("", 2, "N,example.com").saved, "N|||example.com\n")

    def test_supported_urls_are_passed_as_data(self):
        for raw, expected in [
            ("example.com", "https://example.com"),
            ("example.com:8080/path", "https://example.com:8080/path"),
            ("HTTPS://Example.com/Case", "https://Example.com/Case"),
            ("file:///C:/Music/song.wav", "file:///C:/Music/song.wav"),
            (" https://x.example/a%20b ", "https://x.example/a%20b"),
            ("https://x.example/?x=1&y=%PATH%", "https://x.example/?x=1&y=%PATH%"),
            ("https://x.example/?x=||value|||other", "https://x.example/?x=||value|||other"),
        ]:
            with self.subTest(raw=raw):
                self.assertEqual(run("N|||" + raw + "\n", 1).opened[1], expected)

    def test_blocked_launches(self):
        for raw in ('https://x/" & calc & "', 'javascript:alert(1)', 'mailto:x@y', 'https://', 'file://', 'https://x/a b', 'https://x/\tbad', ''):
            with self.subTest(raw=raw):
                g = run("N|||" + raw + "\n", 1)
                self.assertEqual(len(g.opened), 0)
                self.assertEqual(len(g.messages), 1)
        self.assertEqual(len(run(selection=1, sws=False).messages), 1)
        self.assertEqual(len(run(selection=1, fail=True).messages), 1)

    def test_display_cannot_inject_menu_syntax(self):
        g = run("<>#!|evil|||https://x.example\n", 0)
        self.assertEqual(g.menu.count(">"), 5)
        self.assertEqual(g.menu.count("<"), 5)
        self.assertNotIn("!", g.menu)
        self.assertIn("evil", g.menu)

    def test_storage_validation_and_literal_names(self):
        for response in ("bad|||name", "bad\nname"):
            g = run(selection=4, response=response)
            self.assertIsNone(g.saved)
            self.assertEqual(len(g.messages), 1)
        self.assertIsNone(run(selection=6, response="https://x/\nforged|||x").saved)
        self.assertEqual(run(selection=4, response="#<name>!").saved, "#<name>!|||https://a.example\nB|||https://b.example\n")


if __name__ == "__main__":
    unittest.main(verbosity=2)
