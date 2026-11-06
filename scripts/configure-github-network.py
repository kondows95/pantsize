#!/usr/bin/env python3
"""Enable GitHub-only command networking in the user's Codex CLI configuration.

Run from your own terminal. Domain rules cannot restrict access to a GitHub owner.
This does not change GitHub credentials, permissions, or managed policies.
"""

from datetime import datetime, timezone
from pathlib import Path
import os
import shutil
import tomllib


def main():
    codex_home = Path(os.environ.get('CODEX_HOME') or Path.home() / '.codex')
    config = codex_home / 'config.toml'
    original = config.read_text() if config.exists() else ''
    current = tomllib.loads(original)

    # Avoid overwriting a subsequently configured permission profile or policy.
    conflicts = [key for key in ('default_permissions', 'permissions', 'sandbox_mode',
                                'sandbox_workspace_write') if key in current]
    if 'network_proxy' in current.get('features', {}):
        conflicts.append('features.network_proxy')
    if conflicts:
        raise SystemExit('既存設定と競合するため変更しません: ' + ', '.join(conflicts))

    updated = '''# Command networking: GitHub HTTPS only (not restricted to a GitHub owner).
sandbox_mode = "workspace-write"

''' + original.rstrip() + '''

[sandbox_workspace_write]
network_access = true

[features.network_proxy]
enabled = true

[features.network_proxy.domains]
"github.com" = "allow"
"api.github.com" = "allow"
'''
    parsed = tomllib.loads(updated)
    assert parsed['features']['network_proxy']['domains'] == {
        'github.com': 'allow', 'api.github.com': 'allow'
    }
    for key, value in current.items():
        if key != 'features':
            assert parsed[key] == value, key
        else:
            for feature, setting in value.items():
                assert parsed['features'][feature] == setting, feature

    codex_home.mkdir(parents=True, exist_ok=True)
    if config.exists():
        stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
        backup = config.with_name(f'config.toml.backup-{stamp}')
        shutil.copy2(config, backup)
        backup.chmod(0o600)
        print('バックアップ:', backup)
    config.write_text(updated)
    config.chmod(0o600)
    print('変更しました:', config)
    print('Codex CLIを再起動してください。管理ポリシーによる制限は解除されません。')
    print('GitHubの所有者制限は行いません。別途、限定した認証情報が必要です。')


if __name__ == '__main__':
    main()
