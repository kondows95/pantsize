#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

account=$(gh api user --jq .login)
if [ "$account" != "kondows95" ]; then
  echo 'GitHubの有効なアカウントをkondows95に切り替えてください。' >&2
  exit 1
fi

if [ -e .git ]; then
  echo 'すでに.gitが存在します。既存の履歴とリモートを確認してから公開してください。' >&2
  exit 1
fi

git init -b main
git add .gitignore README.md Pantsize Pantsize.xcodeproj docs/AppStoreConnect-ja.md docs/site scripts

python3 - <<'PY'
import subprocess
paths = subprocess.check_output(['git', 'diff', '--cached', '--name-only', '-z']).decode().split('\0')
for path in filter(None, paths):
    parts = path.split('/')
    if any(part in ('DerivedData', 'xcuserdata', '.DS_Store', 'SS') for part in parts) or path.endswith('.xcuserstate'):
        raise SystemExit('公開対象に含めないファイルがあります: ' + path)
print('公開対象の除外設定を確認しました。')
PY

# 個人のメールアドレスをコミットに記録しない。
git -c user.name=kondows95 -c user.email=kondows95@users.noreply.github.com commit -m 'Initial import of Pantsize'
gh repo create kondows95/pantsize --public --description '写真の比率から服の寸法を推定するiPhone用画像定規アプリ' --source . --remote origin --push
gh repo view kondows95/pantsize --json url,visibility --jq '{url, visibility}'
