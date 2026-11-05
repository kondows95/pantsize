# Pantsize 公開用ページ

依存ライブラリやビルド処理のない静的HTMLです。

- `index.html`：サポートページ
- `privacy.html`：プライバシーポリシー
- `style.css`：共通スタイル

## 公開前の未完了事項

1. `index.html` の「お問い合わせ窓口は準備中」の段落を、指定されたメールアドレスの `mailto:` リンク、または問い合わせフォームへのリンクに置き換える。
2. 問い合わせ情報の保存・削除方針が実際の運用と一致することを確認する。
3. 選択したホスティングへHTMLとCSSを配置し、ログイン不要で両ページにアクセスできることを確認する。
4. 公開後のサポートURLとプライバシーポリシーURLをApp Store Connectへ設定する。
5. アプリ内に公開済みプライバシーポリシーへのリンクを追加する。

本ディレクトリは下書きです。問い合わせ先と公開URLは未設定で、アプリへのリンク追加・公開はまだ行っていません。

## GitHub Pages 公開先

予定リポジトリ：`kondows95/pantsize`（公開リポジトリ）。アプリ本体とこのディレクトリを同じリポジトリで管理します。

- サポート：`https://kondows95.github.io/pantsize/`
- プライバシーポリシー：`https://kondows95.github.io/pantsize/privacy.html`

公開時はGitHub Actionsで `docs/site/` の公開用HTMLとCSSのみを配信する構成とします。アプリのソースや他のドキュメントをPagesの配信対象に含めません。

### GitHub CLI の認証

手元のターミナルで以下を実行し、ブラウザでは `kondows95` でログインしてください。トークンを会話に貼り付ける必要はありません。

```sh
gh auth login --hostname github.com --git-protocol https --web
gh api user --jq .login
```

最後の出力が `kondows95` になったら、認証完了です。複数アカウントが登録されていて違うアカウントが有効な場合は、`gh auth switch --hostname github.com --user kondows95` で切り替えます。

問い合わせ先を反映してからPagesの配信を設定・有効化します。上記URLは予定であり、公開完了まではApp Store Connectへ登録しないでください。
