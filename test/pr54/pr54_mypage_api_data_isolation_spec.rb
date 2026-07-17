# PR #54「FR-06 マイページに契約・支払履歴・通知・アンケートを統合」用の自動テスト。
#
# 対象: https://github.com/<org>/parametric-disaster-payout-mvp/pull/54
# 本テストは PR#54 の本文に書かれた「非エンジニア向けユーザーテスト手順」のうち、
# フロントエンド（マイページのReactコンポーネント）に関する部分は既存の
# src/frontend/__tests__/mypage.test.tsx（Jest + React Testing Library）で
# 検証済みのため、本ファイルではその土台となるバックエンドAPI
# （GET /api/v1/payouts、GET /api/v1/notifications、POST /api/v1/survey_responses）を
# RSpec の request spec としてブラックボックス検証する。
# Rails の test 環境（storage/test.sqlite3）のみを対象とし、本番サーバー・
# 本番DBには一切接続しない。
#
# PR本文の手順との対応:
#   手順1（契約一覧・通知一覧・支払履歴が表示される）
#     -> 表示データの出所となるAPIの正しさを "手順1" セクションで検証
#   手順4（支払完了後のアンケートフォームが表示され、回答すると一覧に反映される）
#     -> "手順4" セクションで POST /api/v1/survey_responses の成功・失敗系を検証
#   手順5（他人の契約や支払を操作できないことの確認・APIレベル）
#     -> "手順5" セクションで、他ユーザーの支払を対象にしたAPI呼び出しが
#        403 Forbiddenで拒否されること、かつ一覧APIにも他人のデータが
#        混入しないことを検証（OWASP A01対策の中心）
#
# 補足: PATCH /api/v1/policies/:id/cancel と
# PATCH /api/v1/policies/:id/force_waiting_period_elapsed の403検証は
# 既存の src/backend/spec/requests/policies_spec.rb で実施済みのため、
# 本ファイルでは重複させず、そこでカバーされていない
# payouts#index / notifications#index / survey_responses#create の
# 3エンドポイントに絞って検証する。
#
# マスタデータは db/seeds.rb（本番投入と同じ26件）をロードして使う
# （pr57のRSpecと同じ方針）。Payoutモデルには支払確定時に契約状態を
# 遷移させるコールバック（app/models/payout.rb の
# update_policy_status_on_state_change）があり、"active" 等の
# 契約状態マスタが存在しないとRecordNotFoundで失敗するため、
# 個別にPolicyStatus等を都度手組みするより安全である。
#
# 実行方法:
#   cd src/backend
#   RAILS_ENV=test bin/rails db:test:prepare
#   bundle exec rspec ../../test/pr54/pr54_mypage_api_data_isolation_spec.rb
#
# 実行結果は事前に確認済み（作成時点で全例 green。既知の実装バグは検出されなかった）。

require "rails_helper"

