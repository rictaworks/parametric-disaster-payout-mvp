class CreateStations < ActiveRecord::Migration[7.1]
  def change
    create_table :stations do |t|
      t.string :code, null: false
      t.string :name, null: false
      t.string :prefecture, null: false

      t.timestamps
    end
    add_index :stations, :code, unique: true
  end
end
