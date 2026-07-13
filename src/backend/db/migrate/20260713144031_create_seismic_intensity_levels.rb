class CreateSeismicIntensityLevels < ActiveRecord::Migration[8.1]
  def change
    create_table :seismic_intensity_levels do |t|
      t.string :code, null: false
      t.decimal :numeric_value, null: false
      t.text :labels

      t.timestamps
    end
    add_index :seismic_intensity_levels, :code, unique: true
  end
end
