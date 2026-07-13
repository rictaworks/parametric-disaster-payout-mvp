class CreateNotifications < ActiveRecord::Migration[8.1]
  def change
    create_table :notifications do |t|
      t.references :user, null: false, foreign_key: true
      t.references :policy, null: true, foreign_key: true
      t.references :payout, null: true, foreign_key: true
      t.text :message, null: false
      t.datetime :read_at

      t.timestamps
    end
  end
end
