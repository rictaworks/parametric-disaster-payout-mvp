class CreateTables < ActiveRecord::Migration[7.1]
  def change
    create_table :users do |t|
      t.string :google_sub, null: false
      t.timestamps
    end
    add_index :users, :google_sub, unique: true

    create_table :plans do |t|
      t.string :code, null: false
      t.string :plan_type, null: false
      t.string :label_ja, null: false
      t.string :label_en, null: false
      t.string :label_fr
      t.string :label_zh
      t.string :label_ru
      t.string :label_es
      t.string :label_ar
      t.timestamps
    end
    add_index :plans, :code, unique: true

    create_table :stations do |t|
      t.string :code, null: false
      t.string :plan_type, null: false
      t.string :label_ja, null: false
      t.string :label_en, null: false
      t.string :label_fr
      t.string :label_zh
      t.string :label_ru
      t.string :label_es
      t.string :label_ar
      t.string :prefecture, null: false
      t.timestamps
    end
    add_index :stations, :code, unique: true

    create_table :payout_tiers do |t|
      t.string :code, null: false
      t.integer :amount_jpy, null: false
      t.string :label_ja, null: false
      t.string :label_en, null: false
      t.string :label_fr
      t.string :label_zh
      t.string :label_ru
      t.string :label_es
      t.string :label_ar
      t.timestamps
    end
    add_index :payout_tiers, :code, unique: true

    create_table :policy_statuses do |t|
      t.string :code, null: false
      t.string :label_ja, null: false
      t.string :label_en, null: false
      t.timestamps
    end
    add_index :policy_statuses, :code, unique: true

    create_table :seismic_intensity_levels do |t|
      t.string :code, null: false
      t.string :label_ja, null: false
      t.string :label_en, null: false
      t.timestamps
    end
    add_index :seismic_intensity_levels, :code, unique: true

    create_table :payout_statuses do |t|
      t.string :code, null: false
      t.string :label_ja, null: false
      t.string :label_en, null: false
      t.timestamps
    end
    add_index :payout_statuses, :code, unique: true

    create_table :policies do |t|
      t.references :user, null: false, foreign_key: true
      t.references :plan, null: false, foreign_key: true
      t.references :station, null: false, foreign_key: true
      t.references :payout_tier, null: false, foreign_key: true
      t.references :policy_status, null: false, foreign_key: true
      t.string :threshold, null: false
      t.string :age_group
      t.datetime :waiting_until, null: false
      t.datetime :expires_at, null: false
      t.timestamps
    end
  end
end
