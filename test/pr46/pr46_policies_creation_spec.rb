# PR #46「契約登録API（POST /api/v1/policies）を追加：reCAPTCHA・マスタ検証・二重契約防止」
#
# PR本文の「非エンジニア向けユーザーテスト手順」は、画面がまだ存在しない内部APIのみの
# 変更であるため、次の2つの依頼文としてまとめられている。
#
#   手順1: `bundle exec rspec spec/requests/policies_spec.rb
#           spec/services/validate_and_create_policy_spec.rb
#           spec/services/recaptcha_verifier_spec.rb` を実行し「0 failures」を確認する
#   手順2（任意）: 正しい内容で契約登録APIを実際に1回呼び出し、
#           - 201 Created が返る
#           - レスポンスに policy_status_id・waiting_until が含まれ、
#             waiting_until が「今からおよそ72時間後」になっている
#           を確認する。400/409/422 それぞれの意味（reCAPTCHA失敗／二重申込／マスタ不正）も
#           あわせて確認する
#
# 本ファイルは、上記の依頼文がそのまま指す既存スイート（spec/requests/policies_spec.rb 等）に
# 依存せず、設計資料 1.5 F1 `validateAndCreatePolicy` の記述（reCAPTCHA検証→マスタ存在確認→
# 震度閾値マスタ確認→重複契約チェック→待機中状態での契約作成・免責明け時刻=開始+72時間）を
# 独立したブラックボックスの request spec として再現し、あわせて QC10（エラーハンドリング）・
# OWASP10（特にA01 Broken Access Control、A03 Injection、A07 Identification and
# Authentication Failures、A08 Software and Data Integrity Failures）の観点を確認する。
#
# 対象は開発サーバー相当のRailsアプリ（開発DB=SQLite）であり、本番サーバーには一切接続しない。
# reCAPTCHAの実通信（Google API）はテスト内でRecaptchaVerifierをダブルに差し替えて遮断する。
#
# 実行方法:
#   cd src/backend
#   RAILS_ENV=test bin/rails db:test:prepare
#   bundle exec rspec ../../test/pr46/pr46_policies_creation_spec.rb

require "rails_helper"

