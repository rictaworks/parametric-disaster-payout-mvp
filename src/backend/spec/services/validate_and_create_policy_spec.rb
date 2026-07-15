require "rails_helper"

RSpec.describe ValidateAndCreatePolicy do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { User.create!(google_sub: "google-sub-policy-service") }
  let(:plan) do
    Plan.create!(
      code: "seismic_policy_service",
      trigger_type: "seismic",
      label_ja: "震度連動",
      label_en: "Seismic-linked",
      label_fr: "Lié aux séismes",
      label_zh: "震度連動",
      label_ru: "Сейсмическая привязка",
      label_es: "Vinculado a sismos",
      label_ar: "مرتبط بالزلازل"
    )
  end
  let(:station) do
    Station.create!(
      code: "seismic_tokyo_policy_service",
      measurement_type: "seismic",
      label_ja: "東京震度観測点",
      label_en: "Tokyo seismic station",
      label_fr: "Tokyo seismic station",
      label_zh: "Tokyo seismic station",
      label_ru: "Tokyo seismic station",
      label_es: "Tokyo seismic station",
      label_ar: "Tokyo seismic station"
    )
  end
  let(:payout_tier) do
    PayoutTier.create!(
      code: "ten_thousand_policy_service",
      amount_yen: 10_000,
      label_ja: "1万円相当（模擬）",
      label_en: "Equivalent to JPY 10,000 (simulated)",
      label_fr: "Equivalent to JPY 10,000 (simulated)",
      label_zh: "Equivalent to JPY 10,000 (simulated)",
      label_ru: "Equivalent to JPY 10,000 (simulated)",
      label_es: "Equivalent to JPY 10,000 (simulated)",
      label_ar: "Equivalent to JPY 10,000 (simulated)"
    )
  end
  let!(:pending_status) do
    PolicyStatus.create!(
      code: "pending",
      sort_order: 0,
      label_ja: "待機中",
      label_en: "Pending",
      label_fr: "Pending",
      label_zh: "Pending",
      label_ru: "Pending",
      label_es: "Pending",
      label_ar: "Pending"
    )
  end
  let!(:active_status) do
    PolicyStatus.create!(
      code: "active",
      sort_order: 1,
      label_ja: "有効",
      label_en: "Active",
      label_fr: "Active",
      label_zh: "Active",
      label_ru: "Active",
      label_es: "Active",
      label_ar: "Active"
    )
  end
  let!(:processing_status) do
    PolicyStatus.create!(
      code: "processing",
      sort_order: 2,
      label_ja: "支払処理中",
      label_en: "Processing payout",
      label_fr: "Processing payout",
      label_zh: "Processing payout",
      label_ru: "Processing payout",
      label_es: "Processing payout",
      label_ar: "Processing payout"
    )
  end
  let!(:seismic_intensity_level_5_weak) do
    SeismicIntensityLevel.create!(
      code: "5_weak",
      sort_order: 5,
      label_ja: "5弱",
      label_en: "5 weak",
      label_fr: "5 weak",
      label_zh: "5 weak",
      label_ru: "5 weak",
      label_es: "5 weak",
      label_ar: "5 weak"
    )
  end
  let(:recaptcha_client) { instance_double(RecaptchaVerifier, valid?: recaptcha_valid) }
  let(:recaptcha_valid) { true }
  let(:service) do
    described_class.new(
      user: user,
      plan_id: plan_id,
      station_id: station_id,
      payout_tier_id: payout_tier_id,
      threshold: threshold,
      recaptcha_token: recaptcha_token
    )
  end
  let(:plan_id) { plan.id }
  let(:station_id) { station.id }
  let(:payout_tier_id) { payout_tier.id }
  let(:threshold) { "5弱" }
  let(:recaptcha_token) { "token-123" }

  before do
    allow(RecaptchaVerifier).to receive(:new).and_return(recaptcha_client)
  end

  it "creates a pending policy and records waiting_until 72 hours ahead" do
    travel_to(Time.zone.parse("2026-07-15 09:00:00")) do
      result = service.call

      expect(result).to be_success
      expect(result.status).to eq(:created)
      expect(result.policy).to be_persisted
      expect(result.policy.policy_status).to eq(pending_status)
      expect(result.policy.waiting_until).to be_within(5.seconds).of(Time.current + 72.hours)
      expect(result.policy.expires_at).to be_within(5.seconds).of(Time.current + 1.year)
    end
  end

  it "rejects invalid reCAPTCHA tokens with 400 semantics" do
    allow(recaptcha_client).to receive(:valid?).and_return(false)

    result = service.call

    expect(result).not_to be_success
    expect(result.status).to eq(:bad_request)
    expect(result.error).to eq("recaptcha_failed")
    expect(Policy.count).to eq(0)
  end

  it "rejects missing master records with 422 semantics" do
    result = described_class.new(
      user: user,
      plan_id: 123_456,
      station_id: 234_567,
      payout_tier_id: 345_678,
      threshold: threshold,
      recaptcha_token: recaptcha_token
    ).call

    expect(result).not_to be_success
    expect(result.status).to eq(:unprocessable_entity)
    expect(result.error).to eq("master_not_found")
    expect(result.details).to include(:plan, :station, :payout_tier)
  end

  it "rejects a seismic threshold that does not match any seismic intensity level master" do
    result = described_class.new(
      user: user,
      plan_id: plan_id,
      station_id: station_id,
      payout_tier_id: payout_tier_id,
      threshold: "存在しない震度",
      recaptcha_token: recaptcha_token
    ).call

    expect(result).not_to be_success
    expect(result.status).to eq(:unprocessable_entity)
    expect(result.error).to eq("threshold_invalid")
    expect(Policy.count).to eq(0)
  end

  it "does not require a master match for rainfall plan thresholds" do
    rainfall_plan = Plan.create!(
      code: "rainfall_policy_service",
      trigger_type: "rainfall",
      label_ja: "降雨連動",
      label_en: "Rainfall-linked",
      label_fr: "Rainfall-linked",
      label_zh: "Rainfall-linked",
      label_ru: "Rainfall-linked",
      label_es: "Rainfall-linked",
      label_ar: "Rainfall-linked"
    )
    rainfall_station = Station.create!(
      code: "rainfall_tokyo_policy_service",
      measurement_type: "rainfall",
      label_ja: "東京雨量観測点",
      label_en: "Tokyo rainfall station",
      label_fr: "Tokyo rainfall station",
      label_zh: "Tokyo rainfall station",
      label_ru: "Tokyo rainfall station",
      label_es: "Tokyo rainfall station",
      label_ar: "Tokyo rainfall station"
    )

    result = described_class.new(
      user: user,
      plan_id: rainfall_plan.id,
      station_id: rainfall_station.id,
      payout_tier_id: payout_tier_id,
      threshold: "50mm/h",
      recaptcha_token: recaptcha_token
    ).call

    expect(result).to be_success
    expect(result.policy.threshold).to eq("50mm/h")
  end

  %w[pending active processing].each do |status_code|
    it "rejects duplicate policies when a #{status_code} policy already exists" do
      existing_status = PolicyStatus.find_by!(code: status_code)
      Policy.create!(
        user: user,
        plan: plan,
        station: station,
        payout_tier: payout_tier,
        policy_status: existing_status,
        threshold: threshold
      )

      result = service.call

      expect(result).not_to be_success
      expect(result.status).to eq(:conflict)
      expect(result.error).to eq("duplicate_policy")
    end
  end

  it "acquires the user row lock before checking for or creating a duplicate policy" do
    # A real transaction blocks at user.lock! until a concurrent request's
    # transaction commits, so the duplicate check must run after the lock is
    # acquired, not before it, or two concurrent requests could both pass the
    # check before either has written its policy.
    expect(user).to receive(:lock!).ordered.and_call_original
    expect(service).to receive(:duplicate_policy_exists?).ordered.and_call_original

    result = service.call

    expect(result).to be_success
  end

  it "rejects the request and creates no policy when the post-lock duplicate check finds one" do
    # Simulates a concurrent request's policy becoming visible only once this
    # service has acquired the lock (i.e. after another transaction committed
    # while this one was waiting on the row lock).
    allow(service).to receive(:duplicate_policy_exists?).and_return(true)

    result = service.call

    expect(result).not_to be_success
    expect(result.status).to eq(:conflict)
    expect(result.error).to eq("duplicate_policy")
    expect(Policy.where(user: user).count).to eq(0)
  end
end
