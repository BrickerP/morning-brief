#!/usr/bin/env python3
import importlib.util
import inspect
import sys
import tempfile
import traceback
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "packages" / "morningbrief"))

failed = 0
passed = 0
for path in sorted((ROOT / "tests").glob("test_*.py")):
    spec = importlib.util.spec_from_file_location(path.stem, path)
    mod = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(mod)
    for attr in dir(mod):
        if not attr.startswith("test_") or not callable(getattr(mod, attr)):
            continue
        fn = getattr(mod, attr)
        sig = inspect.signature(fn)
        kw: dict = {}
        td = None
        if sig.parameters:

            class MP:
                def setattr(self, obj, name, value):
                    setattr(obj, name, value)

            if "tmp_path" in sig.parameters:
                td = tempfile.TemporaryDirectory()
                kw["tmp_path"] = Path(td.name)
            if "monkeypatch" in sig.parameters:
                kw["monkeypatch"] = MP()
        try:
            fn(**kw)
            print("PASS", path.stem, attr)
            passed += 1
        except Exception:
            print("FAIL", path.stem, attr)
            traceback.print_exc()
            failed += 1
        finally:
            if td:
                td.cleanup()

print(f"{passed} passed, {failed} failed")
raise SystemExit(1 if failed else 0)
