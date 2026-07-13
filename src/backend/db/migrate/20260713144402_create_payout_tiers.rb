class CreatePayoutTiers < ActiveRecord::Migration[7.1]
  def change
    create_table :payout_tiers do |t|
      t.references :plan, null: false, foreign_key: true
      t.decimal :threshold, null: false, precision: 8, scale: 2
      t.decimal :amount, null: false, precision: 10, scale: 2
      t.string :tier_label, null: false

      t.timestamps
    end
  end
end
