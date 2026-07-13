class CreatePayouts < ActiveRecord::Migration[8.1]
  def change
    create_table :payouts do |t|
      t.references :policy, null: false, foreign_key: true
      t.references :payout_status, null: false, foreign_key: true
      t.references :observation, null: false, foreign_key: true
      t.string :idempotency_key
      t.integer :amount_yen

      t.timestamps
    end
    add_index :payouts, :idempotency_key, unique: true
  end
end
