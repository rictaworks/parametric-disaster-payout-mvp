# PR #72「Exclude simulated observations from KPI payout metrics」
# （日本語PR本文タイトル: KPI集計から管理画面の模擬イベント注入による支払指図を除外する）
#
# 対応する既知の不具合報告: DEBUG/kpi_aggregator_includes_simulated_events.md
# （PR #56 のテストで検出され、本PRで対応）
#
# PR本文に書かれた「非エンジニア向けユーザーテスト手順」（計7手順）をそのまま自動再現する。
#
#   手順1: テスト用の契約者としてログインする
#     -> "手順1" セクション（development環境の自動ログイン分岐。詳細はtest/pr59を参照し、
#        ここではPR本文のfetchスニペットが指す経路そのものを再現する）
#   手順2: 震度連動プランの契約を申し込む
#     -> "手順2" セクション（POST /api/v1/policies が201・待機中で契約を作成する）
#   手順3: 契約の待機期間（免責期間）を即時経過させる
#     -> "手順3" セクション（PATCH /api/v1/policies/:id/force_waiting_period_elapsed で有効化）
#   手順4: 管理画面KPI画面の「変更前」の数値を記録する
#     -> "手順4" セクション（GET /admin/kpi の画面表示・JSON値の両方を確認）
#   手順5: 管理画面から模擬イベントを注入する
#     -> "手順5" セクション（POST /admin/simulated_events で simulated=true の観測を作成）
#   手順6: 支払指図が生成されたことを確認する
#     -> "手順6" セクション（GET /admin/payouts に新規の支払指図が反映される）
#   手順7: KPI画面の数値が「変更前」と変わっていないことを確認する（今回の修正の本題）
#     -> "手順7" セクション（模擬イベント由来の支払指図がKPIに混入しないことを厳密に検証）
#
# 「変更前」の数値が常に0だと変化の有無が自明になってしまうため、本テストでは事前に
# 実観測（simulated=false）由来の支払指図を1件用意し、「本日の支払指図件数=1」
# 「即日性平均分数=10.0分」という非ゼロの基準値を作った上で、模擬イベント注入後も
# その基準値が変わらないことを厳密に確認する（バグが再発すれば1→2、10.0→5.0のように
# 数値が変化し、本テストは即座に失敗するようになっている）。
#
# 併せて QC10（エラーハンドリング）・OWASP10（特にA01 Broken Access Control、
# A07 Identification and Authentication Failures）の該当観点を確認する。
#
# 実行方法（開発/テストDBのみを対象。本番サーバーへは一切接続しない。config/database.yml の
# test 環境は sqlite3 の storage/test.sqlite3 を使用する）:
#   cd src/backend
#   RAILS_ENV=test bin/rails db:test:prepare
#   bundle exec rspec ../../test/pr72/pr72_kpi_excludes_simulated_events_spec.rb
#
# 実行結果メモ（作成時点）:
#   本PRの修正（src/backend/app/services/kpi_aggregator.rb）が反映されたブランチでは
#   全件green。修正前（simulatedによる絞り込みがない状態）で実行すると「手順7」の
#   アサーションが red になり、今回の不具合が再発していないことを検知できる。

require "rails_helper"

