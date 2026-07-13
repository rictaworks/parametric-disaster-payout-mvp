class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :google_sub, null: false

      t.timestamps
    end
    add_index :users, :google_sub, unique: true
  end
end
