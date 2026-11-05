# Pantsize 公開用ページ

- サポート： https://kondows95.github.io/pantsize/
- プライバシーポリシー： https://kondows95.github.io/pantsize/privacy.html

`.github/workflows/pages.yml` が、mainのページ更新時にHTML・CSS・`.nojekyll`のみをGitHub Pagesへ配信します。アプリ本体や他のドキュメントは配信対象に含めません。

## 初回公開

リポジトリのルートで `bash scripts/deploy-pages.sh` を実行します。kondows95でのGitHub CLI認証が必要です。スクリプトはIssuesを有効化し、PagesをGitHub Actions方式に設定し、変更をコミット・pushします。

Actionsの「Deploy GitHub Pages」が成功してから上記URLにアクセスできることを確認してください。URL確認後、App Store Connectへ登録し、アプリ内にもポリシーのリンクを追加します。

問い合わせ先は公開GitHub Issuesです。投稿にGitHubアカウントが必要であり、投稿内容が公開されることを両ページで説明しています。
