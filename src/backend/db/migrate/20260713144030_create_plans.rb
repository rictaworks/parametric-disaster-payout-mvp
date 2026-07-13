class CreatePlans < ActiveRecord::Migration[8.1]
  def change
    create_table :plans do |t|
      t.string :code, null: false
      t.string :plan_type, null: false
      t.text :labels

      t.timestamps
    end
    add_index :plans, :code, unique: true
  end
end
