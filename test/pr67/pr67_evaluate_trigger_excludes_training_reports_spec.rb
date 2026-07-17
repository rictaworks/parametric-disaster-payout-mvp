# PR #67「気象庁の訓練報・試験報がトリガー判定を通過し模擬支払を誤生成する不具合を修正」
#
# Issue #66 で検出された不具合: 気象庁の訓練報・試験報（気象庁XMLの
# `<Control><Status>` が「訓練」「試験」等）を取り込むと Observation#simulated が
# true になるが、支払指図を生成する EvaluateTrigger はこのフラグを一切参照して
# いなかったため、実際には災害が発生していないにもかかわらず、閾値条件さえ満たせば
# 通常の観測と同じように模擬支払指図・アプリ内通知が生成されてしまっていた
# （PR #53本文が明示的に約束していた安全策が未実装だった）。
#
# PR #67 は次の対応を行った:
#   - Observation に admin_injected（管理者が管理画面の模擬イベント注入から意図的に
#     作成したか）カラムを追加。simulated フラグは「気象庁の訓練報・試験報」と
#     「管理画面からの模擬イベント注入（F5, PR #56）」の両方で true になるが、
#     後者だけが admin_injected: true になる
#   - EvaluateTrigger に observation.simulated? && !observation.admin_injected? の
#     ガードを追加。気象庁由来のsimulated（訓練報・試験報）は判定から除外される一方、
#     管理画面からの模擬イベント注入は従来どおりデモ用の模擬支払を生成できる
#   - 既存データのバックフィル: デプロイ前に管理画面から作成済みの模擬観測が一律
#     admin_injected: false になって一覧・続報検索・未処理の再評価ジョブから
#     消えてしまわないよう、マイグレーションでバックフィルする
#
# PR #67本文のユーザーテスト手順は「bundle exec rspec spec ../../test で failures 0件」
# という間接確認に留まるため、本ファイルはこのPR固有の不具合修正そのもの
# （気象庁訓練報が支払をトリガーしないこと）を直接検証する。あわせて PR本文が
# 明記する「/admin/simulated_events にBASIC認証でログインし模擬イベントを注入する→
# 一覧に表示される→続報投入で支払指図・通知が生成される」という管理画面確認手順を
# request specとして再現し、バックフィル済み既存データが消えないことも確認する。
#
# 本ファイルの構成:
#   手順1: [このPRの中核] 気象庁由来の訓練報・試験報相当の観測
#          （simulated: true, admin_injected: false）は、閾値条件を満たしていても
#          支払指図・通知を生成しない
#   手順2: [回帰防止] 管理画面からの模擬イベント注入相当の観測
#          （simulated: true, admin_injected: true）は、従来どおり閾値条件を
#          満たせば支払指図・通知を生成する（F5の既存機能が壊れていないことの確認）
#   手順3: [回帰防止] 実観測（simulated: false, admin_injected: false）は
#          従来どおり支払指図・通知を生成する
#   手順4: 管理画面（/admin/simulated_events）での模擬イベント注入・一覧表示・
#          続報投入による支払指図生成の確認（BASIC認証込み、PR本文手順3の再現）。
#          あわせてバックフィル済み既存データ（admin_injected: true）が
#          一覧から消えないことを確認する
#
# 併せて QC10（エラーハンドリング：不正・想定外の入力でも例外にならず、想定された
# 挙動になること）と OWASP10（特に A04 Insecure Design：気象庁の訓練報・試験報という
# 「実災害ではない入力」を安全側で判定から除外できているか＝設計上の安全策の欠如の
# 修正そのもの、A07 Identification and Authentication Failures：管理画面のBASIC認証が
# 必須であること）の該当観点を確認する。
#
# [重要] 固定の絶対日時をハードコードせず、travel_to(Time.zone.now) で実行時刻を
# 凍結し、そこからの相対値でシナリオを組み立てる（test/pr49 と同じ方針）。
#
# 実行方法（開発/テストDBのみを対象。本番サーバーへは一切接続しない）:
#   cd src/backend
#   RAILS_ENV=test bin/rails db:test:prepare
#   bundle exec rspec ../../test/pr67/pr67_evaluate_trigger_excludes_training_reports_spec.rb

require "rails_helper"

