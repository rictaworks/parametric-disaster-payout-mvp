class CreatePolicies < ActiveRecord::Migration[8.1]
  def change
    create_table :policies do |t|
      t.references :user, null: false, foreign_key: true
      t.references :plan, null: false, foreign_key: true
      t.references :station, null: false, foreign_key: true
      t.references :payout_tier, null: false, foreign_key: true
      t.references :policy_status, null: false, foreign_key: true
      t.decimal :threshold
      t.datetime :waiting_until
      t.datetime :expires_at

      t.timestamps
    end
  end
end
