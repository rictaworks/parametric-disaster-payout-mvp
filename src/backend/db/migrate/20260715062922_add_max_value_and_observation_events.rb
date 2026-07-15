class AddMaxValueAndObservationEvents < ActiveRecord::Migration[7.2]
  def change
    add_column :observations, :max_value, :decimal, precision: 6, scale: 2

    create_table :observation_events do |t|
      t.references :observation, null: false, foreign_key: true
      t.datetime :occurred_at, null: false
      t.json :payload, null: false, default: {}

      t.timestamps
    end

    add_index :observation_events, [ :observation_id, :occurred_at ]
  end
end
