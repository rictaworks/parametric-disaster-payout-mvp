# PR #56「Add admin simulated event injection tab for trigger-path demo testing」
#
# PR本文には非エンジニア向けの番号付き手順は明記されていないため、本文の記述
# （「観測点選択→震度/降雨入力→新規/続報切替→注入、の流れでIngestObservationEventに
# 投入し、F2と同じ判定経路・simulated=trueの付与・最大値更新挙動を再現できます」）と、
# 紐づく Issue #14「[Stage 13] 管理画面 模擬イベント注入タブ（F5 injectSimulatedEvent）」の
# 受入条件を「非エンジニア向けユーザーテスト手順」として再構成し、それを自動再現する。
#
# 再構成した手順:
#   手順1: 管理画面（BASIC認証）にログインし、「模擬イベント注入」タブを開く
#          -> "手順1" セクション（未認証は拒否／認証成功でタブ・フォーム部品が表示される）
#   手順2: 観測点を選び、震度値ボタン（0〜7の10段階）を選んで「新規イベント」として注入する
#          -> "手順2" セクション（観測が simulated=true で作成され、F2と同じ再判定経路に乗る）
#   手順3: 同じ観測点に対して「既存イベントへの続報」で、より大きい震度値を注入する
#          -> "手順3" セクション（#7の最大値更新ロジック：上回る場合のみ更新される）
#   手順4: さらに小さい震度値で続報を注入しても最大値・支払件数が変化しないことを確認する
#          -> "手順4" セクション（下方修正では最大値・既発生支払を変更しない）
#   手順5: 対象契約者のマイページ通知（API）に支払指図の通知が反映されることを確認する
#          -> "手順5" セクション
#   手順6: 降雨観測点に対して降雨値（mm）を「新規イベント」として注入する
#          -> "手順6" セクション（rainfallでも simulated=true・F2経路の再現を確認）
#   手順7: 続報投入時、既存イベント一覧（simulated=trueのみ）から対象イベントを選べることを確認する
#          -> "手順7" セクション
#
# 併せて QC10（エラーハンドリング）・OWASP10（特にA01 Broken Access Control、A03 Injection、
# A07 Identification and Authentication Failures）の該当観点を確認する。
#
# 実行方法（開発/テストDBのみを対象。本番サーバーへは一切接続しない。config/database.yml の
# test 環境は sqlite3 の storage/test.sqlite3 を使用する）:
#   cd src/backend
#   RAILS_ENV=test bin/rails db:test:prepare
#   bundle exec rspec ../../test/pr56/pr56_admin_simulated_events_spec.rb

require "rails_helper"

