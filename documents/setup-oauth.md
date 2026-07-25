# Google OAuth クライアントのセットアップ

mailer が Gmail API を呼ぶための OAuth クライアントを用意する手順。GCP コンソールでの作業は自動化できないため手動で行う。

## 1. GCP プロジェクト作成と Gmail API 有効化

1. https://console.cloud.google.com/ でプロジェクトを作成する
2. 「API とサービス > ライブラリ」で **Gmail API** を有効化する

## 2. OAuth 同意画面

1. 「API とサービス > OAuth 同意画面」で User Type: **外部** を選択する
2. スコープに以下を追加する
   - `https://www.googleapis.com/auth/gmail.modify`
   - `https://www.googleapis.com/auth/gmail.settings.basic`
3. **公開ステータスを「本番」にする**（「テスト中」のままだと restricted scope を含むためリフレッシュトークンが7日で失効する）
   - 未検証アプリのままで良い。100 ユーザー上限は個人利用では問題ない
   - 同意時に「このアプリは Google で確認されていません」と出るが、「詳細 > （安全ではないページ）に移動」で進める

## 3. OAuth クライアント作成

「API とサービス > 認証情報 > 認証情報を作成 > OAuth クライアント ID」で以下を作成する。

| 用途 | アプリケーションの種類 | 備考 |
| --- | --- | --- |
| CLI / macOS | デスクトップアプリ | loopback リダイレクト（http://127.0.0.1:ポート）を使う |
| iOS | iOS | Bundle ID を指定。カスタム URL スキームでリダイレクト |

## 4. mailer への設定

CLI / macOS 用クライアントの ID とシークレットを `~/.config/mailer/oauth.json` に置く:

```json
{
  "clientID": "xxxx.apps.googleusercontent.com",
  "clientSecret": "GOCSPX-xxxx"
}
```

環境変数でも指定できる（設定ファイルより優先）:

```sh
export MAILER_GOOGLE_CLIENT_ID="xxxx.apps.googleusercontent.com"
export MAILER_GOOGLE_CLIENT_SECRET="GOCSPX-xxxx"
```

設定ディレクトリは `MAILER_CONFIG_DIR` で変更できる（既定: `~/.config/mailer`）。

## 参照

- https://developers.google.com/identity/protocols/oauth2
- https://support.google.com/cloud/answer/7454865
