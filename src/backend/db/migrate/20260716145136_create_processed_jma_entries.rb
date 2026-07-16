class CreateProcessedJmaEntries < ActiveRecord::Migration[7.2]
  def change
    create_table :processed_jma_entries do |t|
      t.string :entry_id

      t.timestamps
    end
    add_index :processed_jma_entries, :entry_id, unique: true
  end
end
