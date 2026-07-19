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

#### ブラウザのコンソールから自動ログインする場合

ブラウザで `http://localhost:3000` を開いた後、開発者ツールのコンソールから以下の `fetch` を実行することで、自動ログイン用 Cookie を設定できます。

```javascript
fetch('/api/v1/session', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({})
}).then(res => console.log('Logged in successfully!'));
```

実行後、そのまま `http://localhost:3000/mypage` を開くとログインされた状態になります。

#### コマンドラインから `curl` で確認する場合

`-c` オプションで Cookie を保存し、後続リクエストに `-b` で引き渡します。

```bash
# Cookie をファイルに保存してセッション作成
curl -i -X POST http://localhost:3000/api/v1/session \
  -H "Content-Type: application/json" \
  -H "Origin: http://localhost:3000" \
  -c cookies.txt \
  -d '{}'

# 保存した Cookie を使用して契約一覧 API を呼び出す
curl -i http://localhost:3000/api/v1/policies \
  -b cookies.txt
```

## ページ一覧

### 利用者向け（Google ログイン）

| ページ名 | URL | 用途 |
| --- | --- | --- |
| ホーム | `http://localhost:3000/` | 模擬デモの概要とログイン導線 |
| ログイン | `http://localhost:3000/login` | Google ID トークンでセッション作成 |
| 申込ウィザード | `http://localhost:3000/policies/new` | 模擬契約の申込 |
| マイページ | `http://localhost:3000/mypage` | 契約・支払・通知の確認 |

### 管理画面（Rails・HTTP Basic 認証・日本語のみ）

Rails サーバー（既定では `http://localhost:3001`）に対して直接アクセスします。認証情報は環境変数 `ADMIN_BASIC_USER` / `ADMIN_BASIC_PASSWORD`（`src/backend/.env`）で設定します。

| ページ名 | URL | 用途 |
| --- | --- | --- |
| 契約一覧 | `http://localhost:3001/admin` | 全契約の確認 |
| KPI 閲覧 | `http://localhost:3001/admin/kpi` | 登録数・契約継続率等の KPI 集計表示 |
| 支払一覧 | `http://localhost:3001/admin/payouts` | 支払指図・完了操作 |
| 模擬イベント注入 | `http://localhost:3001/admin/simulated_events` | テスト用の震度・降雨観測イベントを手動投入 |
| 手動リセット | `http://localhost:3001/admin/reset` | 模擬デモデータの一括初期化（本番環境では無効） |

## API 一覧

ブラウザからは Next.js の BFF (`http://localhost:3000/api/v1/...`) を経由して Rails API を呼び出します。

| タイトル | エンドポイント | 仕様メモ |
| --- | --- | --- |
| セッション作成 | `POST /api/v1/session` | [`SPEC/api/README.md#post-apiv1session`](SPEC/api/README.md#post-apiv1session) |
| 選好言語の更新 | `PATCH /api/v1/locale` | [`SPEC/api/README.md#patch-apiv1locale`](SPEC/api/README.md#patch-apiv1locale) |
| マスタ一覧 | `GET /api/v1/masters` | [`SPEC/api/README.md#get-apiv1masters`](SPEC/api/README.md#get-apiv1masters) |
| 契約一覧 | `GET /api/v1/policies` | [`SPEC/api/README.md#get-apiv1policies`](SPEC/api/README.md#get-apiv1policies) |
| 契約作成 | `POST /api/v1/policies` | [`SPEC/api/README.md#post-apiv1policies`](SPEC/api/README.md#post-apiv1policies) |
| 契約解約 | `PATCH /api/v1/policies/:id/cancel` | [`SPEC/api/README.md#patch-apiv1policiesidcancel`](SPEC/api/README.md#patch-apiv1policiesidcancel) |
| 免責期間即時経過 | `PATCH /api/v1/policies/:id/force_waiting_period_elapsed` | [`SPEC/api/README.md#patch-apiv1policiesidforce_waiting_period_elapsed`](SPEC/api/README.md#patch-apiv1policiesidforce_waiting_period_elapsed) |
| 支払一覧 | `GET /api/v1/payouts` | [`SPEC/api/README.md#get-apiv1payouts`](SPEC/api/README.md#get-apiv1payouts) |
| 通知一覧 | `GET /api/v1/notifications` | [`SPEC/api/README.md#get-apiv1notifications`](SPEC/api/README.md#get-apiv1notifications) |
| アンケート送信 | `POST /api/v1/survey_responses` | [`SPEC/api/README.md#post-apiv1survey_responses`](SPEC/api/README.md#post-apiv1survey_responses) |

### 管理 API（Rails・HTTP Basic 認証）

| タイトル | エンドポイント | 仕様メモ |
| --- | --- | --- |
| 模擬イベント注入 | `POST /admin/simulated_events` | [`SPEC/api/README.md#post-adminsimulated_events`](SPEC/api/README.md#post-adminsimulated_events) |
| 手動リセット | `POST /admin/reset` | [`SPEC/api/README.md#post-adminreset`](SPEC/api/README.md#post-adminreset) |
| 支払完了（模擬） | `PATCH /admin/api/payouts/:id/complete` | [`SPEC/api/README.md#patch-adminapipayoutsidcomplete`](SPEC/api/README.md#patch-adminapipayoutsidcomplete) |
| 支払無効化 | `PATCH /admin/api/payouts/:id/invalidate` | [`SPEC/api/README.md#patch-adminapipayoutsidinvalidate`](SPEC/api/README.md#patch-adminapipayoutsidinvalidate) |
