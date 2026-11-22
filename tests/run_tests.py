"""Run the Buff-o-Matic Lua test suite with an embedded Lua 5.1 (WoW's Lua version).

Requires:  pip install lupa
Usage:     python tests/run_tests.py
If you have a standalone Lua 5.1 interpreter, `lua tests/run.lua` works too.
"""
import os
import sys

try:
    import lupa.lua51 as lupa_lua
except ImportError:
    sys.exit("lupa is not installed: pip install lupa")

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__))).replace("\\", "/")
lua = lupa_lua.LuaRuntime(unpack_returned_tuples=True)
assert lua.eval("_VERSION") == "Lua 5.1", lua.eval("_VERSION")
lua.globals().ROOT = root
failed = False
for name in ("run.lua", "smoke.lua"):
    # fresh runtime per file: the smoke test installs global WoW API mocks
    lua = lupa_lua.LuaRuntime(unpack_returned_tuples=True)
    lua.globals().ROOT = root
    with open(os.path.join(root, "tests", name), encoding="utf-8") as f:
        src = f.read()
    try:
        lua.execute(src)
    except lupa_lua.LuaError as e:
        print(e)
        failed = True
sys.exit(1 if failed else 0)
