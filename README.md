# parametric-disaster-payout-mvp

> **本サービスは保険の引受・実支払を行わない需要調査用の模擬デモです。実際の金銭のお支払いは発生しません。**

震度・降雨量という客観的パラメータのみで即日模擬支払判定を行うパラメトリック災害保険 MVP。

## リポジトリ構成

```
/src
  /frontend/    # Next.js (TypeScript, App Router)  — port 3000
  /backend/     # Rails API                         — port 3001
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

## 自動ログイン手順

（後続 Issue で記載）

## ページ一覧

（後続 Issue で記載）

## API 一覧

（後続 Issue で記載）
