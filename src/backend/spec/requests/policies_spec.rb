require "rails_helper"

RSpec.describe "POST /api/v1/policies", type: :request do
  let(:user)        { create(:user) }
  let(:plan)        { create(:plan, :seismic) }
  let(:station)     { create(:station, :seismic) }
  let(:payout_tier) { create(:payout_tier) }
  let(:valid_params) do
    {
      plan_id:         plan.id,
      station_id:      station.id,
      payout_tier_id:  payout_tier.id,
      recaptcha_token: "valid_recaptcha_token"
    }
  end

  before do
    # PolicyStatus マスタを準備
    create(:policy_status, :waiting)
    create(:policy_status, :active)
    create(:policy_status, :processing)

    # reCAPTCHA 成功レスポンスをスタブ
    stub_request(:post, "https://www.google.com/recaptcha/api/siteverify")
      .to_return(
        status: 200,
        body: '{"success":true}',
        headers: { "Content-Type" => "application/json" }
      )

    # ユーザー認証をセッション経由でセットアップ
    post "/api/v1/policies", params: valid_params  # will be 401 first
    allow_any_instance_of(ApplicationController).to receive(:authenticate_user!) do |controller|
      controller.instance_variable_set(:@current_user, user)
    end
  end

  describe "正常系" do
    it "201 Createdが返る" do
      post "/api/v1/policies", params: valid_params
      expect(response).to have_http_status(:created)
    end

    it "レスポンスにstatusが'waiting'で含まれる" do
      post "/api/v1/policies", params: valid_params
      json = JSON.parse(response.body)
      expect(json["status"]).to eq("waiting")
    end

    it "waiting_untilが含まれる" do
      post "/api/v1/policies", params: valid_params
      json = JSON.parse(response.body)
      expect(json["waiting_until"]).to be_present
    end

    it "waiting_untilが作成時刻の約72時間後である" do
      freeze_time do
        post "/api/v1/policies", params: valid_params
        json = JSON.parse(response.body)
        expected = (Time.current + 72.hours).iso8601
        expect(json["waiting_until"]).to eq(expected)
      end
    end

    it "DBに契約が1件作成される" do
      expect {
        post "/api/v1/policies", params: valid_params
      }.to change(Policy, :count).by(1)
    end
  end

  describe "reCAPTCHA検証失敗（400 Bad Request）" do
    before do
      stub_request(:post, "https://www.google.com/recaptcha/api/siteverify")
        .to_return(
          status: 200,
          body: '{"success":false}',
          headers: { "Content-Type" => "application/json" }
        )
    end

    it "400が返る" do
      post "/api/v1/policies", params: valid_params
      expect(response).to have_http_status(:bad_request)
    end

    it "DBに契約が作成されない" do
      expect {
        post "/api/v1/policies", params: valid_params
      }.not_to change(Policy, :count)
    end
  end

  describe "マスタ不存在（422 Unprocessable Entity）" do
    it "存在しないプランIDで422が返る" do
      post "/api/v1/policies", params: valid_params.merge(plan_id: 0)
      expect(response).to have_http_status(422)
    end

    it "存在しない観測点IDで422が返る" do
      post "/api/v1/policies", params: valid_params.merge(station_id: 0)
      expect(response).to have_http_status(422)
    end

    it "存在しない支払額区分IDで422が返る" do
      post "/api/v1/policies", params: valid_params.merge(payout_tier_id: 0)
      expect(response).to have_http_status(422)
    end
  end

  describe "重複契約拒否（409 Conflict）" do
    before do
      waiting_status = PolicyStatus.find_by!(code: PolicyStatus::WAITING)
      create(:policy, user: user, plan: plan, station: station,
             payout_tier: payout_tier, policy_status: waiting_status)
    end

    it "409が返る" do
      post "/api/v1/policies", params: valid_params
      expect(response).to have_http_status(:conflict)
    end

    it "DBに新たな契約が作成されない" do
      expect {
        post "/api/v1/policies", params: valid_params
      }.not_to change(Policy, :count)
    end
  end

  describe "未認証（401 Unauthorized）" do
    before do
      # 認証スタブを外して本物の認証を使う
      allow_any_instance_of(ApplicationController).to receive(:authenticate_user!).and_call_original
    end

    it "セッションなしで401が返る" do
      post "/api/v1/policies", params: valid_params
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
