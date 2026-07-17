# parametric-disaster-payout-mvp

> **本サービスは保険の引受・実支払を行わない需要調査用の模擬デモです。実際の金銭のお支払いは発生しません。**

震度・降雨量という客観的パラメータのみで即日模擬支払判定を行うパラメトリック災害保険 MVP です。

## リポジトリ構成

```
/src
  /frontend/    # Next.js (TypeScript, App Router)  — port 3000
  /backend/     # Rails API                         — port 3001
/SPEC/api/      # API 仕様メモ
/e2e/           # Playwright (後続 Issue で実装)
/.github/workflows/
```

## セットアップ

### フロントエンド

```bash
cd src/frontend
npm install
npm run dev        # http://localhost:3000
```

### バックエンド

```bash
cd src/backend
bundle install
bin/rails db:create db:migrate
bin/rails server   # http://localhost:3001
# ヘルスチェック: curl http://localhost:3001/up
```

### 環境変数

フロントエンドとバックエンドのそれぞれで環境変数を設定する必要があります。

#### フロントエンド

```bash
cd src/frontend
cp .env.example .env
# .env を編集して各値を設定する
```

#### バックエンド

```bash
cd src/backend
cp .env.example .env
# .env を編集して各値を設定する
```

> [!NOTE]
> 本番環境（または暗号化された credentials を復号・編集する環境）では、`RAILS_MASTER_KEY` を環境変数として必ず指定してください。

## 自動ログイン手順

### 1. 通常の Google ログイン

1. `src/frontend` と `src/backend` を起動します。
2. `http://localhost:3000/login` を開き、Google ID トークンを貼り付けて送信します。
3. 成功すると `parametric_session_token` Cookie が設定され、`/mypage` で契約情報を確認できます。

### 2. development 環境の認証済み分岐

Rails が `development` 環境のときは、`POST /api/v1/session` が Google ID トークンなしでも `development-user` を作成します。

Next.js の BFF 経由で自動ログインする場合は、以下のように空の JSON を送ります。

```bash
curl -i -X POST http://localhost:3000/api/v1/session \
  -H "Content-Type: application/json" \
  -H "Origin: http://localhost:3000" \
  -H "Host: localhost:3000" \
  -d '{}'
```

レスポンスの `Set-Cookie` で `parametric_session_token` が返るので、そのまま `/mypage` を開けます。

## ページ一覧

| ページ名 | URL | 用途 |
| --- | --- | --- |
| ホーム | `http://localhost:3000/` | 模擬デモの概要とログイン導線 |
| ログイン | `http://localhost:3000/login` | Google ID トークンでセッション作成 |
| 申込ウィザード | `http://localhost:3000/policies/new` | 模擬契約の申込 |
| マイページ | `http://localhost:3000/mypage` | 契約・支払・通知の確認 |

## API 一覧

ブラウザからは Next.js の BFF (`http://localhost:3000/api/v1/...`) を経由して Rails API を呼び出します。

| タイトル | エンドポイント | 仕様メモ |
| --- | --- | --- |
| セッション作成 | `POST /api/v1/session` | [`SPEC/api/README.md#post-apiv1session`](SPEC/api/README.md#post-apiv1session) |
| マスタ一覧 | `GET /api/v1/masters` | [`SPEC/api/README.md#get-apiv1masters`](SPEC/api/README.md#get-apiv1masters) |
| 契約一覧 | `GET /api/v1/policies` | [`SPEC/api/README.md#get-apiv1policies`](SPEC/api/README.md#get-apiv1policies) |
| 契約作成 | `POST /api/v1/policies` | [`SPEC/api/README.md#post-apiv1policies`](SPEC/api/README.md#post-apiv1policies) |
| 契約解約 | `PATCH /api/v1/policies/:id/cancel` | [`SPEC/api/README.md#patch-apiv1policiesidcancel`](SPEC/api/README.md#patch-apiv1policiesidcancel) |
| 免責期間即時経過 | `PATCH /api/v1/policies/:id/force_waiting_period_elapsed` | [`SPEC/api/README.md#patch-apiv1policiesidforce_waiting_period_elapsed`](SPEC/api/README.md#patch-apiv1policiesidforce_waiting_period_elapsed) |
| 支払一覧 | `GET /api/v1/payouts` | [`SPEC/api/README.md#get-apiv1payouts`](SPEC/api/README.md#get-apiv1payouts) |
| 通知一覧 | `GET /api/v1/notifications` | [`SPEC/api/README.md#get-apiv1notifications`](SPEC/api/README.md#get-apiv1notifications) |
| アンケート送信 | `POST /api/v1/survey_responses` | [`SPEC/api/README.md#post-apiv1survey_responses`](SPEC/api/README.md#post-apiv1survey_responses) |