RSpec.describe "PR56: 管理画面 模擬イベント注入タブ（F5 injectSimulatedEvent）", type: :request do
  include ActiveJob::TestHelper

  let(:admin_user) { "admin" }
  let(:admin_password) { "changeme" }
  let(:valid_auth_headers) do
    { "Authorization" => "Basic #{Base64.strict_encode64("#{admin_user}:#{admin_password}")}" }
  end
  let(:invalid_auth_headers) do
    { "Authorization" => "Basic #{Base64.strict_encode64("admin:wrong-password")}" }
  end
  let(:internal_api_secret) { "shared-secret-pr56" }

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("ADMIN_BASIC_USER").and_return(admin_user)
    allow(ENV).to receive(:[]).with("ADMIN_BASIC_PASSWORD").and_return(admin_password)
    allow(ENV).to receive(:[]).with("INTERNAL_API_SECRET").and_return(internal_api_secret)
    ActiveJob::Base.queue_adapter = :test
  end

  after do
    clear_enqueued_jobs
    clear_performed_jobs
    ActiveJob::Base.queue_adapter = :test
  end

  def label(suffix)
    { label_ja: suffix, label_en: suffix, label_fr: suffix, label_zh: suffix, label_ru: suffix, label_es: suffix, label_ar: suffix }
  end

  let(:user) { User.create!(google_sub: "google-sub-pr56") }

  let(:seismic_plan) do
    Plan.create!(code: "seismic_pr56", trigger_type: "seismic", **label("震度連動"))
  end
  let(:rainfall_plan) do
    Plan.create!(code: "rainfall_pr56", trigger_type: "rainfall", **label("降雨連動"))
  end
  let(:seismic_station) do
    Station.create!(code: "seismic_tokyo_pr56", measurement_type: "seismic", **label("東京震度観測点"))
  end
  let(:rainfall_station) do
    Station.create!(code: "rainfall_tokyo_pr56", measurement_type: "rainfall", **label("東京雨量観測点"))
  end
  let(:payout_tier) do
    PayoutTier.create!(code: "ten_thousand_pr56", amount_yen: 10_000, **label("1万円相当（模擬）"))
  end

  let!(:active_status) { PolicyStatus.find_or_create_by!(code: "active") { |s| s.sort_order = 1; s.assign_attributes(label("有効")) } }
  let!(:processing_status) { PolicyStatus.find_or_create_by!(code: "processing") { |s| s.sort_order = 2; s.assign_attributes(label("支払処理中")) } }
  let!(:ordered_status) { PayoutStatus.find_or_create_by!(code: "ordered") { |s| s.sort_order = 0; s.assign_attributes(label("指図済")) } }

  let(:seismic_level_4) { SeismicIntensityLevel.create!(code: "4_pr56", sort_order: 4, **label("4")) }
  let(:seismic_level_5_weak) { SeismicIntensityLevel.create!(code: "5_weak_pr56", sort_order: 5, **label("5弱")) }
  let(:seismic_level_3) { SeismicIntensityLevel.create!(code: "3_pr56", sort_order: 3, **label("3")) }

  let!(:seismic_policy) do
    Policy.create!(
      user: user, plan: seismic_plan, station: seismic_station, payout_tier: payout_tier,
      policy_status: active_status, threshold: "5弱"
    ).tap do |policy|
      policy.update_columns(
        waiting_until: 1.day.ago,
        expires_at: 1.year.from_now
      )
    end
  end

  let!(:rainfall_policy) do
    Policy.create!(
      user: user, plan: rainfall_plan, station: rainfall_station, payout_tier: payout_tier,
      policy_status: active_status, threshold: "10 mm"
    ).tap do |policy|
      policy.update_columns(
        waiting_until: 1.day.ago,
        expires_at: 1.year.from_now
      )
    end
  end

  def notification_headers_for(target_user)
    {
      "X-Internal-API-Secret" => internal_api_secret,
      "X-Internal-Session-Token" => target_user.internal_session_token
    }
  end

  # -----------------------------------------------------------------
  # 手順1: 管理画面（BASIC認証）にログインし「模擬イベント注入」タブを開く
  # -----------------------------------------------------------------
  describe "手順1: BASIC認証・タブ表示" do
    it "認証情報なしでは401 Unauthorizedとなり、フォームの中身は一切返らない（OWASP A07/A01）" do
      get "/admin/simulated_events"

      expect(response).to have_http_status(:unauthorized)
      expect(response.body).not_to include("模擬イベント注入")
    end

    it "誤ったパスワードでは拒否される（OWASP A07：ブルートフォース耐性のある比較を利用）" do
      get "/admin/simulated_events", headers: invalid_auth_headers

      expect(response).to have_http_status(:unauthorized)
    end

    it "正しい認証情報でタブとフォーム部品（観測点・震度ボタン・降雨入力・新規/続報切替）が表示される" do
      get "/admin/simulated_events", headers: valid_auth_headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("模擬イベント注入")
      expect(response.body).to include("新規イベント")
      expect(response.body).to include("既存イベントへの続報")
      expect(response.body).to include("東京震度観測点 (seismic_tokyo_pr56")
      expect(response.body).to include("東京雨量観測点 (rainfall_tokyo_pr56")
    end
  end

  # -----------------------------------------------------------------
  # 手順2: 観測点を選び、震度値ボタンを選んで「新規イベント」として注入する
  # -----------------------------------------------------------------
  describe "手順2: 震度の新規イベント注入（F2と同一経路・simulated=true）" do
    it "新規震度イベントを注入すると observations に simulated=true で保存され、F2の再判定キューに乗る" do
      post "/admin/simulated_events",
        headers: valid_auth_headers,
        params: { station_id: seismic_station.id, event_mode: "new", seismic_intensity_level_id: seismic_level_4.id }

      expect(response).to redirect_to(admin_simulated_events_path)

      observation = Observation.find_by!(station: seismic_station)
      expect(observation.simulated).to be(true)
      expect(observation.max_value).to eq(BigDecimal("4"))
      expect(observation.observation_events.count).to eq(1)

      expect(enqueued_jobs.map { |job| job[:job] }).to include(ObservationReevaluationJob)
    end

    it "震度4は契約閾値5弱未満のため、この時点では支払は発生しない" do
      post "/admin/simulated_events",
        headers: valid_auth_headers,
        params: { station_id: seismic_station.id, event_mode: "new", seismic_intensity_level_id: seismic_level_4.id }

      observation = Observation.find_by!(station: seismic_station)
      ObservationReevaluationJob.perform_now(observation.id)

      expect(Payout.count).to eq(0)
      expect(seismic_policy.reload.policy_status.code).to eq("active")
    end
  end

  # -----------------------------------------------------------------
  # 手順3: 既存イベントへの続報で、より大きい震度値を注入する
  # -----------------------------------------------------------------
  describe "手順3: 続報投入時の最大値更新（上回る場合のみ更新、#7ロジックの再現）" do
    it "震度4→震度5弱の続報で最大値が更新され、閾値到達で支払指図が生成される" do
      post "/admin/simulated_events",
        headers: valid_auth_headers,
        params: { station_id: seismic_station.id, event_mode: "new", seismic_intensity_level_id: seismic_level_4.id }
      observation = Observation.find_by!(station: seismic_station)
      ObservationReevaluationJob.perform_now(observation.id)

      post "/admin/simulated_events",
        headers: valid_auth_headers,
        params: {
          station_id: seismic_station.id,
          event_mode: "follow_up",
          observation_id: observation.id,
          seismic_intensity_level_id: seismic_level_5_weak.id
        }
      ObservationReevaluationJob.perform_now(observation.id)

      observation.reload
      expect(observation.max_value).to eq(BigDecimal("5"))
      expect(observation.simulated).to be(true)
      expect(Payout.count).to eq(1)
      expect(seismic_policy.reload.policy_status.code).to eq("processing")
    end
  end

  # -----------------------------------------------------------------
  # 手順4: さらに小さい震度値で続報を注入しても最大値・支払件数が変化しない
  # -----------------------------------------------------------------
  describe "手順4: 下方修正の続報は最大値・既発生支払に影響しない（設計資料F3）" do
    it "5弱到達後に震度3の続報を投入しても最大値は5弱のまま、支払は取り消されない" do
      post "/admin/simulated_events",
        headers: valid_auth_headers,
        params: { station_id: seismic_station.id, event_mode: "new", seismic_intensity_level_id: seismic_level_4.id }
      observation = Observation.find_by!(station: seismic_station)
      ObservationReevaluationJob.perform_now(observation.id)

      post "/admin/simulated_events",
        headers: valid_auth_headers,
        params: {
          station_id: seismic_station.id, event_mode: "follow_up",
          observation_id: observation.id, seismic_intensity_level_id: seismic_level_5_weak.id
        }
      ObservationReevaluationJob.perform_now(observation.id)
      expect(Payout.count).to eq(1)

      post "/admin/simulated_events",
        headers: valid_auth_headers,
        params: {
          station_id: seismic_station.id, event_mode: "follow_up",
          observation_id: observation.id, seismic_intensity_level_id: seismic_level_3.id
        }
      ObservationReevaluationJob.perform_now(observation.id)

      observation.reload
      expect(observation.max_value).to eq(BigDecimal("5"))
      expect(Payout.count).to eq(1)
    end
  end

  # -----------------------------------------------------------------
  # 手順5: 対象契約者のマイページ通知（API）に支払指図の通知が反映される
  # -----------------------------------------------------------------
  describe "手順5: マイページ通知への反映（F4：支払指図と同時にアプリ内通知）" do
    it "支払指図が生成されると契約者本人のマイページ通知APIに反映される" do
      post "/admin/simulated_events",
        headers: valid_auth_headers,
        params: { station_id: seismic_station.id, event_mode: "new", seismic_intensity_level_id: seismic_level_5_weak.id }
      observation = Observation.find_by!(station: seismic_station)
      ObservationReevaluationJob.perform_now(observation.id)

      get "/api/v1/notifications", headers: notification_headers_for(user)

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["notifications"].map { |n| n["kind"] }).to include(Notification::KIND_PAYOUT_ORDERED)
    end

    it "OWASP A01: 他ユーザーには当該通知が表示されない（自分の契約・通知のみ参照可、設計資料FR-06）" do
      other_user = User.create!(google_sub: "google-sub-pr56-other")

      post "/admin/simulated_events",
        headers: valid_auth_headers,
        params: { station_id: seismic_station.id, event_mode: "new", seismic_intensity_level_id: seismic_level_5_weak.id }
      observation = Observation.find_by!(station: seismic_station)
      ObservationReevaluationJob.perform_now(observation.id)

      get "/api/v1/notifications", headers: notification_headers_for(other_user)

      body = JSON.parse(response.body)
      expect(body["notifications"]).to be_empty
    end
  end

  # -----------------------------------------------------------------
  # 手順6: 降雨観測点に降雨値（mm）を「新規イベント」として注入する
  # -----------------------------------------------------------------
  describe "手順6: 降雨の新規イベント注入" do
    it "降雨イベントも simulated=true で保存され、閾値到達で支払指図が生成される" do
      post "/admin/simulated_events",
        headers: valid_auth_headers,
        params: { station_id: rainfall_station.id, event_mode: "new", rainfall_mm: "12.5" }

      observation = Observation.find_by!(station: rainfall_station)
      ObservationReevaluationJob.perform_now(observation.id)

      expect(observation.simulated).to be(true)
      expect(observation.rainfall_mm).to eq(BigDecimal("12.5"))
      expect(Payout.count).to eq(1)
      expect(Payout.first.payout_status).to eq(ordered_status)
    end

    it "QC10 エラーハンドリング / OWASP A03: 数値化できない降雨値は422で拒否され観測は作成されない（例外の握りつぶしではなく明示的な不正入力扱い）" do
      post "/admin/simulated_events",
        headers: valid_auth_headers,
        params: { station_id: rainfall_station.id, event_mode: "new", rainfall_mm: "'; DROP TABLE observations; --" }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(Observation.exists?(station: rainfall_station)).to be(false)
      expect(Station.table_exists?).to be(true)
      expect(Observation.table_exists?).to be(true)
    end

    it "QC10 エラーハンドリング: 負の降雨値は422で拒否され観測は作成されない" do
      post "/admin/simulated_events",
        headers: valid_auth_headers,
        params: { station_id: rainfall_station.id, event_mode: "new", rainfall_mm: "-1" }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(Observation.exists?(station: rainfall_station)).to be(false)
    end

    it "QC10 エラーハンドリング: 観測点未選択のまま注入すると422で拒否される" do
      post "/admin/simulated_events",
        headers: valid_auth_headers,
        params: { event_mode: "new", rainfall_mm: "12.5" }

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  # -----------------------------------------------------------------
  # 手順7: 続報投入時、既存イベント一覧（simulated=trueのみ）から対象イベントを選べる
  # -----------------------------------------------------------------
  describe "手順7: 既存イベント一覧の選択肢（模擬イベントのみ表示）" do
    it "一覧には simulated=true の観測のみが表示され、実観測（simulated=false）は表示されない" do
      real_observation = Observation.create!(
        station: seismic_station, event_id: "real-event-pr56",
        observed_at: Time.zone.parse("2026-07-15 09:00:00"),
        seismic_intensity_level: seismic_level_4, max_value: seismic_level_4.sort_order,
        simulated: false
      )
      simulated_observation = Observation.create!(
        station: seismic_station, event_id: "simulated-event-pr56",
        observed_at: Time.zone.parse("2026-07-15 10:00:00"),
        seismic_intensity_level: seismic_level_4, max_value: seismic_level_4.sort_order,
        simulated: true
      )

      get "/admin/simulated_events", headers: valid_auth_headers

      expect(response.body).to include(simulated_observation.event_id)
      expect(response.body).not_to include(real_observation.event_id)
    end

    it "OWASP A01/A04: 実観測（simulated=false）へは続報投入経路を使えない（模擬フラグを跨いだ改ざんの防止）" do
      real_observation = Observation.create!(
        station: seismic_station, event_id: "real-event-pr56-2",
        observed_at: Time.zone.parse("2026-07-15 09:00:00"),
        seismic_intensity_level: seismic_level_4, max_value: seismic_level_4.sort_order,
        simulated: false
      )
      initial_max_value = real_observation.max_value

      post "/admin/simulated_events",
        headers: valid_auth_headers,
        params: {
          station_id: seismic_station.id, event_mode: "follow_up",
          observation_id: real_observation.id, seismic_intensity_level_id: seismic_level_5_weak.id
        }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(real_observation.reload.max_value).to eq(initial_max_value)
      expect(real_observation.simulated).to be(false)
    end
  end

  # -----------------------------------------------------------------
  # 設計資料F5「KPI集計では実イベントと区別する」の確認（既知のギャップの検出）
  #
  # 現状の KpiAggregator#todays_payout_orders_count / #average_order_latency_minutes は
  # Observation#simulated による絞り込みを行っておらず、模擬イベント経由の支払指図も
  # 実イベントと同様にKPIへ算入してしまう。これは設計資料1.5 F5「KPI集計では実イベントと
  # 区別する」の要求を満たしていないため、本テストは意図的に red（失敗）として現状のギャップ
  # を可視化する（実装済みで green になることを確認する趣旨の対象外）。
  # -----------------------------------------------------------------
  describe "設計資料F5: KPI集計での実/模擬イベントの区別（既知の未実装ギャップ・意図的red）" do
    it "模擬イベント経由の支払指図は本日の支払指図件数KPIに算入されない（現状未実装のため失敗する想定）",
      pending: "Issue #60: KpiAggregatorがObservation#simulatedで絞り込んでおらず模擬イベントがKPIに混入する（要修正）" do
      post "/admin/simulated_events",
        headers: valid_auth_headers,
        params: { station_id: seismic_station.id, event_mode: "new", seismic_intensity_level_id: seismic_level_5_weak.id }
      observation = Observation.find_by!(station: seismic_station)
      ObservationReevaluationJob.perform_now(observation.id)

      expect(Payout.count).to eq(1)

      metrics = KpiAggregator.new.call

      expect(metrics[:todays_payout_orders_count]).to eq(0)
    end
  end
end