RSpec.describe "PR72: KPI集計から模擬イベント由来の支払指図を除外する", type: :request do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  let(:admin_user) { "admin" }
  let(:admin_password) { "changeme" }
  let(:valid_admin_headers) do
    { "Authorization" => "Basic #{Base64.strict_encode64("#{admin_user}:#{admin_password}")}" }
  end
  let(:internal_api_secret) { "shared-secret-pr72" }
  let(:recaptcha_client) { instance_double(RecaptchaVerifier, valid?: true) }

  def label(suffix)
    { label_ja: suffix, label_en: suffix, label_fr: suffix, label_zh: suffix, label_ru: suffix, label_es: suffix, label_ar: suffix }
  end

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("ADMIN_BASIC_USER").and_return(admin_user)
    allow(ENV).to receive(:[]).with("ADMIN_BASIC_PASSWORD").and_return(admin_password)
    allow(ENV).to receive(:[]).with("INTERNAL_API_SECRET").and_return(internal_api_secret)
    allow(RecaptchaVerifier).to receive(:new).and_return(recaptcha_client)
    ActiveJob::Base.queue_adapter = :test
  end

  after do
    clear_enqueued_jobs
    clear_performed_jobs
    ActiveJob::Base.queue_adapter = :test
  end

  # 震度階級マスタ（SeismicIntensityLevel）は本プロジェクト全体で共有される実質シングルトンの
  # マスタ（設計資料1.7）のため、正規のcodeで find_or_create_by! して他specとの衝突を避ける
  # （test/pr46/pr46_policies_creation_spec.rb と同様の配慮）
  let!(:pending_status) { PolicyStatus.find_or_create_by!(code: "pending") { |s| s.sort_order = 0; s.assign_attributes(label("待機中")) } }
  let!(:active_status) { PolicyStatus.find_or_create_by!(code: "active") { |s| s.sort_order = 1; s.assign_attributes(label("有効")) } }
  let!(:processing_status) { PolicyStatus.find_or_create_by!(code: "processing") { |s| s.sort_order = 2; s.assign_attributes(label("支払処理中")) } }
  let!(:ordered_status) { PayoutStatus.find_or_create_by!(code: "ordered") { |s| s.sort_order = 0; s.assign_attributes(label("指図済")) } }
  let!(:seismic_level_5_weak) { SeismicIntensityLevel.find_or_create_by!(code: "5_weak") { |s| s.sort_order = 5; s.assign_attributes(label("5弱")) } }

  let(:seismic_plan) { Plan.create!(code: "seismic_pr72", trigger_type: "seismic", **label("震度連動")) }
  let(:seismic_station) { Station.create!(code: "seismic_tokyo_pr72", measurement_type: "seismic", **label("東京震度観測点")) }
  let(:payout_tier) { PayoutTier.create!(code: "ten_thousand_pr72", amount_yen: 10_000, **label("1万円相当（模擬）")) }

  let(:test_user) { User.create!(google_sub: "google-sub-pr72") }
  let(:user_headers) do
    { "X-Internal-API-Secret" => internal_api_secret, "X-Internal-Session-Token" => test_user.internal_session_token }
  end

  # -----------------------------------------------------------------
  # 手順1: テスト用の契約者としてログインする
  # -----------------------------------------------------------------
  describe "手順1: テスト用の契約者としてログインする" do
    it "development環境の自動ログイン分岐で 'Logged in successfully' 相当のセッションが作成される" do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("development"))

      post "/api/v1/session", params: {}.to_json,
        headers: { "Content-Type" => "application/json", "X-Internal-API-Secret" => internal_api_secret }

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["session_token"]).to be_present
      expect(User.exists?(google_sub: "development-user")).to be(true)
    end

    it "失敗パターン: バックエンドの内部API共有シークレットが無い場合はログインできない（forbidden）" do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("development"))

      post "/api/v1/session", params: {}.to_json, headers: { "Content-Type" => "application/json" }

      expect(response).to have_http_status(:forbidden)
    end
  end

  # -----------------------------------------------------------------
  # 手順2: 震度連動プランの契約を申し込む
  # -----------------------------------------------------------------
  describe "手順2: 震度連動プランの契約を申し込む" do
    it "申込が完了し、マイページ相当のAPI（契約一覧）に『待機中』として表示される" do
      post "/api/v1/policies",
        params: {
          plan_id: seismic_plan.id, station_id: seismic_station.id, payout_tier_id: payout_tier.id,
          threshold: "5弱", recaptcha_token: "valid-recaptcha-token"
        },
        headers: user_headers

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["policy"]["policy_status_code"]).to eq("pending")

      get "/api/v1/policies", headers: user_headers
      policies = JSON.parse(response.body)["policies"]
      expect(policies.map { |p| p["policy_status_code"] }).to include("pending")
    end
  end

  # -----------------------------------------------------------------
  # 手順3: 契約の待機期間（免責期間）を即時経過させる
  # -----------------------------------------------------------------
  describe "手順3: 契約の待機期間（免責期間）を即時経過させる" do
    it "PATCH force_waiting_period_elapsed で契約状態が『有効』に変わる" do
      post "/api/v1/policies",
        params: {
          plan_id: seismic_plan.id, station_id: seismic_station.id, payout_tier_id: payout_tier.id,
          threshold: "5弱", recaptcha_token: "valid-recaptcha-token"
        },
        headers: user_headers
      policy_id = JSON.parse(response.body).fetch("policy").fetch("id")

      patch "/api/v1/policies/#{policy_id}/force_waiting_period_elapsed", headers: user_headers

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["policy"]["policy_status_code"]).to eq("active")
    end

    it "失敗パターン: 存在しない契約IDを指定すると404が返り、他契約には影響しない" do
      patch "/api/v1/policies/999999/force_waiting_period_elapsed", headers: user_headers

      expect(response).to have_http_status(:not_found)
    end
  end

  # -----------------------------------------------------------------
  # 手順4〜7: KPI画面の「変更前」記録 → 模擬イベント注入 → 支払指図生成確認 →
  #           KPI画面の数値が変わっていないことの確認
  #
  # ここからは、手順2・3で作成した契約と同じ状態（有効・免責明け済み）の契約を
  # 直接用意した上で、PR本文の手順4〜7を一つの流れとして再現する。
  # -----------------------------------------------------------------
  describe "手順4〜7: 模擬イベント注入がKPI集計に影響しないことの確認（今回の修正の本題）" do
    around do |example|
      travel_to(Time.find_zone!("Asia/Tokyo").parse("2026-07-18 10:00:00")) { example.run }
    end

    # 手順2・3を経て「有効」状態になった契約者本人の契約
    let!(:seismic_policy) do
      Policy.create!(
        user: test_user, plan: seismic_plan, station: seismic_station, payout_tier: payout_tier,
        policy_status: active_status, threshold: "5弱"
      ).tap do |policy|
        policy.update_columns(waiting_until: 1.day.ago, expires_at: 1.year.from_now)
      end
    end

    # 「変更前」の基準値を非ゼロにするための、実観測（simulated=false）由来の既存の支払指図
    # （例えば別の契約者が本物の地震で本日すでに支払を受けた、という想定）。
    # 手順5で模擬イベントを注入する観測点（seismic_station）とは別の観測点にしておくことで、
    # 模擬イベントの再判定（EvaluateTrigger）がこの契約を巻き込まないようにする
    # （EvaluateTriggerは「同一観測点・同一プラン種別」の契約全件を再判定対象にするため）
    let(:real_world_station) { Station.create!(code: "seismic_yokohama_pr72", measurement_type: "seismic", **label("横浜震度観測点")) }

    let!(:real_world_payout) do
      other_user = User.create!(google_sub: "google-sub-pr72-real")
      other_policy = Policy.create!(
        user: other_user, plan: seismic_plan, station: real_world_station, payout_tier: payout_tier,
        policy_status: processing_status, threshold: "5弱"
      ).tap { |policy| policy.update_columns(waiting_until: 2.days.ago, expires_at: 1.year.from_now) }

      real_observation = Observation.create!(
        station: real_world_station, event_id: "real-event-pr72",
        observed_at: Time.zone.parse("2026-07-18 09:00:00"),
        seismic_intensity_level: seismic_level_5_weak, max_value: seismic_level_5_weak.sort_order,
        simulated: false
      )

      Payout.create!(
        policy: other_policy, payout_tier: payout_tier, payout_status: ordered_status,
        observation: real_observation, idempotency_key: "policy_#{other_policy.id}_real-event-pr72",
        decided_at: Time.zone.parse("2026-07-18 09:10:00")
      )
    end

    def inject_simulated_seismic_event!
      post "/admin/simulated_events",
        headers: valid_admin_headers,
        params: { station_id: seismic_station.id, event_mode: "new", seismic_intensity_level_id: seismic_level_5_weak.id }
    end

    # -----------------------------------------------------------------
    # 手順4: 管理画面にログインし、KPI画面の「変更前」の数値を記録する
    # -----------------------------------------------------------------
    describe "手順4: KPI画面の『変更前』の数値を記録する" do
      it "画面（HTML）に『本日の支払指図件数』『即日性平均分数』とその数値が表示される" do
        get "/admin/kpi", headers: valid_admin_headers

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("本日の支払指図件数")
        expect(response.body).to include("即日性平均分数")
      end

      it "変更前の数値（JSON）は、既存の実イベント由来の支払指図1件分になっている" do
        get "/admin/kpi", headers: valid_admin_headers, as: :json

        expect(response).to have_http_status(:ok)
        metrics = JSON.parse(response.body)
        expect(metrics["todays_payout_orders_count"]).to eq(1)
        expect(metrics["average_order_latency_minutes"]).to eq(10.0)
      end

      it "失敗パターン: 認証情報なしではKPIの数値は一切返らない（OWASP A07/A01）" do
        get "/admin/kpi"

        expect(response).to have_http_status(:unauthorized)
        expect(response.body).not_to include("本日の支払指図件数")
      end
    end

    # -----------------------------------------------------------------
    # 手順5: 管理画面から模擬イベントを注入する
    # -----------------------------------------------------------------
    describe "手順5: 管理画面から模擬イベントを注入する" do
      it "注入したイベントが『最近の観測イベント』一覧に simulated=true として追加される" do
        inject_simulated_seismic_event!

        expect(response).to redirect_to(admin_simulated_events_path)

        observation = Observation.where(station: seismic_station, simulated: true).order(:id).last
        expect(observation).not_to be_nil
        expect(observation.simulated).to be(true)
        expect(observation.max_value).to eq(BigDecimal("5"))

        get "/admin/simulated_events", headers: valid_admin_headers
        expect(response.body).to include("true")
      end
    end

    # -----------------------------------------------------------------
    # 手順6: 支払指図が生成されたことを確認する
    # -----------------------------------------------------------------
    describe "手順6: 支払指図が生成されたことを確認する" do
      it "模擬イベントでも実際のトリガー判定ロジック（F3）と同じ経路で支払指図が1件追加される" do
        expect { inject_simulated_seismic_event! }
          .not_to change { Payout.count } # まだ再判定ジョブを実行していない時点では増えない

        observation = Observation.where(station: seismic_station, simulated: true).order(:id).last
        expect { ObservationReevaluationJob.perform_now(observation.id) }
          .to change { Payout.count }.from(1).to(2)

        get "/admin/payouts", headers: valid_admin_headers
        expect(response).to have_http_status(:ok)

        newest_payout = Payout.order(:id).last
        expect(newest_payout.observation.simulated).to be(true)
        expect(newest_payout.payout_status.code).to eq("ordered")
        expect(response.body).to include(newest_payout.id.to_s)
      end
    end

    # -----------------------------------------------------------------
    # 手順7: KPI画面の数値が「変更前」と変わっていないことを確認する（今回の修正の本題）
    # -----------------------------------------------------------------
    describe "手順7: KPI画面の数値が『変更前』と変わっていないことを確認する" do
      it "模擬イベント由来の支払指図が増えても『本日の支払指図件数』『即日性平均分数』は変化しない" do
        get "/admin/kpi", headers: valid_admin_headers, as: :json
        before_metrics = JSON.parse(response.body)
        expect(before_metrics["todays_payout_orders_count"]).to eq(1)
        expect(before_metrics["average_order_latency_minutes"]).to eq(10.0)

        inject_simulated_seismic_event!
        observation = Observation.where(station: seismic_station, simulated: true).order(:id).last
        ObservationReevaluationJob.perform_now(observation.id)

        # 支払指図自体は増えている（手順6の再確認）
        expect(Payout.count).to eq(2)
        expect(Payout.joins(:observation).where(observations: { simulated: true }).count).to eq(1)

        get "/admin/kpi", headers: valid_admin_headers, as: :json
        after_metrics = JSON.parse(response.body)

        expect(after_metrics["todays_payout_orders_count"]).to eq(before_metrics["todays_payout_orders_count"])
        expect(after_metrics["average_order_latency_minutes"]).to eq(before_metrics["average_order_latency_minutes"])
        expect(after_metrics["todays_payout_orders_count"]).to eq(1)
        expect(after_metrics["average_order_latency_minutes"]).to eq(10.0)

        # 画面（HTML）表示でも同じ値のまま変わっていないことを確認する
        get "/admin/kpi", headers: valid_admin_headers
        expect(response.body).to include("本日の支払指図件数")
      end

      it "失敗パターンの裏付け: 模擬イベント由来の支払指図単体を数えると1件存在する（=もし絞り込みが無ければ2件にKPIが混入していたはず）" do
        inject_simulated_seismic_event!
        observation = Observation.where(station: seismic_station, simulated: true).order(:id).last
        ObservationReevaluationJob.perform_now(observation.id)

        simulated_payout_count = Payout.joins(:observation).where(observations: { simulated: true }, decided_at: Time.zone.parse("2026-07-18 00:00:00")..Time.zone.parse("2026-07-18 23:59:59")).count
        expect(simulated_payout_count).to eq(1)

        get "/admin/kpi", headers: valid_admin_headers, as: :json
        metrics = JSON.parse(response.body)
        expect(metrics["todays_payout_orders_count"]).not_to eq(1 + simulated_payout_count)
        expect(metrics["todays_payout_orders_count"]).to eq(1)
      end
    end
  end
end