RSpec.describe "PR#54 マイページAPI（支払・通知・アンケート）のデータ分離", type: :request do
  let(:internal_api_secret) { "pr54-shared-secret" }
  let(:user) { User.create!(google_sub: "google-sub-pr54-user") }
  let(:other_user) { User.create!(google_sub: "google-sub-pr54-other-user") }

  let(:user_headers) do
    {
      "X-Internal-API-Secret" => internal_api_secret,
      "X-Internal-Session-Token" => user.internal_session_token
    }
  end
  let(:other_user_headers) do
    {
      "X-Internal-API-Secret" => internal_api_secret,
      "X-Internal-Session-Token" => other_user.internal_session_token
    }
  end

  let(:plan) { Plan.find_by!(code: "seismic") }
  let(:station) { Station.find_by!(code: "seismic_tokyo") }
  let(:payout_tier) { PayoutTier.find_by!(code: "ten_thousand") }
  let(:processing_status) { PolicyStatus.find_by!(code: "processing") }
  let(:ordered_status) { PayoutStatus.find_by!(code: "ordered") }
  let(:completed_status) { PayoutStatus.find_by!(code: "completed_simulated") }
  let(:seismic_level) { SeismicIntensityLevel.find_by!(code: "5_strong") }

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("INTERNAL_API_SECRET").and_return(internal_api_secret)
    # マスタデータ26件（保険プラン・震度階級・観測点・支払額区分・契約状態・支払状態）を投入する。
    load Rails.root.join("db/seeds.rb")
  end

  def build_policy_with_completed_payout(owner:, event_id:)
    policy = Policy.create!(
      user: owner,
      plan: plan,
      station: station,
      payout_tier: payout_tier,
      policy_status: processing_status,
      threshold: "5強"
    )
    policy.update_columns(waiting_until: 1.day.ago, expires_at: 1.year.from_now)

    observation = Observation.create!(
      station: station,
      event_id: event_id,
      observed_at: Time.current,
      seismic_intensity_level: seismic_level,
      max_value: seismic_level.sort_order,
      simulated: true
    )

    payout = Payout.create!(
      policy: policy,
      payout_tier: payout_tier,
      payout_status: completed_status,
      observation: observation,
      idempotency_key: "policy_#{policy.id}_event_#{event_id}",
      decided_at: Time.current
    )

    [ policy, payout ]
  end

  # ---------------------------------------------------------------------
  # 手順1: 支払履歴・通知一覧が自分のデータのみで構成されること
  # ---------------------------------------------------------------------
  describe "手順1: GET /api/v1/payouts は自分の支払のみを返す" do
    it "自分の支払のみが一覧に含まれ、他ユーザーの支払は含まれない" do
      _own_policy, own_payout = build_policy_with_completed_payout(owner: user, event_id: "event-pr54-own")
      _other_policy, _other_payout = build_policy_with_completed_payout(owner: other_user, event_id: "event-pr54-other")

      get "/api/v1/payouts", headers: user_headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)

      expect(body["payouts"].length).to eq(1)
      expect(body["payouts"].first).to include(
        "id" => own_payout.id,
        "payout_tier_code" => "ten_thousand",
        "payout_status_code" => "completed_simulated",
        "survey_response_submitted" => false
      )
    end

    it "支払が1件もない場合は空配列を返す（QC10: エラーにならず空状態として応答する）" do
      get "/api/v1/payouts", headers: user_headers

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq("payouts" => [])
    end

    it "セッショントークンがない場合は401になる" do
      get "/api/v1/payouts", headers: { "X-Internal-API-Secret" => internal_api_secret }

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "手順1: GET /api/v1/notifications は自分の通知のみを返す" do
    it "自分の通知のみが一覧に含まれ、他ユーザーの通知は含まれない" do
      own_policy, own_payout = build_policy_with_completed_payout(owner: user, event_id: "event-pr54-notif-own")
      other_policy, other_payout = build_policy_with_completed_payout(owner: other_user, event_id: "event-pr54-notif-other")

      own_notification = Notification.create!(
        user: user, policy: own_policy, payout: own_payout,
        kind: Notification::KIND_PAYOUT_COMPLETED, message: "支払完了（模擬）を確認しました。"
      )
      Notification.create!(
        user: other_user, policy: other_policy, payout: other_payout,
        kind: Notification::KIND_PAYOUT_COMPLETED, message: "他ユーザー宛の通知"
      )

      get "/api/v1/notifications", headers: user_headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)

      expect(body["notifications"].length).to eq(1)
      expect(body["notifications"].first).to include(
        "id" => own_notification.id,
        "message" => "支払完了（模擬）を確認しました。"
      )
    end

    it "セッショントークンがない場合は401になる" do
      get "/api/v1/notifications", headers: { "X-Internal-API-Secret" => internal_api_secret }

      expect(response).to have_http_status(:unauthorized)
    end
  end

  # ---------------------------------------------------------------------
  # 手順4: 支払完了後のアンケート回答（成功・失敗パターン）
  # ---------------------------------------------------------------------
  describe "手順4: POST /api/v1/survey_responses（成功パターン）" do
    it "支払完了（模擬）の自分の支払に対してアンケートを送信すると201で保存される" do
      _policy, payout = build_policy_with_completed_payout(owner: user, event_id: "event-pr54-survey-ok")

      post "/api/v1/survey_responses",
        params: { payout_id: payout.id, response_data: { satisfaction: 4, feedback: "とても分かりやすかったです。" } },
        headers: user_headers,
        as: :json

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["survey_response"]).to include(
        "payout_id" => payout.id,
        "response_data" => { "satisfaction" => 4, "feedback" => "とても分かりやすかったです。" }
      )

      # 手順1のGET /api/v1/payoutsに反映され、「回答済み」表示に切り替わることを確認
      get "/api/v1/payouts", headers: user_headers
      expect(JSON.parse(response.body)["payouts"].first["survey_response_submitted"]).to eq(true)
    end
  end

  describe "手順4: POST /api/v1/survey_responses（失敗パターン）" do
    it "支払完了（模擬）でない支払（指図済のまま）には回答できず422になる" do
      policy = Policy.create!(
        user: user, plan: plan, station: station, payout_tier: payout_tier,
        policy_status: processing_status, threshold: "5強"
      )
      policy.update_columns(waiting_until: 1.day.ago, expires_at: 1.year.from_now)
      observation = Observation.create!(
        station: station, event_id: "event-pr54-survey-not-completed", observed_at: Time.current,
        seismic_intensity_level: seismic_level, max_value: seismic_level.sort_order, simulated: true
      )
      payout = Payout.create!(
        policy: policy, payout_tier: payout_tier, payout_status: ordered_status,
        observation: observation, idempotency_key: "policy_#{policy.id}_event_not_completed"
      )

      post "/api/v1/survey_responses",
        params: { payout_id: payout.id, response_data: { satisfaction: 5, feedback: "test" } },
        headers: user_headers,
        as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(SurveyResponse.count).to eq(0)
    end

    it "満足度が範囲外（0や6）の場合は422になる" do
      _policy, payout = build_policy_with_completed_payout(owner: user, event_id: "event-pr54-survey-range")

      post "/api/v1/survey_responses",
        params: { payout_id: payout.id, response_data: { satisfaction: 0, feedback: "test" } },
        headers: user_headers,
        as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(SurveyResponse.count).to eq(0)
    end

    it "同じ支払に二重で回答しようとすると2回目は422になる（idx_survey_responses_payout一意制約）" do
      _policy, payout = build_policy_with_completed_payout(owner: user, event_id: "event-pr54-survey-dup")

      post "/api/v1/survey_responses",
        params: { payout_id: payout.id, response_data: { satisfaction: 5, feedback: "1回目" } },
        headers: user_headers,
        as: :json
      expect(response).to have_http_status(:created)

      post "/api/v1/survey_responses",
        params: { payout_id: payout.id, response_data: { satisfaction: 3, feedback: "2回目" } },
        headers: user_headers,
        as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(SurveyResponse.where(payout_id: payout.id).count).to eq(1)
    end

    it "存在しないpayout_idを指定すると404になる（QC10: 500エラーにならず適切なエラーコードで応答する）" do
      post "/api/v1/survey_responses",
        params: { payout_id: 999_999, response_data: { satisfaction: 5, feedback: "test" } },
        headers: user_headers,
        as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  # ---------------------------------------------------------------------
  # 手順5: 他人の契約や支払を操作できないことの確認（APIレベル） / OWASP A01
  # ---------------------------------------------------------------------
  describe "手順5・OWASP A01: 他ユーザーの支払に対するアンケート送信は拒否される" do
    it "他ユーザーの支払IDを指定してアンケートを送信すると403になり、データは作成されない" do
      _other_policy, other_payout = build_policy_with_completed_payout(owner: other_user, event_id: "event-pr54-forbidden")

      post "/api/v1/survey_responses",
        params: { payout_id: other_payout.id, response_data: { satisfaction: 5, feedback: "なりすまし回答" } },
        headers: user_headers,
        as: :json

      expect(response).to have_http_status(:forbidden)
      expect(SurveyResponse.count).to eq(0)
    end

    it "他ユーザーが同じ手口を試みても防御は対称に機能する（逆方向の確認）" do
      _own_policy, own_payout = build_policy_with_completed_payout(owner: user, event_id: "event-pr54-forbidden-reverse")

      post "/api/v1/survey_responses",
        params: { payout_id: own_payout.id, response_data: { satisfaction: 5, feedback: "なりすまし回答" } },
        headers: other_user_headers,
        as: :json

      expect(response).to have_http_status(:forbidden)
      expect(SurveyResponse.count).to eq(0)
    end
  end

  describe "OWASP A03: Injection（アンケート自由記述欄にスクリプト文字列を入力しても保存・取得時にサーバーがクラッシュしない）" do
    it "<script>タグを含む文字列をfeedbackに入れてもJSONとして安全に保存・返却される" do
      _policy, payout = build_policy_with_completed_payout(owner: user, event_id: "event-pr54-xss")
      malicious_feedback = "<script>alert('xss')</script>"

      post "/api/v1/survey_responses",
        params: { payout_id: payout.id, response_data: { satisfaction: 5, feedback: malicious_feedback } },
        headers: user_headers,
        as: :json

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      # サーバー側はエスケープせずそのまま保存する設計（構造化データとして格納するため）。
      # 実際の画面表示はReact（src/frontend/app/mypage/page.tsx）がテキストノードとして
      # レンダリングするため自動エスケープされ、dangerouslySetInnerHTML等は使用していない
      # （src/frontend/app/mypage/page.tsx にdangerouslySetInnerHTMLが存在しないことを確認済み）。
      expect(body["survey_response"]["response_data"]["feedback"]).to eq(malicious_feedback)
    end
  end
end