RSpec.describe "PR46: POST /api/v1/policies（契約登録API）", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  def label(suffix)
    { label_ja: suffix, label_en: suffix, label_fr: suffix, label_zh: suffix, label_ru: suffix, label_es: suffix, label_ar: suffix }
  end

  let(:user) { User.create!(google_sub: "google-sub-pr46") }
  let(:other_user) { User.create!(google_sub: "google-sub-pr46-other") }
  let(:internal_api_secret) { "shared-secret-pr46" }
  let(:headers) do
    {
      "X-Internal-API-Secret" => internal_api_secret,
      "X-Internal-Session-Token" => user.internal_session_token
    }
  end
  let(:recaptcha_client) { instance_double(RecaptchaVerifier, valid?: recaptcha_valid) }
  let(:recaptcha_valid) { true }

  let(:seismic_plan) { Plan.create!(code: "seismic_pr46", trigger_type: "seismic", **label("震度連動")) }
  let(:rainfall_plan) { Plan.create!(code: "rainfall_pr46", trigger_type: "rainfall", **label("降雨連動")) }
  let(:seismic_station) { Station.create!(code: "seismic_tokyo_pr46", measurement_type: "seismic", **label("東京震度観測点")) }
  let(:rainfall_station) { Station.create!(code: "rainfall_tokyo_pr46", measurement_type: "rainfall", **label("東京雨量観測点")) }
  let(:payout_tier) { PayoutTier.create!(code: "ten_thousand_pr46", amount_yen: 10_000, **label("1万円相当（模擬）")) }

  let!(:pending_status) { PolicyStatus.find_or_create_by!(code: "pending") { |s| s.sort_order = 0; s.assign_attributes(label("待機中")) } }
  let!(:active_status) { PolicyStatus.find_or_create_by!(code: "active") { |s| s.sort_order = 1; s.assign_attributes(label("有効")) } }
  let!(:processing_status) { PolicyStatus.find_or_create_by!(code: "processing") { |s| s.sort_order = 2; s.assign_attributes(label("支払処理中")) } }
  let!(:cancelled_status) { PolicyStatus.find_or_create_by!(code: "cancelled") { |s| s.sort_order = 4; s.assign_attributes(label("解約")) } }
  let!(:expired_status) { PolicyStatus.find_or_create_by!(code: "expired") { |s| s.sort_order = 5; s.assign_attributes(label("失効")) } }

  # 震度階級マスタ（SeismicIntensityLevel）は sort_order にDBレベルの一意制約を持つ、
  # 本プロジェクト全体で共有される実質シングルトンのマスタ（設計資料1.7：全10件）。
  # ファイル固有のsuffix付きcodeで作成すると、非トランザクションのテスト
  # （pr46_policies_race_condition_spec.rb 等）が永続化する正規のcode「5_weak」と
  # sort_order（5）が衝突するため、他のspecファイルと同じ正規のcodeを共有する
  let!(:seismic_level_5_weak) { SeismicIntensityLevel.find_or_create_by!(code: "5_weak") { |s| s.sort_order = 5; s.assign_attributes(label("5弱")) } }

  let(:params) do
    {
      plan_id: seismic_plan.id,
      station_id: seismic_station.id,
      payout_tier_id: payout_tier.id,
      threshold: "5弱",
      recaptcha_token: "valid-recaptcha-token"
    }
  end

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("INTERNAL_API_SECRET").and_return(internal_api_secret)
    allow(RecaptchaVerifier).to receive(:new).and_return(recaptcha_client)
  end

  # -----------------------------------------------------------------
  # 手順2: 正しい内容でAPIを1回呼び出し、201・待機中・免責明け72時間後を確認する
  # -----------------------------------------------------------------
  describe "手順2: 正常系（reCAPTCHA成功・マスタ実在・重複なし）" do
    it "201 Createdで契約が『待機中』状態で作成され、waiting_untilが申込からおよそ72時間後になる" do
      travel_to(Time.zone.parse("2026-07-17 09:00:00")) do
        post "/api/v1/policies", params: params, headers: headers

        expect(response).to have_http_status(:created)

        body = JSON.parse(response.body)
        expect(body["policy"]).to include(
          "user_id" => user.id,
          "plan_id" => seismic_plan.id,
          "station_id" => seismic_station.id,
          "payout_tier_id" => payout_tier.id,
          "policy_status_id" => pending_status.id,
          "policy_status_code" => "pending",
          "threshold" => "5弱"
        )

        policy = Policy.find(body.fetch("policy").fetch("id"))
        expect(policy.policy_status).to eq(pending_status)
        expect(policy.waiting_until).to be_within(2.seconds).of(Time.current + 72.hours)
        expect(Time.iso8601(body["policy"]["waiting_until"])).to be_within(2.seconds).of(Time.current + 72.hours)
      end
    end

    it "同じ利用者でもプランの種類（震度/降雨）が異なれば別々に契約できる" do
      post "/api/v1/policies", params: params, headers: headers
      expect(response).to have_http_status(:created)

      rainfall_params = {
        plan_id: rainfall_plan.id,
        station_id: rainfall_station.id,
        payout_tier_id: payout_tier.id,
        threshold: "10 mm",
        recaptcha_token: "valid-recaptcha-token"
      }
      post "/api/v1/policies", params: rainfall_params, headers: headers

      expect(response).to have_http_status(:created)
      expect(Policy.where(user: user).count).to eq(2)
    end
  end

  # -----------------------------------------------------------------
  # reCAPTCHA検証失敗（設計資料F1: 「reCAPTCHAを検証し、失敗なら即時拒否する」）
  # -----------------------------------------------------------------
  describe "reCAPTCHA検証が失敗した場合（400）" do
    it "400 Bad Requestを返し、契約は一切作成されない" do
      allow(recaptcha_client).to receive(:valid?).and_return(false)

      post "/api/v1/policies", params: params, headers: headers

      expect(response).to have_http_status(:bad_request)
      expect(JSON.parse(response.body)).to include("error" => "recaptcha_failed")
      expect(Policy.count).to eq(0)
    end

    it "recaptcha_tokenが空文字の場合、RecaptchaVerifierへその値がそのまま渡され検証に失敗すれば拒否される" do
      allow(recaptcha_client).to receive(:valid?).with("").and_return(false)

      post "/api/v1/policies", params: params.merge(recaptcha_token: ""), headers: headers

      expect(response).to have_http_status(:bad_request)
      expect(JSON.parse(response.body)).to include("error" => "recaptcha_failed")
      expect(Policy.count).to eq(0)
    end
  end

  # -----------------------------------------------------------------
  # マスタ不在（設計資料F1: 「プラン・観測点・支払額区分がマスタに存在することを確認する」）
  # -----------------------------------------------------------------
  describe "マスタ検証（422）" do
    it "存在しないplan_idを指定すると422 master_not_foundを返し、契約は作成されない" do
      post "/api/v1/policies", params: params.merge(plan_id: 999_999), headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      body = JSON.parse(response.body)
      expect(body["error"]).to eq("master_not_found")
      expect(body["details"]).to eq([ "plan" ])
      expect(Policy.count).to eq(0)
    end

    it "存在しないstation_idを指定すると422 master_not_foundを返す" do
      post "/api/v1/policies", params: params.merge(station_id: 999_999), headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["details"]).to include("station")
      expect(Policy.count).to eq(0)
    end

    it "存在しないpayout_tier_idを指定すると422 master_not_foundを返す" do
      post "/api/v1/policies", params: params.merge(payout_tier_id: 999_999), headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["details"]).to include("payout_tier")
      expect(Policy.count).to eq(0)
    end

    it "震度階級マスタに存在しない震度を指定すると422 threshold_invalidを返す" do
      post "/api/v1/policies", params: params.merge(threshold: "存在しない震度"), headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)).to include("error" => "threshold_invalid")
      expect(Policy.count).to eq(0)
    end

    it "プランのトリガー種別（震度）と観測点の測定種別（降雨）が一致しない組み合わせは422で拒否される" do
      post "/api/v1/policies",
        params: params.merge(station_id: rainfall_station.id),
        headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      body = JSON.parse(response.body)
      expect(body["error"]).to eq("validation_failed")
      expect(Policy.count).to eq(0)
    end
  end

  # -----------------------------------------------------------------
  # 二重契約防止（設計資料F1: 「同一ユーザー×同一プラン種別の有効（待機中・有効・支払処理中）
  # 契約が存在すれば拒否する」）
  # -----------------------------------------------------------------
  describe "二重契約防止（409）" do
    %w[pending active processing].each do |status_code|
      it "既に#{status_code}状態の同種プラン契約がある場合は409 duplicate_policyを返す" do
        Policy.create!(
          user: user, plan: seismic_plan, station: seismic_station, payout_tier: payout_tier,
          policy_status: PolicyStatus.find_by!(code: status_code), threshold: "5弱"
        )

        post "/api/v1/policies", params: params, headers: headers

        expect(response).to have_http_status(:conflict)
        expect(JSON.parse(response.body)).to include("error" => "duplicate_policy")
        expect(Policy.where(user: user).count).to eq(1)
      end
    end

    %w[cancelled expired].each do |status_code|
      it "既存契約が#{status_code}状態であれば二重契約とみなされず新規に申込できる" do
        Policy.create!(
          user: user, plan: seismic_plan, station: seismic_station, payout_tier: payout_tier,
          policy_status: PolicyStatus.find_by!(code: status_code), threshold: "5弱"
        )

        post "/api/v1/policies", params: params, headers: headers

        expect(response).to have_http_status(:created)
        expect(Policy.where(user: user).count).to eq(2)
      end
    end

    it "別の利用者は同じプランへ問題なく契約できる（重複判定はユーザー単位）" do
      Policy.create!(
        user: user, plan: seismic_plan, station: seismic_station, payout_tier: payout_tier,
        policy_status: active_status, threshold: "5弱"
      )

      other_headers = {
        "X-Internal-API-Secret" => internal_api_secret,
        "X-Internal-Session-Token" => other_user.internal_session_token
      }
      post "/api/v1/policies", params: params, headers: other_headers

      expect(response).to have_http_status(:created)
      expect(Policy.where(user: other_user).count).to eq(1)
    end
  end

  # -----------------------------------------------------------------
  # OWASP A07: 内部API向け認証（共有シークレット + 内部セッショントークン）の2段構え
  # -----------------------------------------------------------------
  describe "OWASP A07: 認証欠如時の拒否" do
    it "内部セッショントークンが無い場合は401 Unauthorizedを返し契約は作成されない" do
      post "/api/v1/policies",
        params: params,
        headers: { "X-Internal-API-Secret" => internal_api_secret }

      expect(response).to have_http_status(:unauthorized)
      expect(Policy.count).to eq(0)
    end

    it "内部API共有シークレットが無い・誤っている場合は403 Forbiddenを返し契約は作成されない" do
      post "/api/v1/policies",
        params: params,
        headers: { "X-Internal-Session-Token" => user.internal_session_token, "X-Internal-API-Secret" => "wrong-secret" }

      expect(response).to have_http_status(:forbidden)
      expect(Policy.count).to eq(0)
    end

    it "改ざん・失効した内部セッショントークンでは401 Unauthorizedを返す" do
      post "/api/v1/policies",
        params: params,
        headers: {
          "X-Internal-API-Secret" => internal_api_secret,
          "X-Internal-Session-Token" => "#{user.internal_session_token}-tampered"
        }

      expect(response).to have_http_status(:unauthorized)
      expect(Policy.count).to eq(0)
    end
  end

  # -----------------------------------------------------------------
  # OWASP A01/A08: 契約者は自分のGoogleログインsub（内部セッション）にのみ紐づけられる。
  # クライアントから任意のuser_idを送っても、それに乗っ取られないこと（マスアサインメント/IDOR対策）
  # -----------------------------------------------------------------
  describe "OWASP A01/A08: user_idのマスアサインメント・なりすまし防止" do
    it "リクエストにuser_idを含めても、作成される契約は常にセッション保持者（current_user）に紐づく" do
      post "/api/v1/policies",
        params: params.merge(user_id: other_user.id),
        headers: headers

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["policy"]["user_id"]).to eq(user.id)
      expect(Policy.where(user: other_user).count).to eq(0)
    end
  end

  # -----------------------------------------------------------------
  # OWASP A03: インジェクション対策の確認（パラメータ化クエリにより安全に処理されること）
  # -----------------------------------------------------------------
  describe "OWASP A03: インジェクション耐性" do
    it "thresholdにSQLインジェクション文字列を渡してもテーブルは破壊されず422で安全に拒否される" do
      post "/api/v1/policies",
        params: params.merge(threshold: "5弱'; DROP TABLE policies; --"),
        headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)).to include("error" => "threshold_invalid")
      expect(Policy.table_exists?).to be(true)
      expect(SeismicIntensityLevel.table_exists?).to be(true)
      expect(Policy.count).to eq(0)
    end

    it "plan_idに非数値のインジェクション文字列を渡しても422 master_not_foundとして安全に処理される" do
      post "/api/v1/policies",
        params: params.merge(plan_id: "999999999 OR 1=1; DROP TABLE plans; --"),
        headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)).to include("error" => "master_not_found")
      expect(Plan.table_exists?).to be(true)
      expect(Plan.count).to be >= 1
      expect(Policy.count).to eq(0)
    end

    # 注記（挙動確認・脆弱性ではない）: ActiveRecordのInteger型キャストはRubyの
    # String#to_i と同様に先頭の数字だけを緩く解釈する（例: "1 OR 1=1".to_i は 1）。
    # クエリ自体はプレースホルダにより常にパラメータ化されるためSQLインジェクションは
    # 成立しないが、「先頭が数字であれば残りの文字列は無視される」というID入力の緩さは
    # クライアント側のバリデーション抜けを覆い隠しうるため、挙動として記録しておく
    it "plan_idの先頭が実在IDの数字で始まる場合、残りの文字列は無視されて数値部分のみで照合される（ActiveRecordの型キャスト仕様）" do
      post "/api/v1/policies",
        params: params.merge(plan_id: "#{seismic_plan.id} OR 1=1"),
        headers: headers

      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body)["policy"]["plan_id"]).to eq(seismic_plan.id)
    end

    it "thresholdにスクリプトタグ文字列を渡してもレスポンスにそのまま反映されず422で拒否される" do
      malicious = "<script>alert(1)</script>"
      post "/api/v1/policies",
        params: params.merge(threshold: malicious),
        headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).not_to include("<script>")
      expect(Policy.count).to eq(0)
    end
  end

  # -----------------------------------------------------------------
  # QC10 エラーハンドリング: 必須パラメータ欠落時の挙動
  # -----------------------------------------------------------------
  describe "QC10 エラーハンドリング: 必須パラメータ欠落" do
    it "plan_idが未指定の場合は500ではなく422で拒否される（例外を握りつぶさず明示的なエラーとして扱う）" do
      post "/api/v1/policies", params: params.except(:plan_id), headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)).to include("error" => "master_not_found")
    end

    it "recaptcha_tokenが未指定の場合は400 recaptcha_failedで拒否される" do
      allow(recaptcha_client).to receive(:valid?).and_return(false)

      post "/api/v1/policies", params: params.except(:recaptcha_token), headers: headers

      expect(response).to have_http_status(:bad_request)
      expect(JSON.parse(response.body)).to include("error" => "recaptcha_failed")
    end
  end
end
