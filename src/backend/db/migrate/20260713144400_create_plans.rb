class CreatePlans < ActiveRecord::Migration[7.1]
  def change
    create_table :plans do |t|
      t.string :plan_type, null: false
      t.string :name, null: false
      t.text :description

      t.timestamps
    end
  end
end
