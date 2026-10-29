"""Compile all distributed scripts with Lua 5.3 and run mocked regression tests."""
from pathlib import Path
import runpy
from lupa.lua53 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
lua = LuaRuntime(unpack_returned_tuples=True)
compile_lua = lua.eval('function(s, name) local f,e=load(s,name,"t"); return f~=nil,e end')
scripts = [p for folder in ('Items', 'Tracks', 'MIDI', 'Utility') for p in (ROOT / folder).glob('*.lua')]
assert len(scripts) == 9, f'Expected nine publishable scripts, found {len(scripts)}'
for path in scripts:
    text = path.read_text(encoding='utf-8-sig')
    ok, error = compile_lua(text, '@' + path.name)
    assert ok, f'{path}: {error}'
    assert '-- @author futurewy' in text, f'Incorrect author: {path}'
    assert '-- @version ' in text and '-- @description ' in text
    print(f'Lua 5.3 syntax + metadata PASS: {path.name}')
for path in sorted((ROOT / 'tests').glob('test_*.py')):
    print(f'Running {path.name}', flush=True)
    try:
        runpy.run_path(str(path), run_name='__main__')
    except SystemExit as exc:
        if exc.code not in (None, 0):
            raise
print('All syntax and mocked regression tests passed. REAPER host testing still required.')
