"""Offline Lua checks. This does not launch or emulate the Maker runtime."""
import json
import sys
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / '.tmp/lua-check'))
from lupa import LuaRuntime
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute("package.path = 'scripts/?.lua;' .. package.path")
parse = lua.eval('function(s,n) local f,e=load(s,n); return f~=nil,e end')
files = list((ROOT / 'scripts').rglob('*.lua'))
for p in files:
    ok, err = parse(p.read_text(encoding='utf-8-sig'), str(p))
    assert ok, err
rules = lua.execute("return require('Bottle.Tests').Run()")
checks = lua.execute((Path(__file__).parent / 'checks.lua').read_text(encoding='utf-8'))
widget_checks = lua.execute((Path(__file__).parent / 'widget-checks.lua').read_text(encoding='utf-8'))
assets = list((ROOT / 'assets/image/machine-layered').glob('*.png'))
assert len(assets) == 51
result = dict(lua_syntax_files=len(files), game_rule_checks=rules,
              layered_checks=checks, widget_contract_checks=widget_checks, independent_pngs=len(assets),
              runtime_visual_verification='NOT_VERIFIED_BY_OFFLINE_CHECKS')
(Path(__file__).parent / 'checks.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
print(json.dumps(result, indent=2))