RSpec.describe "PR67: 気象庁の訓練報・試験報はトリガー判定から除外され模擬支払を生成しない", type: :request do
  include ActiveSupport::Testing::TimeHelpers
  include ActiveJob::TestHelper

  around do |example|
    travel_to(Time.zone.now) { example.run }
  end

  before { ActiveJob::Base.queue_adapter = :test }

  after do
    clear_enqueued_jobs
    clear_performed_jobs
    ActiveJob::Base.queue_adapter = :test
  end

  let(:admin_user) { "admin" }
  let(:admin_password) { "changeme-pr67" }
  let(:auth_headers) do
    { "Authorization" => "Basic #{Base64.strict_encode64("#{admin_user}:#{admin_password}")}" }
  end

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("ADMIN_BASIC_USER").and_return(admin_user)
    allow(ENV).to receive(:[]).with("ADMIN_BASIC_PASSWORD").and_return(admin_password)
  end

  let(:user) { User.create!(google_sub: "google-sub-pr67-#{SecureRandom.hex(6)}") }

  let(:seismic_plan) do
    Plan.create!(
      code: "seismic_pr67_#{SecureRandom.hex(4)}",
      trigger_type: "seismic",
      label_ja: "震度連動", label_en: "Seismic-linked", label_fr: "Seismic-linked",
      label_zh: "Seismic-linked", label_ru: "Seismic-linked", label_es: "Seismic-linked", label_ar: "Seismic-linked"
    )
  end

  let(:seismic_station) do
    Station.create!(
      code: "seismic_tokyo_pr67_#{SecureRandom.hex(4)}",
      measurement_type: "seismic",
      label_ja: "東京震度観測点", label_en: "Tokyo", label_fr: "Tokyo", label_zh: "Tokyo",
      label_ru: "Tokyo", label_es: "Tokyo", label_ar: "Tokyo"
    )
  end

  let(:payout_tier) do
    PayoutTier.create!(
      code: "tier_pr67_#{SecureRandom.hex(4)}",
      amount_yen: 10_000,
      label_ja: "1万円相当（模擬）", label_en: "10000", label_fr: "10000", label_zh: "10000",
      label_ru: "10000", label_es: "10000", label_ar: "10000"
    )
  end

  # PolicyStatus/PayoutStatus は EvaluateTrigger/ExecutePayout が固定コード文字列で
  # find_by!(code: ...) するため、他のマスタとは異なりランダムサフィックスを付けない
  # （test/pr49 と同じ理由）
  let(:active_status)     { PolicyStatus.find_or_create_by!(code: "active", sort_order: 1, label_ja: "有効", label_en: "Active", label_fr: "Active", label_zh: "Active", label_ru: "Active", label_es: "Active", label_ar: "Active") }
  let(:processing_status) { PolicyStatus.find_or_create_by!(code: "processing", sort_order: 2, label_ja: "支払処理中", label_en: "Processing", label_fr: "Processing", label_zh: "Processing", label_ru: "Processing", label_es: "Processing", label_ar: "Processing") }
  let(:ordered_status)    { PayoutStatus.find_or_create_by!(code: "ordered", sort_order: 0, label_ja: "指図済", label_en: "Ordered", label_fr: "Ordered", label_zh: "Ordered", label_ru: "Ordered", label_es: "Ordered", label_ar: "Ordered") }

  let(:level_4)        { SeismicIntensityLevel.create!(code: "4_pr67_#{SecureRandom.hex(4)}", sort_order: 4, label_ja: "4", label_en: "4", label_fr: "4", label_zh: "4", label_ru: "4", label_es: "4", label_ar: "4") }
  let(:level_5_strong) { SeismicIntensityLevel.create!(code: "5s_pr67_#{SecureRandom.hex(4)}", sort_order: 6, label_ja: "5強", label_en: "5s", label_fr: "5s", label_zh: "5s", label_ru: "5s", label_es: "5s", label_ar: "5s") }

  before do
    active_status
    processing_status
    ordered_status
    level_4
    level_5_strong
  end

  def build_seismic_policy(threshold: "5強", waiting_until: Time.current - 1.day, expires_at: Time.current + 1.year)
    Policy.create!(
      user: user, plan: seismic_plan, station: seismic_station,
      payout_tier: payout_tier, policy_status: active_status, threshold: threshold
    ).tap do |policy|
      policy.update_columns(waiting_until: waiting_until, expires_at: expires_at)
    end
  end

  # ---------------------------------------------------------------------
  # 手順1: [このPRの中核] 気象庁由来の訓練報・試験報（simulated: true,
  # admin_injected: false）は、閾値条件を満たしていても支払指図・通知を生成しない
  # ---------------------------------------------------------------------
  describe "手順1: 気象庁の訓練報・試験報相当の観測はトリガー判定から除外される" do
    it "EvaluateTrigger.call は simulated: true かつ admin_injected: false の観測を ignored として即終了し、閾値到達でも支払・通知を生成しない" do
      policy = build_seismic_policy

      # 気象庁XMLの Status=訓練/試験 を受信した JmaPoller が生成する payload を模す
      # （station_code・event_id・seismic_intensity_level_label_ja・simulated のみで
      #  admin_injected キーを含まない = IngestObservationEvent#admin_injected? が
      #  デフォルトの false を返す。app/services/jma_poller.rb#seismic_observations 参照）
      training_observation = Observation.create!(
        station: seismic_station, event_id: "pr67-jma-training-report",
        observed_at: Time.current, seismic_intensity_level: level_5_strong,
        max_value: level_5_strong.sort_order, simulated: true, admin_injected: false
      )
      expect(training_observation.max_value).to be >= level_5_strong.sort_order # 閾値条件は満たしている

      result = EvaluateTrigger.call(training_observation)

      expect(result.status).to eq(:ignored)
      expect(result.payouts).to be_empty
      expect(Payout.count).to eq(0)
      expect(policy.reload.policy_status).to eq(active_status)
      expect(Notification.where(policy: policy, kind: Notification::KIND_PAYOUT_ORDERED)).not_to exist
    end

    it "IngestObservationEvent 経由（JmaPollerが実際に使う経路）で気象庁訓練報を取り込んでも、再評価ジョブの実行後に支払・通知が生成されない" do
      policy = build_seismic_policy

      # app/services/jma_poller.rb#seismic_observations が生成する payload を忠実に再現する。
      # このpayloadには admin_injected キーが存在しない点が管理画面注入との決定的な違い
      payload = {
        station_code: seismic_station.code,
        occurred_at: Time.current.iso8601,
        event_id: "pr67-jma-training-report-ingest",
        seismic_intensity_level_label_ja: level_5_strong.label_ja,
        simulated: true
      }

      result = IngestObservationEvent.new(payload: payload).call
      expect(result.status).to eq(:created)

      observation = result.observation
      expect(observation.simulated).to be(true)
      expect(observation.admin_injected).to be(false)

      ObservationReevaluationJob.perform_now(observation.id)

      expect(Payout.count).to eq(0)
      expect(policy.reload.policy_status).to eq(active_status)
      expect(Notification.where(policy: policy)).not_to exist
    end

    it "訓練報の続報（さらに震度が上方修正された続報）でも支払指図は生成されない" do
      policy = build_seismic_policy

      training_observation = Observation.create!(
        station: seismic_station, event_id: "pr67-jma-training-follow-up",
        observed_at: Time.current, seismic_intensity_level: level_4,
        max_value: level_4.sort_order, simulated: true, admin_injected: false
      )
      EvaluateTrigger.call(training_observation)
      expect(Payout.count).to eq(0)

      # 続報で震度が5強に上方修正された（IngestObservationEventの最大値更新を模す）
      training_observation.update_columns(seismic_intensity_level_id: level_5_strong.id, max_value: level_5_strong.sort_order)
      result = EvaluateTrigger.call(training_observation)

      expect(result.status).to eq(:ignored)
      expect(Payout.count).to eq(0)
      expect(policy.reload.policy_status).to eq(active_status)
    end

    it "訓練報を先に無視した後、同一契約・同一観測点への正当な実観測（simulated: false）は通常どおり支払指図を生成する（誤って契約自体をブロックしていないことの確認）" do
      policy = build_seismic_policy

      training_observation = Observation.create!(
        station: seismic_station, event_id: "pr67-training-before-real",
        observed_at: Time.current, seismic_intensity_level: level_5_strong,
        max_value: level_5_strong.sort_order, simulated: true, admin_injected: false
      )
      EvaluateTrigger.call(training_observation)
      expect(Payout.count).to eq(0)

      real_observation = Observation.create!(
        station: seismic_station, event_id: "pr67-real-after-training",
        observed_at: Time.current + 1.minute, seismic_intensity_level: level_5_strong,
        max_value: level_5_strong.sort_order, simulated: false
      )
      result = EvaluateTrigger.call(real_observation)

      expect(result.status).to eq(:success)
      expect(result.payouts.count).to eq(1)
      expect(Payout.count).to eq(1)
      expect(policy.reload.policy_status).to eq(processing_status)
    end
  end

  # ---------------------------------------------------------------------
  # 手順2: [回帰防止] 管理画面からの模擬イベント注入相当の観測
  # （simulated: true, admin_injected: true）は従来どおり支払指図・通知を生成する
  # ---------------------------------------------------------------------
  describe "手順2: 管理画面からの模擬イベント注入（F5）は従来どおり支払指図・通知を生成する（回帰防止）" do
    it "EvaluateTrigger.call は simulated: true かつ admin_injected: true の観測については閾値到達時に支払指図・通知を生成する" do
      policy = build_seismic_policy

      admin_observation = Observation.create!(
        station: seismic_station, event_id: "pr67-admin-injected",
        observed_at: Time.current, seismic_intensity_level: level_5_strong,
        max_value: level_5_strong.sort_order, simulated: true, admin_injected: true
      )

      result = EvaluateTrigger.call(admin_observation)

      expect(result.status).to eq(:success)
      expect(result.payouts.count).to eq(1)
      expect(Payout.count).to eq(1)
      expect(Payout.first.payout_status).to eq(ordered_status)
      expect(policy.reload.policy_status).to eq(processing_status)

      notification = Notification.find_by(policy: policy, kind: Notification::KIND_PAYOUT_ORDERED)
      expect(notification).to be_present
      expect(notification.message).to eq(I18n.t("notifications.payout_ordered"))
    end

    it "管理画面（/admin/simulated_events）から実際に注入した場合も、F2と同一経路を通り従来どおり支払指図が生成される（F5のend-to-end回帰確認）" do
      policy = build_seismic_policy

      post "/admin/simulated_events",
        headers: auth_headers,
        params: { station_id: seismic_station.id, event_mode: "new", seismic_intensity_level_id: level_5_strong.id }
      expect(response).to redirect_to(admin_simulated_events_path)

      observation = Observation.find_by!(station: seismic_station, simulated: true)
      expect(observation.admin_injected).to be(true)

      ObservationReevaluationJob.perform_now(observation.id)

      expect(Payout.count).to eq(1)
      expect(policy.reload.policy_status).to eq(processing_status)
      expect(Notification.where(policy: policy, kind: Notification::KIND_PAYOUT_ORDERED)).to exist
    end
  end

  # ---------------------------------------------------------------------
  # 手順3: [回帰防止] 実観測（simulated: false, admin_injected: false）は
  # 従来どおり支払指図・通知を生成する
  # ---------------------------------------------------------------------
  describe "手順3: 通常の実観測は従来どおり支払指図・通知を生成する（回帰防止）" do
    it "simulated: false の観測は閾値到達時に支払指図・通知を生成する" do
      policy = build_seismic_policy

      real_observation = Observation.create!(
        station: seismic_station, event_id: "pr67-real-observation",
        observed_at: Time.current, seismic_intensity_level: level_5_strong,
        max_value: level_5_strong.sort_order, simulated: false
      )

      result = EvaluateTrigger.call(real_observation)

      expect(result.status).to eq(:success)
      expect(result.payouts.count).to eq(1)
      expect(Payout.count).to eq(1)
      expect(policy.reload.policy_status).to eq(processing_status)
      expect(Notification.where(policy: policy, kind: Notification::KIND_PAYOUT_ORDERED)).to exist
    end
  end

  # ---------------------------------------------------------------------
  # 手順4: PR本文の管理画面確認手順（/admin/simulated_events にBASIC認証で
  # ログインし、模擬イベントを新規注入する→「既存イベント一覧」に表示される
  # （バックフィル済みデータが消えないことの確認を含む）→続報投入で支払指図・
  # 通知が生成される）をrequest specとして再現する
  # ---------------------------------------------------------------------
  describe "手順4: 管理画面での模擬イベント注入・一覧表示・続報投入（PR本文の手順3の再現）" do
    it "BASIC認証なしでは401となり管理画面にアクセスできない（OWASP A07）" do
      get "/admin/simulated_events"

      expect(response).to have_http_status(:unauthorized)
    end

    it "震度の模擬イベントを新規注入すると『既存イベント一覧』に表示され、続報投入で閾値到達すると支払指図・通知が生成される" do
      policy = build_seismic_policy

      post "/admin/simulated_events",
        headers: auth_headers,
        params: { station_id: seismic_station.id, event_mode: "new", seismic_intensity_level_id: level_4.id }
      expect(response).to redirect_to(admin_simulated_events_path)

      observation = Observation.find_by!(station: seismic_station, simulated: true)
      expect(observation.admin_injected).to be(true)
      ObservationReevaluationJob.perform_now(observation.id)
      expect(Payout.count).to eq(0) # 震度4は閾値5強未満

      # 「既存イベント一覧」に注入した震度4のイベントが表示される
      get "/admin/simulated_events", headers: auth_headers
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(observation.event_id)

      # 続報で震度5強に到達させる
      post "/admin/simulated_events",
        headers: auth_headers,
        params: {
          station_id: seismic_station.id, event_mode: "follow_up",
          observation_id: observation.id, seismic_intensity_level_id: level_5_strong.id
        }
      expect(response).to redirect_to(admin_simulated_events_path)
      ObservationReevaluationJob.perform_now(observation.id)

      expect(Payout.count).to eq(1)
      payout = Payout.last
      expect(payout.payout_status).to eq(ordered_status)
      expect(policy.reload.policy_status).to eq(processing_status)

      notification = Notification.find_by(policy: policy, kind: Notification::KIND_PAYOUT_ORDERED)
      expect(notification).to be_present
      expect(notification.message).to eq(I18n.t("notifications.payout_ordered"))
    end

    it "デプロイ前（マイグレーション前）から存在した管理画面注入済みの観測（バックフィルにより admin_injected: true）は、一覧から消えず引き続き続報投入の対象として選択できる" do
      # 「デプロイ前から存在した管理画面由来の模擬観測」を、マイグレーション
      # （db/migrate/20260717130000_add_admin_injected_to_observations.rb）によって
      # 正しく admin_injected: true にバックフィルされた後の状態として直接再現する
      # （バックフィルロジック自体は spec/db/migrate/..._spec.rb で個別に検証済み。
      #  ここではバックフィル後のデータが管理画面の機能から見て消えていないことを確認する）
      pre_existing_observation = Observation.create!(
        station: seismic_station, event_id: "pr67-pre-existing-backfilled",
        observed_at: Time.current - 1.day, seismic_intensity_level: level_4,
        max_value: level_4.sort_order, simulated: true, admin_injected: true
      )

      get "/admin/simulated_events", headers: auth_headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(pre_existing_observation.event_id)

      # 続報投入の対象（observation_id）としても引き続き選択できる
      policy = build_seismic_policy
      post "/admin/simulated_events",
        headers: auth_headers,
        params: {
          station_id: seismic_station.id, event_mode: "follow_up",
          observation_id: pre_existing_observation.id, seismic_intensity_level_id: level_5_strong.id
        }
      expect(response).to redirect_to(admin_simulated_events_path)

      ObservationReevaluationJob.perform_now(pre_existing_observation.id)

      expect(Payout.count).to eq(1)
      expect(policy.reload.policy_status).to eq(processing_status)
    end

    it "QC10 エラーハンドリング: 気象庁訓練報相当（admin_injected: false）の観測は続報投入の候補一覧・検索対象から除外される（管理画面はF5専用の模擬イベントのみを扱う）" do
      training_observation = Observation.create!(
        station: seismic_station, event_id: "pr67-training-not-in-admin-list",
        observed_at: Time.current, seismic_intensity_level: level_4,
        max_value: level_4.sort_order, simulated: true, admin_injected: false
      )

      get "/admin/simulated_events", headers: auth_headers

      expect(response.body).not_to include(training_observation.event_id)

      # 続報投入の対象として指定しても、observation_idが一覧対象外のため422で拒否される
      post "/admin/simulated_events",
        headers: auth_headers,
        params: {
          station_id: seismic_station.id, event_mode: "follow_up",
          observation_id: training_observation.id, seismic_intensity_level_id: level_5_strong.id
        }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(training_observation.reload.max_value).to eq(level_4.sort_order)
    end
  end
end
