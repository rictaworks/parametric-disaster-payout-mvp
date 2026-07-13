class CreatePayoutTiers < ActiveRecord::Migration[8.1]
  def change
    create_table :payout_tiers do |t|
      t.string :code, null: false
      t.integer :amount_yen, null: false
      t.text :labels

      t.timestamps
    end
    add_index :payout_tiers, :code, unique: true
  end
end
