# ER図（実装リバースエンジニアリング）

`src/backend/db/schema.rb`（`version: 2026_07_17_130000`）から起こしたER図です。設計初期段階の [`../parametric-disaster-payout-mvp_design_document.md`](../parametric-disaster-payout-mvp_design_document.md) のER図とは、主キー構成・正規化マスタの分離・追加テーブルの点で異なります。実装の正とするのはこちらです。

```mermaid
erDiagram
    USERS ||--o{ POLICIES : "契約する"
    USERS ||--o{ NOTIFICATIONS : "受け取る"
    USERS ||--o{ SURVEY_RESPONSES : "回答する"
    PLANS ||--o{ POLICIES : "適用される"
    PAYOUT_TIERS ||--o{ POLICIES : "適用される"
    POLICY_STATUSES ||--o{ POLICIES : "状態"
    STATIONS ||--o{ POLICIES : "対象地点"
    STATIONS ||--o{ OBSERVATIONS : "観測する"
    SEISMIC_INTENSITY_LEVELS ||--o{ OBSERVATIONS : "震度階級"
    POLICIES ||--o{ PAYOUTS : "支払われる"
    OBSERVATIONS ||--o{ PAYOUTS : "根拠となる"
    OBSERVATIONS ||--o{ OBSERVATION_EVENTS : "続報履歴"
    PAYOUT_TIERS ||--o{ PAYOUTS : "支払額区分"
    PAYOUT_STATUSES ||--o{ PAYOUTS : "状態"
    PAYOUTS ||--o| SURVEY_RESPONSES : "紐づく"
    PAYOUTS ||--o{ NOTIFICATIONS : "紐づく"
    POLICIES ||--o{ NOTIFICATIONS : "紐づく"

    USERS {
        int id PK
        string google_sub UK "opaqueなsub値・メール不保持"
    }
    PLANS {
        int id PK
        string code UK
        string trigger_type "seismic / rainfall"
    }
    PAYOUT_TIERS {
        int id PK
        string code UK
        int amount_yen
    }
    POLICY_STATUSES {
        int id PK
        string code UK "pending/active/processing/cap_reached/cancelled/expired"
        int sort_order
    }
    PAYOUT_STATUSES {
        int id PK
        string code UK "ordered/completed_simulated/invalid"
        int sort_order
    }
    SEISMIC_INTENSITY_LEVELS {
        int id PK
        string code UK
        int sort_order
    }
    STATIONS {
        int id PK
        string code UK "気象庁観測点コード"
        string jma_code UK
        string measurement_type "seismic / rainfall"
    }
    POLICIES {
        int id PK
        int user_id FK
        int plan_id FK
        int station_id FK
        int payout_tier_id FK
        int policy_status_id FK
        string threshold
        datetime waiting_until "免責明け時刻"
        datetime expires_at
        datetime terminated_at "解約・失効時刻"
    }
    OBSERVATIONS {
        int id PK
        int station_id FK
        int seismic_intensity_level_id FK "震度観測点のみ"
        decimal rainfall_mm "雨量観測点のみ"
        decimal max_value "最大観測値（続報で更新）"
        string event_id "気象庁イベントID"
        datetime observed_at
        boolean simulated "模擬フラグ"
        boolean admin_injected "管理画面からの注入フラグ"
    }
    OBSERVATION_EVENTS {
        int id PK
        int observation_id FK
        datetime occurred_at
        json payload "続報の生データ履歴"
    }
    PAYOUTS {
        int id PK
        int policy_id FK
        int observation_id FK
        int payout_tier_id FK
        int payout_status_id FK
        string idempotency_key UK "policy_id×event 相当で一意"
        datetime decided_at "指図時刻（即日性KPI）"
    }
    NOTIFICATIONS {
        int id PK
        int user_id FK
        int policy_id FK
        int payout_id FK
        string kind
        text message
        datetime delivered_at
        datetime read_at
    }
    SURVEY_RESPONSES {
        int id PK
        int user_id FK
        int payout_id FK "UK・1支払につき1件"
        json response_data "satisfaction必須・feedback任意"
    }
```

## design_document.md のER図との主な相違点

| 項目 | design_document.md（初期設計） | 実装（schema.rb） |
| --- | --- | --- |
| USERS PK | `google_sub` を直接PK | `id`（integer, 連番）。`google_sub` はUK |
| POLICIES/NOTIFICATIONS/SURVEY_RESPONSES の所有者FK | `google_sub FK` | `user_id`（integer FK） |
| STATIONS PK | `station_id`（気象庁コードを直接PK） | `id`。`code`/`jma_code` はUK |
| 契約状態・支払状態・震度階級 | `POLICIES.status` 等の文字列カラム | `policy_statuses` / `payout_statuses` / `seismic_intensity_levels` に正規化 |
| `PAYOUTS.ordered_at` | あり | 実装では `decided_at` |
| 続報履歴 | 設計上は概念のみ | `observation_events` テーブルとして実体化 |
| ジョブキュー基盤 | 記載なし | `solid_queue_*`（Solid Queue、Rails標準のバックグラウンドジョブ基盤。ドメインモデル外のため本図では省略） |
| 隔離データ | 記載なし | `legacy_payouts` / `legacy_survey_responses`（過去の不整合データを隔離した退避テーブル。現行フローでは参照しない） |

DFD・シーケンス図・クラス図・状態遷移図・ユースケース図は概念レベルで実装と大きな乖離がないため、当面は [`../parametric-disaster-payout-mvp_design_document.md`](../parametric-disaster-payout-mvp_design_document.md) を正とする。ただしテーブル・カラムに言及する場合は本図（ER図）を優先すること。
