#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
account=$(gh api user --jq .login)
test "$account" = kondows95 || { echo 'kondows95で認証してください。' >&2; exit 1; }
test "$(git branch --show-current)" = main || { echo 'mainブランチで実行してください。' >&2; exit 1; }
test "$(git remote get-url origin)" = https://github.com/kondows95/pantsize.git || { echo 'originを確認してください。' >&2; exit 1; }

python3 - <<'PY'
import subprocess
def run(*args):
    subprocess.run(args, check=True)
run('gh', 'api', '--method', 'PATCH', 'repos/kondows95/pantsize', '-F', 'has_issues=true', '--silent')
result = subprocess.run(['gh', 'api', 'repos/kondows95/pantsize/pages'], capture_output=True, text=True)
if result.returncode == 0:
    method = 'PUT'
elif 'HTTP 404' in result.stderr:
    method = 'POST'
else:
    raise SystemExit(result.stderr)
run('gh', 'api', '--method', method, 'repos/kondows95/pantsize/pages', '-f', 'build_type=workflow', '--silent')
PY

git add .github/workflows/pages.yml docs/site/index.html docs/site/privacy.html docs/site/README.md README.md scripts/deploy-pages.sh
if ! git diff --cached --quiet; then
  git -c user.name=kondows95 -c user.email=kondows95@users.noreply.github.com commit -m 'Publish support and privacy pages with GitHub Pages'
fi
git push origin main
echo 'GitHub Pagesの配信結果は以下のActions画面で確認してください。'
echo 'https://github.com/kondows95/pantsize/actions/workflows/pages.yml'
