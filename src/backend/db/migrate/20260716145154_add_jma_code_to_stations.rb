class AddJmaCodeToStations < ActiveRecord::Migration[7.2]
  def up
    add_column :stations, :jma_code, :string
    add_index :stations, :jma_code, unique: true

    # Temporarily define the model in the migration namespace to ensure it is isolated.
    station_model = Class.new(ActiveRecord::Base) do
      self.table_name = 'stations'
    end

    station_model.find_by(code: "seismic_tokyo")&.update!(jma_code: "1310130")
    station_model.find_by(code: "seismic_osaka")&.update!(jma_code: "2712830")
    station_model.find_by(code: "rainfall_tokyo")&.update!(jma_code: "44132")
  end

  def down
    remove_index :stations, :jma_code
    remove_column :stations, :jma_code
  end
end
