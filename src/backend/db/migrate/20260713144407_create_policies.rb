class CreatePolicies < ActiveRecord::Migration[7.1]
  def change
    create_table :policies do |t|
      t.references :user, null: false, foreign_key: true
      t.references :plan, null: false, foreign_key: true
      t.references :station, null: false, foreign_key: true
      t.references :payout_tier, null: false, foreign_key: true
      t.string :status, null: false, default: "active"
      t.datetime :waiting_until
      t.date :start_date, null: false
      t.date :end_date, null: false
      t.integer :annual_payout_count, null: false, default: 0

      t.timestamps
    end
  end
end
