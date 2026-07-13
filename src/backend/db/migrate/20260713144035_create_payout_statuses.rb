class CreatePayoutStatuses < ActiveRecord::Migration[8.1]
  def change
    create_table :payout_statuses do |t|
      t.string :code, null: false
      t.text :labels

      t.timestamps
    end
    add_index :payout_statuses, :code, unique: true
  end
end
