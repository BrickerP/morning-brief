from morningbrief.models import rollup_status


def test_rollup_all_ok():
    assert rollup_status(["ok", "ok"]) == "ok"


def test_rollup_all_failed():
    assert rollup_status(["failed", "failed"]) == "failed"


def test_rollup_mixed_partial():
    assert rollup_status(["ok", "failed"]) == "partial"


def test_rollup_all_empty():
    assert rollup_status(["empty", "empty"]) == "empty"


def test_rollup_ok_and_empty():
    assert rollup_status(["ok", "empty"]) == "partial"
