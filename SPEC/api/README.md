# SPEC/api

Rails の API 仕様メモです。README の API 一覧からも参照します。

## POST /api/v1/session

- セッション作成
- 開発環境では Google ID トークンなしで `development-user` を作成できる
- BFF からは `X-Internal-API-Secret` を付与して Rails に中継する

## GET /api/v1/masters

- マスタ一覧
- 返却: `plans`, `stations`, `payout_tiers`

## GET /api/v1/policies

- 認証済みユーザーの契約一覧

## POST /api/v1/policies

- 契約作成
- `plan_id`, `station_id`, `payout_tier_id`, `threshold`, `recaptcha_token` を送る

## PATCH /api/v1/policies/:id/cancel

- 契約解約

## PATCH /api/v1/policies/:id/force_waiting_period_elapsed

- 免責期間を即時経過させるプロトタイプ操作

## GET /api/v1/payouts

- 認証済みユーザーの支払一覧

## GET /api/v1/notifications

- 認証済みユーザーの通知一覧

## POST /api/v1/survey_responses

- アンケート送信
- `payout_id` と `response_data` を送る
  - `response_data` 内の `satisfaction`（1〜5の整数）は**必須**です。
  - `response_data` 内の `feedback`（文字列）は**任意**です。

### リクエストJSON例

```json
{
  "payout_id": 1,
  "response_data": {
    "satisfaction": 5,
    "feedback": "非常に迅速な模擬支払いで満足しました。"
  }
}
```

### レスポンス

- **成功時 (`201 Created`)**

```json
{
  "survey_response": {
    "id": 1,
    "payout_id": 1,
    "response_data": {
      "satisfaction": 5,
      "feedback": "非常に迅速な模擬支払いで満足しました。"
    },
    "created_at": "2026-07-17T01:54:33Z"
  }
}
```

- **エラー時 (`422 Unprocessable Entity`)**
  - `payout_id` に対応する支払の状態が `completed_simulated` ではない場合、または `satisfaction` が正しくない場合に返ります。
  - `satisfaction` の検証エラー例（`response_data` の日本語属性ラベルが未定義のため、属性名部分は英語表記のまま返ります）:
    ```json
    {
      "error": [
        "Response data 満足度は必須入力です"
      ]
    }
    ```
