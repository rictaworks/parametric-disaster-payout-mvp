class CreateObservations < ActiveRecord::Migration[8.1]
  def change
    create_table :observations do |t|
      t.references :station, null: false, foreign_key: true
      t.datetime :observed_at
      t.decimal :value
      t.references :seismic_intensity_level, null: false, foreign_key: true

      t.timestamps
    end
  end
end
