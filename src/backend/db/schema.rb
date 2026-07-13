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

ActiveRecord::Schema[7.1].define(version: 2026_07_13_144418) do
  create_table "notifications", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "policy_id"
    t.integer "payout_id"
    t.string "notification_type", null: false
    t.text "body", null: false
    t.datetime "read_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["payout_id"], name: "index_notifications_on_payout_id"
    t.index ["policy_id"], name: "index_notifications_on_policy_id"
    t.index ["user_id"], name: "index_notifications_on_user_id"
  end

  create_table "observations", force: :cascade do |t|
    t.integer "station_id", null: false
    t.datetime "observed_at", null: false
    t.decimal "value", precision: 8, scale: 2, null: false
    t.string "event_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["event_id"], name: "index_observations_on_event_id"
    t.index ["station_id"], name: "index_observations_on_station_id"
  end

  create_table "payout_tiers", force: :cascade do |t|
    t.integer "plan_id", null: false
    t.decimal "threshold", precision: 8, scale: 2, null: false
    t.decimal "amount", precision: 10, scale: 2, null: false
    t.string "tier_label", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["plan_id"], name: "index_payout_tiers_on_plan_id"
  end

  create_table "payouts", force: :cascade do |t|
    t.integer "policy_id", null: false
    t.integer "observation_id"
    t.decimal "amount", precision: 10, scale: 2, null: false
    t.string "status", default: "pending", null: false
    t.string "idempotency_key", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["idempotency_key"], name: "index_payouts_on_idempotency_key", unique: true
    t.index ["observation_id"], name: "index_payouts_on_observation_id"
    t.index ["policy_id"], name: "index_payouts_on_policy_id"
  end

  create_table "plans", force: :cascade do |t|
    t.string "plan_type", null: false
    t.string "name", null: false
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "policies", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "plan_id", null: false
    t.integer "station_id", null: false
    t.integer "payout_tier_id", null: false
    t.string "status", default: "active", null: false
    t.datetime "waiting_until"
    t.date "start_date", null: false
    t.date "end_date", null: false
    t.integer "annual_payout_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["payout_tier_id"], name: "index_policies_on_payout_tier_id"
    t.index ["plan_id"], name: "index_policies_on_plan_id"
    t.index ["station_id"], name: "index_policies_on_station_id"
    t.index ["user_id"], name: "index_policies_on_user_id"
  end

  create_table "stations", force: :cascade do |t|
    t.string "code", null: false
    t.string "name", null: false
    t.string "prefecture", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_stations_on_code", unique: true
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
  add_foreign_key "observations", "stations"
  add_foreign_key "payout_tiers", "plans"
  add_foreign_key "payouts", "observations"
  add_foreign_key "payouts", "policies"
  add_foreign_key "policies", "payout_tiers"
  add_foreign_key "policies", "plans"
  add_foreign_key "policies", "stations"
  add_foreign_key "policies", "users"
end
