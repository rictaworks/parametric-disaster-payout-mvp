class CreateObservations < ActiveRecord::Migration[7.1]
  def change
    create_table :observations do |t|
      t.references :station, null: false, foreign_key: true
      t.datetime :observed_at, null: false
      t.decimal :value, null: false, precision: 8, scale: 2
      t.string :event_id, null: false

      t.timestamps
    end
    add_index :observations, :event_id
  end
end
