# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.2].define(version: 2026_07_13_174806) do
  create_table "notifications", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "policy_id"
    t.integer "payout_id"
    t.string "kind", null: false
    t.text "message", null: false
    t.datetime "delivered_at"
    t.datetime "read_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["payout_id"], name: "index_notifications_on_payout_id"
    t.index ["policy_id"], name: "index_notifications_on_policy_id"
    t.index ["user_id"], name: "index_notifications_on_user_id"
  end

  create_table "observations", force: :cascade do |t|
    t.integer "policy_id", null: false
    t.integer "station_id", null: false
    t.integer "seismic_intensity_level_id"
    t.decimal "rainfall_mm", precision: 6, scale: 2
    t.datetime "observed_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["policy_id"], name: "index_observations_on_policy_id"
    t.index ["seismic_intensity_level_id"], name: "index_observations_on_seismic_intensity_level_id"
    t.index ["station_id"], name: "index_observations_on_station_id"
  end

  create_table "payout_statuses", force: :cascade do |t|
    t.string "code", null: false
    t.integer "sort_order", null: false
    t.string "label_ja", null: false
    t.string "label_en", null: false
    t.string "label_fr", null: false
    t.string "label_zh", null: false
    t.string "label_ru", null: false
    t.string "label_es", null: false
    t.string "label_ar", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_payout_statuses_on_code", unique: true
    t.index ["sort_order"], name: "index_payout_statuses_on_sort_order", unique: true
  end

  create_table "payout_tiers", force: :cascade do |t|
    t.string "code", null: false
    t.integer "amount_yen", null: false
    t.string "label_ja", null: false
    t.string "label_en", null: false
    t.string "label_fr", null: false
    t.string "label_zh", null: false
    t.string "label_ru", null: false
    t.string "label_es", null: false
    t.string "label_ar", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_payout_tiers_on_code", unique: true
  end

  create_table "payouts", force: :cascade do |t|
    t.integer "policy_id", null: false
    t.integer "payout_tier_id", null: false
    t.integer "payout_status_id", null: false
    t.integer "observation_id"
    t.string "idempotency_key", null: false
    t.datetime "decided_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["idempotency_key"], name: "index_payouts_on_idempotency_key", unique: true
    t.index ["observation_id"], name: "index_payouts_on_observation_id"
    t.index ["payout_status_id"], name: "index_payouts_on_payout_status_id"
    t.index ["payout_tier_id"], name: "index_payouts_on_payout_tier_id"
    t.index ["policy_id"], name: "index_payouts_on_policy_id"
  end

  create_table "plans", force: :cascade do |t|
    t.string "code", null: false
    t.string "trigger_type", null: false
    t.string "label_ja", null: false
    t.string "label_en", null: false
    t.string "label_fr", null: false
    t.string "label_zh", null: false
    t.string "label_ru", null: false
    t.string "label_es", null: false
    t.string "label_ar", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_plans_on_code", unique: true
  end

  create_table "policies", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "plan_id", null: false
    t.integer "payout_tier_id", null: false
    t.integer "policy_status_id", null: false
    t.string "threshold", null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["payout_tier_id"], name: "index_policies_on_payout_tier_id"
    t.index ["plan_id"], name: "index_policies_on_plan_id"
    t.index ["policy_status_id"], name: "index_policies_on_policy_status_id"
    t.index ["user_id"], name: "index_policies_on_user_id"
  end

  create_table "policy_statuses", force: :cascade do |t|
    t.string "code", null: false
    t.integer "sort_order", null: false
    t.string "label_ja", null: false
    t.string "label_en", null: false
    t.string "label_fr", null: false
    t.string "label_zh", null: false
    t.string "label_ru", null: false
    t.string "label_es", null: false
    t.string "label_ar", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_policy_statuses_on_code", unique: true
    t.index ["sort_order"], name: "index_policy_statuses_on_sort_order", unique: true
  end

  create_table "seismic_intensity_levels", force: :cascade do |t|
    t.string "code", null: false
    t.integer "sort_order", null: false
    t.string "label_ja", null: false
    t.string "label_en", null: false
    t.string "label_fr", null: false
    t.string "label_zh", null: false
    t.string "label_ru", null: false
    t.string "label_es", null: false
    t.string "label_ar", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_seismic_intensity_levels_on_code", unique: true
    t.index ["sort_order"], name: "index_seismic_intensity_levels_on_sort_order", unique: true
  end

  create_table "stations", force: :cascade do |t|
    t.string "code", null: false
    t.string "measurement_type", null: false
    t.string "label_ja", null: false
    t.string "label_en", null: false
    t.string "label_fr", null: false
    t.string "label_zh", null: false
    t.string "label_ru", null: false
    t.string "label_es", null: false
    t.string "label_ar", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_stations_on_code", unique: true
  end

  create_table "survey_responses", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "policy_id"
    t.json "response_data", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["policy_id"], name: "index_survey_responses_on_policy_id"
    t.index ["user_id"], name: "index_survey_responses_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "google_sub", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["google_sub"], name: "index_users_on_google_sub", unique: true
  end

  add_foreign_key "notifications", "payouts"
  add_foreign_key "notifications", "policies"
  add_foreign_key "notifications", "users"
  add_foreign_key "observations", "policies"
  add_foreign_key "observations", "seismic_intensity_levels"
  add_foreign_key "observations", "stations"
  add_foreign_key "payouts", "observations"
  add_foreign_key "payouts", "payout_statuses"
  add_foreign_key "payouts", "payout_tiers"
  add_foreign_key "payouts", "policies"
  add_foreign_key "policies", "payout_tiers"
  add_foreign_key "policies", "plans"
  add_foreign_key "policies", "policy_statuses"
  add_foreign_key "policies", "users"
  add_foreign_key "survey_responses", "policies"
  add_foreign_key "survey_responses", "users"
end
