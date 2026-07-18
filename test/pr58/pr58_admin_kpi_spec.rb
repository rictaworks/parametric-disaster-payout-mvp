# PR #58「管理画面にKPIタブと集計APIを追加」
#
# PR本文に書かれた「非エンジニア向けユーザーテスト手順」を自動再現するテスト（バックエンド部分）。
#
# 対応する手順:
#   手順1: 管理画面にログインし、「KPI」タブを開く
#          -> "手順1" セクション（BASIC認証・タブ表示・7指標のカード表示を検証）
#   手順2: KPIのJSON形式データを確認する（/admin/kpi.json）
#          -> "手順2" セクション（JSON応答・HTMLとの数値一致・BASIC認証必須を検証）
#   手順3: マイページのアンケートフォームで「満足度」を選べることを確認する（バックエンドAPI部分）
#          -> "手順3" セクション（POST /api/v1/survey_responses が満足度付きで成功することを確認）
#   手順4（参考・任意）: 満足度が未入力・範囲外だと保存できないことの確認
#          -> "手順4" セクション（バリデーション拒否を確認）
#
# 併せて QC10（エラーハンドリング）・OWASP10（特にA01 Broken Access Control、A07 認証の欠陥）の
# 該当観点を確認する。
#
# 実行方法（開発/テストDBのみを対象。本番サーバーへは一切接続しない。config/database.yml の
# test 環境は sqlite3 の storage/test.sqlite3 を使用する）:
#   cd src/backend
#   RAILS_ENV=test bin/rails db:test:prepare
#   bundle exec rspec ../../test/pr58/pr58_admin_kpi_spec.rb

require "rails_helper"

