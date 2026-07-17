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
