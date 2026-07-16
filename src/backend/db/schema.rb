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

ActiveRecord::Schema[7.2].define(version: 2026_07_16_145154) do
  create_table "legacy_payouts", force: :cascade do |t|
    t.integer "policy_id"
    t.integer "payout_tier_id"
    t.integer "payout_status_id"
    t.integer "observation_id"
    t.string "idempotency_key"
    t.datetime "decided_at"
    t.string "isolation_reason", null: false
    t.datetime "legacy_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "legacy_survey_responses", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "policy_id"
    t.json "response_data", default: {}, null: false
    t.datetime "legacy_created_at"
    t.string "isolation_reason"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

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

  create_table "observation_events", force: :cascade do |t|
    t.integer "observation_id", null: false
    t.datetime "occurred_at", null: false
    t.json "payload", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["observation_id", "occurred_at"], name: "index_observation_events_on_observation_id_and_occurred_at"
    t.index ["observation_id"], name: "index_observation_events_on_observation_id"
  end

  create_table "observations", force: :cascade do |t|
    t.integer "station_id", null: false
    t.integer "seismic_intensity_level_id"
    t.decimal "rainfall_mm", precision: 6, scale: 2
    t.datetime "observed_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "event_id"
    t.boolean "simulated", default: false, null: false
    t.decimal "max_value", precision: 6, scale: 2
    t.index ["seismic_intensity_level_id"], name: "index_observations_on_seismic_intensity_level_id"
    t.index ["station_id", "event_id"], name: "idx_obs_station_event", unique: true, where: "event_id IS NOT NULL"
    t.index ["station_id", "observed_at"], name: "idx_obs_station_observed", unique: true, where: "event_id IS NULL"
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
    t.integer "observation_id", null: false
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
    t.integer "station_id"
    t.datetime "waiting_until"
    t.datetime "terminated_at"
    t.index ["payout_tier_id"], name: "index_policies_on_payout_tier_id"
    t.index ["plan_id"], name: "index_policies_on_plan_id"
    t.index ["policy_status_id"], name: "index_policies_on_policy_status_id"
    t.index ["station_id"], name: "index_policies_on_station_id"
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

  create_table "processed_jma_entries", force: :cascade do |t|
    t.string "entry_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["entry_id"], name: "index_processed_jma_entries_on_entry_id", unique: true
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

  create_table "solid_queue_blocked_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.string "concurrency_key", null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.index ["concurrency_key", "priority", "job_id"], name: "index_solid_queue_blocked_executions_for_release"
    t.index ["expires_at", "concurrency_key"], name: "index_solid_queue_blocked_executions_for_maintenance"
    t.index ["job_id"], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id", "job_id"], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "solid_queue_failed_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.text "error"
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "solid_queue_jobs", force: :cascade do |t|
    t.string "queue_name", null: false
    t.string "class_name", null: false
    t.text "arguments"
    t.integer "priority", default: 0, null: false
    t.string "active_job_id"
    t.datetime "scheduled_at"
    t.datetime "finished_at"
    t.string "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active_job_id"], name: "index_solid_queue_jobs_on_active_job_id"
    t.index ["class_name"], name: "index_solid_queue_jobs_on_class_name"
    t.index ["finished_at"], name: "index_solid_queue_jobs_on_finished_at"
    t.index ["queue_name", "finished_at"], name: "index_solid_queue_jobs_for_filtering"
    t.index ["scheduled_at", "finished_at"], name: "index_solid_queue_jobs_for_alerting"
  end

  create_table "solid_queue_pauses", force: :cascade do |t|
    t.string "queue_name", null: false
    t.datetime "created_at", null: false
    t.index ["queue_name"], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end

  create_table "solid_queue_processes", force: :cascade do |t|
    t.string "kind", null: false
    t.datetime "last_heartbeat_at", null: false
    t.bigint "supervisor_id"
    t.integer "pid", null: false
    t.string "hostname"
    t.text "metadata"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.index ["last_heartbeat_at"], name: "index_solid_queue_processes_on_last_heartbeat_at"
    t.index ["name", "supervisor_id"], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
    t.index ["supervisor_id"], name: "index_solid_queue_processes_on_supervisor_id"
  end

  create_table "solid_queue_ready_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index ["priority", "job_id"], name: "index_solid_queue_poll_all"
    t.index ["queue_name", "priority", "job_id"], name: "index_solid_queue_poll_by_queue"
  end

  create_table "solid_queue_recurring_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "task_key", null: false
    t.datetime "run_at", null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    t.index ["task_key", "run_at"], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
  end

  create_table "solid_queue_recurring_tasks", force: :cascade do |t|
    t.string "key", null: false
    t.string "schedule", null: false
    t.string "command", limit: 2048
    t.string "class_name"
    t.text "arguments"
    t.string "queue_name"
    t.integer "priority", default: 0
    t.boolean "static", default: true, null: false
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    t.index ["static"], name: "index_solid_queue_recurring_tasks_on_static"
  end

  create_table "solid_queue_scheduled_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.datetime "scheduled_at", null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index ["scheduled_at", "priority", "job_id"], name: "index_solid_queue_dispatch_all"
  end

  create_table "solid_queue_semaphores", force: :cascade do |t|
    t.string "key", null: false
    t.integer "value", default: 1, null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at"], name: "index_solid_queue_semaphores_on_expires_at"
    t.index ["key", "value"], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index ["key"], name: "index_solid_queue_semaphores_on_key", unique: true
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
    t.string "jma_code"
    t.index ["code"], name: "index_stations_on_code", unique: true
    t.index ["jma_code"], name: "index_stations_on_jma_code", unique: true
  end

  create_table "survey_responses", force: :cascade do |t|
    t.integer "user_id", null: false
    t.json "response_data", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "payout_id", null: false
    t.index ["payout_id"], name: "idx_survey_responses_payout", unique: true
    t.index ["payout_id"], name: "index_survey_responses_on_payout_id"
    t.index ["user_id"], name: "index_survey_responses_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "google_sub", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["google_sub"], name: "index_users_on_google_sub", unique: true
  end

  add_foreign_key "legacy_survey_responses", "users", on_delete: :cascade
  add_foreign_key "notifications", "payouts"
  add_foreign_key "notifications", "policies"
  add_foreign_key "notifications", "users"
  add_foreign_key "observation_events", "observations"
  add_foreign_key "observations", "seismic_intensity_levels"
  add_foreign_key "observations", "stations"
  add_foreign_key "payouts", "observations"
  add_foreign_key "payouts", "payout_statuses"
  add_foreign_key "payouts", "payout_tiers"
  add_foreign_key "payouts", "policies"
  add_foreign_key "policies", "payout_tiers"
  add_foreign_key "policies", "plans"
  add_foreign_key "policies", "policy_statuses"
  add_foreign_key "policies", "stations"
  add_foreign_key "policies", "users"
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "survey_responses", "payouts"
  add_foreign_key "survey_responses", "users"
end
