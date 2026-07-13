class CreatePayouts < ActiveRecord::Migration[7.1]
  def change
    create_table :payouts do |t|
      t.references :policy, null: false, foreign_key: true
      t.references :observation, null: true, foreign_key: true
      t.decimal :amount, null: false, precision: 10, scale: 2
      t.string :status, null: false, default: "pending"
      t.string :idempotency_key, null: false

      t.timestamps
    end
    add_index :payouts, :idempotency_key, unique: true
  end
end
