class CreatePolicyStatuses < ActiveRecord::Migration[8.1]
  def change
    create_table :policy_statuses do |t|
      t.string :code, null: false
      t.text :labels

      t.timestamps
    end
    add_index :policy_statuses, :code, unique: true
  end
end
