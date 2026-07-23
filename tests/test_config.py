from pathlib import Path

import morningbrief.config as config_module


def test_missing_user_config_does_not_rewrite_repo_example(tmp_path: Path) -> None:
    repo = tmp_path / "repo"
    example = repo / "configs" / "config.example.toml"
    example.parent.mkdir(parents=True)
    example.write_text("tracked sentinel\n", encoding="utf-8")
    user_config = tmp_path / "user" / "config.toml"

    original_repo_root = config_module.REPO_ROOT
    original_ensure_app_dirs = config_module.ensure_app_dirs
    config_module.REPO_ROOT = repo
    config_module.ensure_app_dirs = lambda: None
    try:
        loaded = config_module.load_config(user_config)
    finally:
        config_module.REPO_ROOT = original_repo_root
        config_module.ensure_app_dirs = original_ensure_app_dirs

    assert loaded.timezone == "Asia/Shanghai"
    assert user_config.exists()
    assert example.read_text(encoding="utf-8") == "tracked sentinel\n"
