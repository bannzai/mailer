# 問い合わせメールの Jev 分類

受信した問い合わせメールを TypeSafe の判定モデル Jev で分類し、結果をメールに紐付けて保存して、通知枠 (フィルタルール) の条件に使う仕組みの記録。issue: https://github.com/bannzai/mailer/issues/28

## 呼び出す位置

CLI / macOS アプリが `MailerCore` から API (`POST https://api.typesafe.ai/v1/systemone`、モデル `jev-1.13.0` 固定) を直接呼ぶ。中継サーバーは置かない (mailer は bannzai 個人のツールで、サーバーを持たない構成のため)。

API キーは次の順で読む (`InquiryClassifierConfiguration.load`)。どちらも無い環境では分類を利用不可として、受信処理は分類なしで続く。

1. 環境変数 `TYPESAFE_API_KEY` (公式 SDK・castle のスクリプトと同じ名前)
2. `~/.config/mailer/typesafe.json` (`MAILER_CONFIG_DIR` で変更可)

```json
{
  "apiKey": "ts-xxxx"
}
```

iOS アプリには配布しない。iOS のサンドボックスには `typesafe.json` も質問定義も無いため、分類は利用不可のまま既存の通知経路だけが動く。

## 質問定義 (castle 側が SSOT)

種別 (Choice) + flag (Noul) + 深刻度 (Score) の質問定義は castle の jev-check skill が持つ `review-triage.json` で、mailer はそれを読み込んで castle の `classify-review.sh` と同じリクエストを組み立てる (同じ本文で `classify-review.sh --dry-run` の出力と一致することをテスト `requestBodyEqualsCastleDryRunOutput` で確認している)。

- 既定のパス: `~/.agents/skills/jev-check/assets/rules/review-triage.json` (Codex と共有する skill の検索パス)
- 環境変数 `MAILER_JEV_RULES_PATH` で別のファイルを指定できる
- ファイルが無ければ分類は利用不可 (castle 未インストールの環境・CI・iOS)

castle 側の定義: https://github.com/bannzai/castle/blob/main/home/.agents/skills/jev-check/assets/rules/review-triage.json

## 送信する本文の範囲

1 通 = 1 リクエストで、`InquiryClassificationPipeline.inputText` が組み立てる次のテキストを `state.review` に置く。

```text
件名: <Subject ヘッダ>

<本文>
```

- 本文は `text/plain` パートを優先し、無ければ `text/html` のタグを落としたもの、どちらも無ければ Gmail の snippet。添付パート (filename 付き・`Content-Disposition: attachment`) とその配下は本文の探索から除く
- 件名を含めた全体を先頭 2,000 文字に切り詰める (`InquiryClassificationPipeline.maxInputCharacters`)。問い合わせの本文は通常数百文字で、それより長いのは引用の返信連鎖や署名のため、先頭だけで判定できる。Jev の state + 質問の上限 32k トークンより十分小さく、1 件の入力を 3,000 トークン前後 ($0.00013 未満) に抑える
- 送ってよいのは mailer に届く問い合わせメールの本文 (2026-09-20 のユーザー判断)。`mailer classify` は `--query` (必須。例: `to:support@example.com`) で問い合わせの宛先・件名に絞ったメールだけを対象にし、受信トレイ全体には当てない (`--query` 無しでは起動時のエラーで止まる)
- ヘッダ (From・To 等) と添付は送らない

## 保存する判定結果

`~/.config/mailer/classifications.json` にアカウント別・メール ID 別に保存する (`InquiryClassificationStore`。形は `{"<account email>": {"<message id>": {...}}}`)。1 件の項目:

| 項目 | 内容 |
| --- | --- |
| `category` | 種別 (bug / feature_request / billing / howto_question / complaint / praise / off_topic) |
| `categoryConfidence` | 種別の確信度 (0〜1) |
| `severity` | 深刻度の段階名 (none / low / medium / high。score を丸めた添字の段階) |
| `severityScore` | 深刻度のスコア (0〜3 の実数) |
| `severityConfidence` | 深刻度の確信度 (0〜1) |
| `flags` | flag 名 (unusable_now / churn_signal / refund_request / contains_personal_data / abusive) ごとの確率 (0〜1) |
| `model` | 判定したモデル ID |
| `classifiedAt` | 判定した時刻 (ISO 8601) |

