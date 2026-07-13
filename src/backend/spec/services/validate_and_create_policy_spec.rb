require "rails_helper"

RSpec.describe ValidateAndCreatePolicy, type: :service do
  let(:user)        { create(:user) }
  let(:plan)        { create(:plan, :seismic) }
  let(:station)     { create(:station, :seismic) }
  let(:payout_tier) { create(:payout_tier) }
  let(:valid_token) { "valid_recaptcha_token" }

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
  end

  def call_service(overrides = {})
    described_class.new(
      user:            overrides.fetch(:user, user),
      plan_id:         overrides.fetch(:plan_id, plan.id),
      station_id:      overrides.fetch(:station_id, station.id),
      payout_tier_id:  overrides.fetch(:payout_tier_id, payout_tier.id),
      recaptcha_token: overrides.fetch(:recaptcha_token, valid_token)
    ).call
  end

  describe "正常系" do
    it "契約が「待機中」ステータスで作成される" do
      result = call_service
      expect(result.success?).to be true
      expect(result.policy).to be_a(Policy)
      expect(result.policy.policy_status.code).to eq(PolicyStatus::WAITING)
    end

    it "waiting_until が作成時刻の約72時間後になる" do
      freeze_time do
        result = call_service
        expect(result.policy.waiting_until).to be_within(1.second).of(Time.current + 72.hours)
      end
    end

    it "expires_at が作成時刻の約1年後になる" do
      freeze_time do
        result = call_service
        expect(result.policy.expires_at).to be_within(1.second).of(Time.current + 1.year)
      end
    end

    it "契約がDBに保存される" do
      expect { call_service }.to change(Policy, :count).by(1)
    end
  end

  describe "reCAPTCHA検証失敗" do
    before do
      stub_request(:post, "https://www.google.com/recaptcha/api/siteverify")
        .to_return(
          status: 200,
          body: '{"success":false,"error-codes":["invalid-input-response"]}',
          headers: { "Content-Type" => "application/json" }
        )
    end

    it "契約が作成されず失敗結果を返す" do
      result = call_service
      expect(result.success?).to be false
      expect(result.error_code).to eq(:recaptcha_failed)
    end

    it "DBに契約が作成されない" do
      expect { call_service }.not_to change(Policy, :count)
    end
  end

  describe "マスタ不存在（422相当）" do
    it "存在しないプランIDを指定すると失敗する" do
      result = call_service(plan_id: 0)
      expect(result.success?).to be false
      expect(result.error_code).to eq(:master_not_found)
    end

    it "存在しない観測点IDを指定すると失敗する" do
      result = call_service(station_id: 0)
      expect(result.success?).to be false
      expect(result.error_code).to eq(:master_not_found)
    end

    it "存在しない支払額区分IDを指定すると失敗する" do
      result = call_service(payout_tier_id: 0)
      expect(result.success?).to be false
      expect(result.error_code).to eq(:master_not_found)
    end

    it "DBに契約が作成されない" do
      expect { call_service(plan_id: 0) }.not_to change(Policy, :count)
    end
  end

  describe "重複契約拒否（409相当）" do
    context "同一ユーザー×同一プラン種別で「待機中」の契約が存在する場合" do
      before do
        waiting_status = PolicyStatus.find_by!(code: PolicyStatus::WAITING)
        create(:policy, user: user, plan: plan, station: station,
               payout_tier: payout_tier, policy_status: waiting_status)
      end

      it "新規契約が作成されず失敗結果を返す" do
        result = call_service
        expect(result.success?).to be false
        expect(result.error_code).to eq(:duplicate_policy)
      end
    end

    context "同一ユーザー×同一プラン種別で「有効」の契約が存在する場合" do
      before do
        active_status = PolicyStatus.find_by!(code: PolicyStatus::ACTIVE)
        create(:policy, user: user, plan: plan, station: station,
               payout_tier: payout_tier, policy_status: active_status)
      end

      it "新規契約が作成されず失敗結果を返す" do
        result = call_service
        expect(result.success?).to be false
        expect(result.error_code).to eq(:duplicate_policy)
      end
    end

    context "同一ユーザー×同一プラン種別で「支払処理中」の契約が存在する場合" do
      before do
        processing_status = PolicyStatus.find_by!(code: PolicyStatus::PROCESSING)
        create(:policy, user: user, plan: plan, station: station,
               payout_tier: payout_tier, policy_status: processing_status)
      end

      it "新規契約が作成されず失敗結果を返す" do
        result = call_service
        expect(result.success?).to be false
        expect(result.error_code).to eq(:duplicate_policy)
      end
    end

    context "同一ユーザーだが異なるプラン種別の場合" do
      let(:rainfall_plan) { create(:plan, :rainfall) }
      let(:rainfall_station) { create(:station, :rainfall) }

      before do
        waiting_status = PolicyStatus.find_by!(code: PolicyStatus::WAITING)
        create(:policy, user: user, plan: rainfall_plan, station: rainfall_station,
               payout_tier: payout_tier, policy_status: waiting_status)
      end

      it "震度プランは別種別なので契約作成に成功する" do
        result = call_service
        expect(result.success?).to be true
      end
    end

    context "異なるユーザーが同一プラン種別の契約を持つ場合" do
      before do
        other_user = create(:user)
        waiting_status = PolicyStatus.find_by!(code: PolicyStatus::WAITING)
        create(:policy, user: other_user, plan: plan, station: station,
               payout_tier: payout_tier, policy_status: waiting_status)
      end

      it "別ユーザーの契約は影響しないので作成に成功する" do
        result = call_service
        expect(result.success?).to be true
      end
    end
  end
end