RSpec.describe "PR58: 管理画面KPIタブ・集計API・アンケート満足度必須化", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:admin_user) { "admin" }
  let(:admin_password) { "changeme" }
  let(:valid_auth_headers) do
    { "Authorization" => "Basic #{Base64.strict_encode64("#{admin_user}:#{admin_password}")}" }
  end
  let(:invalid_auth_headers) do
    { "Authorization" => "Basic #{Base64.strict_encode64("admin:wrong-password")}" }
  end
  let(:zone) { Time.find_zone!("Asia/Tokyo") }

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("ADMIN_BASIC_USER").and_return(admin_user)
    allow(ENV).to receive(:[]).with("ADMIN_BASIC_PASSWORD").and_return(admin_password)
  end

  # ---------------------------------------------------------------------
  # 手順1: 管理画面にログインし、「KPI」タブを開く
  # ---------------------------------------------------------------------
  describe "手順1: 管理画面の「KPI」タブ" do
    it "管理画面トップのナビゲーションに「KPI」タブへのリンクが表示される" do
      get "/admin", headers: valid_auth_headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(">KPI<")
      expect(response.body).to include(admin_kpi_path)
    end

    it "「KPI」タブをクリックすると /admin/kpi に遷移し、タイトル・説明文・7つの指標カードが表示される" do
      travel_to(zone.parse("2026-07-17 23:30:00")) do
        seed_kpi_fixture_data

        get "/admin/kpi", headers: valid_auth_headers

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("KPI")
        expect(response.body).to include("登録ユーザー数や支払指図状況などの集計を確認できます。")

        %w[
          登録ユーザー数 申込完了率 契約継続率 アンケート回答数 平均満足度 本日の支払指図件数 即日性平均分数
        ].each do |label|
          expect(response.body).to include(label), "カード見出し「#{label}」が表示されていません"
        end

        # PR本文どおりの表記（パーセント・単位付き数値）で表示されること
        expect(response.body).to include("100.0%")
        expect(response.body).to include("50.0%")
        expect(response.body).to include("4.5")
        expect(response.body).to include("35.0分")
      end
    end

    it "失敗パターン: BASIC認証なしでは「500」等の生エラーを見せずに401(認証要求)で拒否される（QC10エラーハンドリング/OWASP A07）" do
      get "/admin/kpi"

      expect(response).to have_http_status(:unauthorized)
      expect(response.headers["WWW-Authenticate"]).to match(/Basic/i)
      expect(response.body).not_to include("登録ユーザー数")
    end

    it "失敗パターン: 誤ったパスワードでは401で拒否される（OWASP A01 Broken Access Control）" do
      get "/admin/kpi", headers: invalid_auth_headers

      expect(response).to have_http_status(:unauthorized)
      expect(response.body).not_to include("登録ユーザー数")
    end
  end

  # ---------------------------------------------------------------------
  # 手順2: KPIのJSON形式データを確認する（/admin/kpi.json）
  # ---------------------------------------------------------------------
  describe "手順2: /admin/kpi.json（開発者向けJSON形式）" do
    it "認証済みであればJSON形式でKPIが取得でき、値がHTML表示と一致する" do
      travel_to(zone.parse("2026-07-17 23:30:00")) do
        seed_kpi_fixture_data

        get "/admin/kpi", headers: valid_auth_headers
        html_body = response.body

        get "/admin/kpi.json", headers: valid_auth_headers
        expect(response).to have_http_status(:ok)

        json = JSON.parse(response.body)
        expect(json).to include(
          "registered_users_count" => 2,
          "application_completion_rate" => 1.0,
          "contract_continuation_rate" => 0.5,
          "survey_response_count" => 2,
          "average_satisfaction" => 4.5,
          "todays_payout_orders_count" => 1,
          "average_order_latency_minutes" => 35.0
        )

        # 手順2の失敗パターン: HTML表示とJSONの数値が食い違っていないこと
        expect(html_body).to include("#{json['registered_users_count']}")
        expect(html_body).to include("#{(json['application_completion_rate'] * 100).round(1)}%")
      end
    end

    it "失敗パターン: 認証なしでは中身(JSON本文)が一切見えない（OWASP A01: セキュリティ上の重大な問題として扱う）" do
      seed_kpi_fixture_data

      get "/admin/kpi.json"

      expect(response).to have_http_status(:unauthorized)
      expect(response.content_type).not_to match(%r{application/json})
      expect(response.body).not_to include("registered_users_count")
    end

    it "失敗パターン: 誤った認証情報では中身が見えない" do
      seed_kpi_fixture_data

      get "/admin/kpi.json", headers: invalid_auth_headers

      expect(response).to have_http_status(:unauthorized)
      expect(response.body).not_to include("registered_users_count")
    end
  end

  # ---------------------------------------------------------------------
  # 手順3: マイページのアンケートフォームで「満足度」を選べることを確認する（API部分）
  # ---------------------------------------------------------------------
  describe "手順3: POST /api/v1/survey_responses（満足度付きで送信）" do
    let(:internal_api_secret) { "shared-secret-pr58" }
    let(:user) { User.create!(google_sub: "google-sub-pr58-survey") }
    let(:headers) do
      {
        "X-Internal-API-Secret" => internal_api_secret,
        "X-Internal-Session-Token" => user.internal_session_token,
        "CONTENT_TYPE" => "application/json"
      }
    end

    before do
      allow(ENV).to receive(:[]).with("INTERNAL_API_SECRET").and_return(internal_api_secret)
    end

    it "満足度（1〜5）を選んで送信すると保存に成功し、KPIの平均満足度に反映される" do
      payout = build_completed_payout_for(user)

      post "/api/v1/survey_responses",
        params: { payout_id: payout.id, response_data: { satisfaction: 3, feedback: "テスト送信" } }.to_json,
        headers: headers

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body.dig("survey_response", "response_data", "satisfaction")).to eq(3)

      expect(KpiAggregator.new.call[:average_satisfaction]).to eq(3.0)
    end
  end

  # ---------------------------------------------------------------------
  # 手順4（参考・任意）: 満足度が未入力・範囲外だと保存できないことの確認
  # ---------------------------------------------------------------------
  describe "手順4: 満足度の必須化バリデーション" do
    let(:internal_api_secret) { "shared-secret-pr58-validation" }
    let(:user) { User.create!(google_sub: "google-sub-pr58-validation") }
    let(:headers) do
      {
        "X-Internal-API-Secret" => internal_api_secret,
        "X-Internal-Session-Token" => user.internal_session_token,
        "CONTENT_TYPE" => "application/json"
      }
    end

    before do
      allow(ENV).to receive(:[]).with("INTERNAL_API_SECRET").and_return(internal_api_secret)
    end

    it "満足度が未入力の場合は422で拒否され、SurveyResponseは保存されない" do
      payout = build_completed_payout_for(user)

      expect do
        post "/api/v1/survey_responses",
          params: { payout_id: payout.id, response_data: { feedback: "満足度なし" } }.to_json,
          headers: headers
      end.not_to change(SurveyResponse, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "満足度が範囲外（0）の場合は422で拒否される" do
      payout = build_completed_payout_for(user)

      post "/api/v1/survey_responses",
        params: { payout_id: payout.id, response_data: { satisfaction: 0, feedback: "範囲外" } }.to_json,
        headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "満足度が範囲外（6以上）の場合は422で拒否される" do
      payout = build_completed_payout_for(user)

      post "/api/v1/survey_responses",
        params: { payout_id: payout.id, response_data: { satisfaction: 6, feedback: "範囲外" } }.to_json,
        headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "満足度が数値でない文字列（不正値）の場合は422で拒否される（OWASP A03的な不正入力対策）" do
      payout = build_completed_payout_for(user)

      post "/api/v1/survey_responses",
        params: { payout_id: payout.id, response_data: { satisfaction: "abc", feedback: "不正値" } }.to_json,
        headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  # =======================================================================
  # フィクスチャ生成ヘルパー
  # =======================================================================

  def seed_kpi_fixture_data
    user_1 = User.create!(google_sub: "google-sub-pr58-kpi-1")
    user_2 = User.create!(google_sub: "google-sub-pr58-kpi-2")
    plan = find_or_create_plan("seismic_pr58_kpi")
    station = find_or_create_station("seismic_tokyo_pr58_kpi")
    payout_tier = find_or_create_payout_tier("ten_thousand_pr58_kpi")
    active_status = find_or_create_policy_status("active", 1, "有効")
    cancelled_status = find_or_create_policy_status("cancelled", 9, "解約")
    completed_status = find_or_create_payout_status("completed_simulated", 1, "支払完了（模擬）")

    policy_1 = Policy.create!(
      user: user_1, plan: plan, station: station, payout_tier: payout_tier,
      policy_status: active_status, threshold: "5強"
    ).tap { |p| p.update_columns(waiting_until: zone.parse("2026-07-15 00:00:00"), expires_at: zone.parse("2026-12-31 23:59:59")) }

    policy_2 = Policy.create!(
      user: user_2, plan: plan, station: station, payout_tier: payout_tier,
      policy_status: active_status, threshold: "5強"
    ).tap { |p| p.update_columns(waiting_until: zone.parse("2026-07-15 00:00:00"), expires_at: zone.parse("2026-12-31 23:59:59")) }

    # KPIは simulated: false の観測由来の支払指図のみを集計対象とする（PR#72）
    observation_1 = Observation.create!(
      station: station, event_id: "event-pr58-kpi-1", observed_at: zone.parse("2026-07-17 00:00:00"),
      seismic_intensity_level: find_or_create_level("level-pr58-kpi-1", 5),
      max_value: 5, simulated: false
    )
    observation_2 = Observation.create!(
      station: station, event_id: "event-pr58-kpi-2", observed_at: zone.parse("2026-07-16 22:50:00"),
      seismic_intensity_level: find_or_create_level("level-pr58-kpi-2", 6),
      max_value: 6, simulated: false
    )

    payout_1 = Payout.create!(
      policy: policy_1, payout_tier: payout_tier, payout_status: completed_status, observation: observation_1,
      idempotency_key: "policy_#{policy_1.id}_event-pr58-kpi-1", decided_at: zone.parse("2026-07-17 00:10:00")
    )
    payout_2 = Payout.create!(
      policy: policy_2, payout_tier: payout_tier, payout_status: completed_status, observation: observation_2,
      idempotency_key: "policy_#{policy_2.id}_event-pr58-kpi-2", decided_at: zone.parse("2026-07-16 23:50:00")
    )

    SurveyResponse.create!(user: user_1, payout: payout_1, response_data: { satisfaction: 4 })
    SurveyResponse.create!(user: user_2, payout: payout_2, response_data: { satisfaction: 5 })

    policy_2.update!(policy_status: cancelled_status)
  end

  def build_completed_payout_for(user)
    plan = find_or_create_plan("seismic_pr58_survey_#{user.id}")
    station = find_or_create_station("seismic_tokyo_pr58_survey_#{user.id}")
    payout_tier = find_or_create_payout_tier("ten_thousand_pr58_survey_#{user.id}")
    active_status = find_or_create_policy_status("active", 1, "有効")
    completed_status = find_or_create_payout_status("completed_simulated", 1, "支払完了（模擬）")

    policy = Policy.create!(
      user: user, plan: plan, station: station, payout_tier: payout_tier,
      policy_status: active_status, threshold: "5強"
    ).tap { |p| p.update_columns(waiting_until: 1.day.ago, expires_at: 1.year.from_now) }

    observation = Observation.create!(
      station: station, event_id: "event-pr58-survey-#{user.id}", observed_at: Time.current,
      seismic_intensity_level: find_or_create_level("level-pr58-survey-#{user.id}", 5),
      max_value: 5, simulated: true
    )

    Payout.create!(
      policy: policy, payout_tier: payout_tier, payout_status: completed_status, observation: observation,
      idempotency_key: "policy_#{policy.id}_event-pr58-survey-#{user.id}", decided_at: Time.current
    )
  end

  def find_or_create_plan(code)
    Plan.find_or_create_by!(code: code) do |p|
      p.trigger_type = "seismic"
      %i[label_ja label_en label_fr label_zh label_ru label_es label_ar].each { |attr| p.public_send("#{attr}=", "震度連動") }
    end
  end

  def find_or_create_station(code)
    Station.find_or_create_by!(code: code) do |s|
      s.measurement_type = "seismic"
      %i[label_ja label_en label_fr label_zh label_ru label_es label_ar].each { |attr| s.public_send("#{attr}=", "東京震度観測点") }
    end
  end

  def find_or_create_payout_tier(code)
    PayoutTier.find_or_create_by!(code: code) do |t|
      t.amount_yen = 10_000
      %i[label_ja label_en label_fr label_zh label_ru label_es label_ar].each { |attr| t.public_send("#{attr}=", "1万円相当（模擬）") }
    end
  end

  def find_or_create_policy_status(code, sort_order, label_ja)
    PolicyStatus.find_or_create_by!(code: code) do |s|
      s.sort_order = sort_order
      %i[label_ja label_en label_fr label_zh label_ru label_es label_ar].each { |attr| s.public_send("#{attr}=", label_ja) }
    end
  end

  def find_or_create_payout_status(code, sort_order, label_ja)
    PayoutStatus.find_or_create_by!(code: code) do |s|
      s.sort_order = sort_order
      %i[label_ja label_en label_fr label_zh label_ru label_es label_ar].each { |attr| s.public_send("#{attr}=", label_ja) }
    end
  end

  def find_or_create_level(code, sort_order)
    SeismicIntensityLevel.find_or_create_by!(code: code) do |l|
      l.sort_order = sort_order
      %i[label_ja label_en label_fr label_zh label_ru label_es label_ar].each { |attr| l.public_send("#{attr}=", "5強") }
    end
  end
end
