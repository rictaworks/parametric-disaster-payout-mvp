class CreateStations < ActiveRecord::Migration[8.1]
  def change
    create_table :stations do |t|
      t.string :code, null: false
      t.string :station_type, null: false
      t.text :labels

      t.timestamps
    end
    add_index :stations, :code, unique: true
  end
end
