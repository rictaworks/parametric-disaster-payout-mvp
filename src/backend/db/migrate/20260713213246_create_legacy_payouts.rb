class CreateLegacyPayouts < ActiveRecord::Migration[7.2]
  def change
    # 移行できない・一意に決定できない支払を削除せず退避しておくための隔離アーカイブテーブル。
    # 参照先（policy/payout_tier/payout_status/observation）が既に存在しない場合もあるため、
    # 外部キー制約は付けずプレーンな整数として保持する。
    create_table :legacy_payouts do |t|
      t.integer :policy_id
      t.integer :payout_tier_id
      t.integer :payout_status_id
      t.integer :observation_id
      t.string :idempotency_key
      t.datetime :decided_at
      t.string :isolation_reason, null: false
      t.datetime :legacy_created_at

      t.timestamps
    end
  end
end