本文・件名・差出人は保存しない (Gmail 側が正で、設定ディレクトリに個人情報を複製しないため)。保存済みのメールは API を呼ばず保存値を使う (再実行しても課金と判定のぶれが増えない)。

## 閾値 (採用 / 不確実 / 却下の 3 帯)

確率 (種別・深刻度の確信度、flag の確率) を `InquiryClassificationBand` で 3 帯に分ける。

| 帯 | 範囲 | 通知枠の条件での扱い |
| --- | --- | --- |
| 採用 | 0.7 以上 | 条件に合致する |
| 不確実 | 0.3 より大きく 0.7 未満 | 合致しない (既存の通知経路に流す) |
| 却下 | 0.3 以下 | 合致しない |

0.7 / 0.3 は castle の判定鎖ランナー jev-decide と同じ値 (TypeSafe 公式の confidence 3 段階に合わせたもの。castle の ADR 0072)。castle の `review-triage.json` にある `threshold: 0.5` は castle のスクリプトが flag を「該当」と表示する境界で、mailer の 3 帯には使わない。

## 通知枠の条件への組み込み

`NotificationRuleCondition.classification` (`InquiryClassificationCondition`) に、合致させる種別 (`categories`)・flag (`flags`)・深刻度 (`severities`) を列挙する。列挙したもののいずれかが採用帯で当たれば合致する (OR)。差出人・件名などの他のフィールドとは AND。issue の例「深刻度 high または unusable_now / refund_request が閾値以上のメールは即時通知、それ以外は 12 時間に 1 回のまとめ通知」は次の 2 枠で表す (先頭の枠が先勝ち)。

```sh
mailer notification-rules add 緊急 --severity high --flag unusable_now --flag refund_request --immediate
mailer notification-rules add 問い合わせまとめ --domain example.com --batch-hours 12
```

`NotificationEngine.decide(messages:rules:states:now:classifications:)` にメール ID -> 判定結果を渡す。判定が無いメール (API 不達・タイムアウト・キー未設定・未判定) と不確実帯の判定は、分類条件を持つ枠に合致せず、残りの枠と `defaultPolicy` (即時) で扱う。不達を「問題なし」にはせず、判定なしのまま既存の経路に流す。

## API 不達・タイムアウト時の挙動

`InquiryClassificationPipeline.classify` は投げない。

- HTTP 429 / 529 は 2 秒・4 秒で最大 2 回再試行し、タイムアウト (20 秒) は 1 回だけ再送する (castle の jev-request.sh と同じ方針。値の根拠は `InquiryClassifier` のコメント)
- それでも失敗したメールは「判定なし」として結果に含めず、保存もしない (次回の実行で再判定する)
- 1 度失敗したら、その実行の残りのメールは API を呼ばず判定なしにする (不達時にメール件数分のタイムアウトを待たないため)
- 判定なしのメール ID と理由は `InquiryClassificationRun.unavailableMessageIds` / `unavailableReason` で呼び出し側に返す

## 受信処理での位置づけ

mailer には常駐の受信ループがまだ無い (通知の配信は issue #10)。現時点の受信処理は受信トレイの取得で、`mailer classify` がそれに分類を足したもの。`InquiryClassificationPipeline` は metadata 形式のメール集合を受け取り、未判定のものだけ `format=full` で本文を取り直して判定・保存する。#10 のポーリングはこの pipeline を呼んでから `NotificationEngine.decide` に判定結果を渡す。

## 精度

castle での実測 (自作 12 本で 73/73 セル、公開レビュー 22 本で 121/123) は https://github.com/bannzai/castle/pull/1170 。問い合わせメールの実文面での精度は未測定で、`mailer classify --query <問い合わせの宛先>` を数通に当てて確認する。
