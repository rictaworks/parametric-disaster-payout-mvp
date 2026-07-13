class CreateStage1DomainModels < ActiveRecord::Migration[7.2]
  def change
    create_table :users do |t|
      t.string :google_sub, null: false

      t.timestamps
    end
    add_index :users, :google_sub, unique: true

    create_table :plans do |t|
      t.string :code, null: false
      t.string :trigger_type, null: false
      multilingual_label_columns(t)

      t.timestamps
    end
    add_index :plans, :code, unique: true

    create_table :seismic_intensity_levels do |t|
      t.string :code, null: false
      t.integer :sort_order, null: false
      multilingual_label_columns(t)

      t.timestamps
    end
    add_index :seismic_intensity_levels, :code, unique: true
    add_index :seismic_intensity_levels, :sort_order, unique: true

    create_table :stations do |t|
      t.string :code, null: false
      t.string :measurement_type, null: false
      multilingual_label_columns(t)

      t.timestamps
    end
    add_index :stations, :code, unique: true

    create_table :payout_tiers do |t|
      t.string :code, null: false
      t.integer :amount_yen, null: false
      multilingual_label_columns(t)

      t.timestamps
    end
    add_index :payout_tiers, :code, unique: true

    create_table :policy_statuses do |t|
      t.string :code, null: false
      t.integer :sort_order, null: false
      multilingual_label_columns(t)

      t.timestamps
    end
    add_index :policy_statuses, :code, unique: true
    add_index :policy_statuses, :sort_order, unique: true

    create_table :payout_statuses do |t|
      t.string :code, null: false
      t.integer :sort_order, null: false
      multilingual_label_columns(t)

      t.timestamps
    end
    add_index :payout_statuses, :code, unique: true
    add_index :payout_statuses, :sort_order, unique: true

    create_table :policies do |t|
      t.references :user, null: false, foreign_key: true
      t.references :plan, null: false, foreign_key: true
      t.references :payout_tier, null: false, foreign_key: true
      t.references :policy_status, null: false, foreign_key: true
      t.string :threshold, null: false
      t.datetime :expires_at, null: false

      t.timestamps
    end

    create_table :observations do |t|
      t.references :policy, null: false, foreign_key: true
      t.references :station, null: false, foreign_key: true
      t.references :seismic_intensity_level, null: true, foreign_key: true
      t.decimal :rainfall_mm, precision: 6, scale: 2
      t.datetime :observed_at, null: false

      t.timestamps
    end

    create_table :payouts do |t|
      t.references :policy, null: false, foreign_key: true
      t.references :payout_tier, null: false, foreign_key: true
      t.references :payout_status, null: false, foreign_key: true
      t.references :observation, null: true, foreign_key: true
      t.string :idempotency_key, null: false
      t.datetime :decided_at

      t.timestamps
    end
    add_index :payouts, :idempotency_key, unique: true

    create_table :notifications do |t|
      t.references :user, null: false, foreign_key: true
      t.references :policy, null: true, foreign_key: true
      t.references :payout, null: true, foreign_key: true
      t.string :kind, null: false
      t.text :message, null: false
      t.datetime :delivered_at
      t.datetime :read_at

      t.timestamps
    end

    create_table :survey_responses do |t|
      t.references :user, null: false, foreign_key: true
      t.references :policy, null: true, foreign_key: true
      t.json :response_data, null: false, default: {}

      t.timestamps
    end
  end

  private

  def multilingual_label_columns(table)
    table.string :label_ja, null: false
    table.string :label_en, null: false
    table.string :label_fr, null: false
    table.string :label_zh, null: false
    table.string :label_ru, null: false
    table.string :label_es, null: false
    table.string :label_ar, null: false
  end
end
