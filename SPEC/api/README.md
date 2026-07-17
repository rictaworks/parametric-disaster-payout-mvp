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

## 管理 API

`/admin` 配下は HTTP Basic 認証（環境変数 `ADMIN_BASIC_USER` / `ADMIN_BASIC_PASSWORD`）で保護されており、日本語ロケール固定です（`src/backend/app/controllers/concerns/admin/authentication.rb`）。

## POST /admin/simulated_events

- 模擬イベント注入（`IngestObservationEvent` を経由し F2 の取込経路と同一処理）
- 管理画面 `http://localhost:3001/admin/simulated_events` のフォームから送信
- パラメータ
  - `station_id`（必須）: 観測点ID
  - `event_mode`: `new`（新規）または `follow_up`（続報）。`follow_up` の場合は `observation_id` が必須で、対象観測の `event_id`/`occurred_at` を引き継ぐ
  - 震度観測点の場合: `seismic_intensity_level_id`（必須）
  - 雨量観測点の場合: `rainfall_mm`（必須、0以上の数値）
- 生成される観測レコードには `simulated: true`, `admin_injected: true` が付与され、KPI集計上は実イベントと区別される
- 失敗時（観測点未存在・パラメータ不正・続報時の観測点不一致等）は `422 Unprocessable Entity` でフォームを再表示

## POST /admin/reset

- 模擬デモデータの手動一括リセット（`ResetDemoData` を実行）
- **本番環境（`Rails.env.production?`）では `404 Not Found` を返し実行不可**
- パラメータ
  - `confirmation_text`（必須）: `ResetDemoData::CONFIRMATION_TEXT` と完全一致しない場合は `422 Unprocessable Entity`

## PATCH /admin/api/payouts/:id/complete

- 支払指図（`ordered`）を「支払完了（模擬）」に遷移（`ExecutePayout` を実行）
- 成功時: `{ "payout": { "id", "payout_status_code", "policy_status_code" } }`
- パラメータ `return_to_admin_payouts` が付与されている場合は `303 See Other` で `/admin/payouts` へリダイレクト

## PATCH /admin/api/payouts/:id/invalidate

- 支払指図（`ordered`）を異常時操作として「無効」に遷移
- `ordered` 状態以外からの遷移は `422 Unprocessable Entity`（`{ "error": "..." }`）
- 既に `invalid` の場合は冪等に成功扱い
