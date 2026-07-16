require 'rails_helper'

RSpec.describe User, type: :model do
  subject(:user) { described_class.new(google_sub: "google-sub-123") }

  it { is_expected.to validate_presence_of(:google_sub) }
  it { is_expected.to validate_uniqueness_of(:google_sub) }
  it { is_expected.to have_many(:policies).dependent(:destroy) }
  it { is_expected.to have_many(:notifications).dependent(:destroy) }
  it { is_expected.to have_many(:survey_responses).dependent(:destroy) }
end

RSpec.describe Policy, type: :model do
  let(:station) do
    Station.create!(
      code: "seismic_tokyo_policy_spec",
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

  subject(:policy) do
    described_class.new(
      user: User.create!(google_sub: "google-sub-policy"),
      plan: Plan.create!(
        code: "seismic_policy_spec",
        trigger_type: "seismic",
        label_ja: "震度連動",
        label_en: "Seismic-linked",
        label_fr: "Lié aux séismes",
        label_zh: "震度連動",
        label_ru: "Сейсмическая привязка",
        label_es: "Vinculado a sismos",
        label_ar: "مرتبط بالزلازل"
      ),
      station: station,
      payout_tier: PayoutTier.create!(
        code: "ten_thousand_policy_spec",
        amount_yen: 10_000,
        label_ja: "1万円相当（模擬）",
        label_en: "Equivalent to JPY 10,000 (simulated)",
        label_fr: "Equivalent to JPY 10,000 (simulated)",
        label_zh: "Equivalent to JPY 10,000 (simulated)",
        label_ru: "Equivalent to JPY 10,000 (simulated)",
        label_es: "Equivalent to JPY 10,000 (simulated)",
        label_ar: "Equivalent to JPY 10,000 (simulated)"
      ),
      policy_status: PolicyStatus.create!(
        code: "active_policy_spec",
        sort_order: 1,
        label_ja: "有効",
        label_en: "Active",
        label_fr: "Active",
        label_zh: "Active",
        label_ru: "Active",
        label_es: "Active",
        label_ar: "Active"
      ),
      threshold: "5弱"
    )
  end

  it { is_expected.to belong_to(:user) }
  it { is_expected.to belong_to(:plan) }
  it "belongs to station optionally" do
    expect(described_class.reflect_on_association(:station).options[:optional]).to be_truthy
  end
  it { is_expected.to belong_to(:payout_tier) }
  it { is_expected.to belong_to(:policy_status) }
  it { is_expected.to have_many(:payouts).dependent(:destroy) }
  it { is_expected.to have_many(:notifications).dependent(:destroy) }
  it { is_expected.to validate_presence_of(:threshold) }

  it "requires station on creation (new record)" do
    new_policy = Policy.new(
      user: policy.user,
      plan: policy.plan,
      payout_tier: policy.payout_tier,
      policy_status: policy.policy_status,
      threshold: "5弱",
      station: nil
    )
    expect(new_policy).not_to be_valid
    expect(new_policy.errors[:station]).to include("can't be blank")
  end

  context "when updating attributes" do
    before { policy.save! }

    it "prevents clearing station once set" do
      policy.station = nil
      expect(policy).not_to be_valid
      expect(policy.errors[:station]).to include("cannot be removed once it has been set")
    end

    it "prevents clearing waiting_until once set" do
      policy.waiting_until = nil
      expect(policy).not_to be_valid
      expect(policy.errors[:waiting_until]).to include("cannot be removed once it has been set")
    end
  end

  context "when waiting_until is initialized" do
    it "forces waiting_until to be 72 hours after creation regardless of inputs" do
      custom_policy = Policy.create!(
        user: policy.user,
        plan: policy.plan,
        station: station,
        payout_tier: policy.payout_tier,
        policy_status: policy.policy_status,
        threshold: "5弱",
        waiting_until: 1.day.from_now
      )
      expect(custom_policy.waiting_until).to be_within(5.seconds).of(Time.current + 72.hours)
    end

    it "forces waiting_until to be 72 hours after Time.current even if a custom created_at is provided" do
      custom_policy = Policy.create!(
        user: policy.user,
        plan: policy.plan,
        station: station,
        payout_tier: policy.payout_tier,
        policy_status: policy.policy_status,
        threshold: "5弱",
        created_at: 1.week.ago
      )
      expect(custom_policy.waiting_until).to be_within(5.seconds).of(Time.current + 72.hours)
    end
  end

  context "when handling legacy policies with nil station or waiting_until" do
    let(:legacy_policy) do
      p = Policy.create!(
        user: policy.user,
        plan: policy.plan,
        station: station,
        payout_tier: policy.payout_tier,
        policy_status: policy.policy_status,
        threshold: "5弱"
      )
      p.update_columns(station_id: nil, waiting_until: nil)
      p
    end

    it "allows updating other attributes (e.g. terminated_at) without validation errors" do
      legacy_policy.terminated_at = Time.current
      expect(legacy_policy).to be_valid
    end
  end

  context "when waiting_until is updated" do
    before { policy.save! }

    it "allows extending waiting_until" do
      policy.waiting_until = policy.waiting_until + 1.day
      expect(policy).to be_valid
    end

    it "prevents moving waiting_until forward" do
      policy.waiting_until = policy.waiting_until - 1.day
      expect(policy).not_to be_valid
      expect(policy.errors[:waiting_until]).to include("cannot be moved forward (shortened)")
    end
  end

  it "sets expires_at to one year after creation when omitted" do
    policy.expires_at = nil
    policy.valid?
    expect(policy.expires_at).to be_present
    expect(policy.expires_at).to be_within(5.seconds).of(Time.current + 1.year)
  end

  it "sets waiting_until to 72 hours after creation when omitted" do
    policy.waiting_until = nil
    policy.valid?
    expect(policy.waiting_until).to be_present
    expect(policy.waiting_until).to be_within(5.seconds).of(Time.current + 72.hours)
  end

  it "validates that station measurement type matches plan trigger type" do
    invalid_station = Station.create!(
      code: "rainfall_tokyo_policy_spec",
      measurement_type: "rainfall",
      label_ja: "東京雨量観測点",
      label_en: "Tokyo rainfall station",
      label_fr: "Tokyo rainfall station",
      label_zh: "Tokyo rainfall station",
      label_ru: "Tokyo rainfall station",
      label_es: "Tokyo rainfall station",
      label_ar: "Tokyo rainfall station"
    )
    policy.station = invalid_station
    expect(policy).not_to be_valid
    expect(policy.errors[:station]).to include("measurement type must match plan trigger type")
  end

  context "when payouts exist" do
    before do
      policy.save!
      observation = Observation.create!(
        station: station,
        seismic_intensity_level: SeismicIntensityLevel.create!(
          code: "5_weak_policy_update_spec",
          sort_order: 5,
          label_ja: "5弱",
          label_en: "5 weak",
          label_fr: "5 weak",
          label_zh: "5 weak",
          label_ru: "5 weak",
          label_es: "5 weak",
          label_ar: "5 weak"
        ),
        event_id: "event-policy-update",
        observed_at: policy.waiting_until + 1.hour
      )
      Payout.create!(
        policy: policy,
        payout_tier: policy.payout_tier,
        payout_status: PayoutStatus.create!(
          code: "ordered_policy_update_spec",
          sort_order: 0,
          label_ja: "指図済",
          label_en: "Ordered",
          label_fr: "Ordered",
          label_zh: "Ordered",
          label_ru: "Ordered",
          label_es: "Ordered",
          label_ar: "Ordered"
        ),
        observation: observation,
        idempotency_key: "payout-policy-update-123"
      )
    end

    it "forbids updating user_id" do
      policy.user = User.create!(google_sub: "another-user-for-policy-update")
      expect(policy).not_to be_valid
      expect(policy.errors[:user]).to include("cannot be changed because payouts already exist")
    end

    it "forbids updating station_id" do
      another_station = Station.create!(
        code: "another_station_policy_update",
        measurement_type: "seismic",
        label_ja: "大阪",
        label_en: "Osaka",
        label_fr: "Osaka",
        label_zh: "Osaka",
        label_ru: "Osaka",
        label_es: "Osaka",
        label_ar: "Osaka"
      )
      policy.station = another_station
      expect(policy).not_to be_valid
      expect(policy.errors[:station]).to include("cannot be changed because payouts already exist")
    end

    it "forbids updating payout_tier_id" do
      another_tier = PayoutTier.create!(
        code: "another_tier_policy_update",
        amount_yen: 30_000,
        label_ja: "3万円",
        label_en: "30k",
        label_fr: "30k",
        label_zh: "30k",
        label_ru: "30k",
        label_es: "30k",
        label_ar: "30k"
      )
      policy.payout_tier = another_tier
      expect(policy).not_to be_valid
      expect(policy.errors[:payout_tier]).to include("cannot be changed because payouts already exist")
    end

    it "forbids updating plan_id" do
      another_plan = Plan.create!(
        code: "another_plan_policy_update",
        trigger_type: "seismic",
        label_ja: "temp", label_en: "temp", label_fr: "temp", label_zh: "temp", label_ru: "temp", label_es: "temp", label_ar: "temp"
      )
      policy.plan = another_plan
      expect(policy).not_to be_valid
      expect(policy.errors[:plan]).to include("cannot be changed because payouts already exist")
    end

    it "forbids updating threshold" do
      policy.threshold = "6弱"
      expect(policy).not_to be_valid
      expect(policy.errors[:threshold]).to include("cannot be changed because payouts already exist")
    end

    it "forbids updating waiting_until" do
      policy.waiting_until = policy.waiting_until + 1.day
      expect(policy).not_to be_valid
      expect(policy.errors[:waiting_until]).to include("cannot be changed because payouts already exist")
    end
  end
end

RSpec.describe Observation, type: :model do
  let(:seismic_station) do
    Station.create!(
      code: "seismic_tokyo_obs_spec",
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

  let(:rainfall_station) do
    Station.create!(
      code: "rainfall_tokyo_obs_spec",
      measurement_type: "rainfall",
      label_ja: "東京雨量観測点",
      label_en: "Tokyo rainfall station",
      label_fr: "Tokyo rainfall station",
      label_zh: "Tokyo rainfall station",
      label_ru: "Tokyo rainfall station",
      label_es: "Tokyo rainfall station",
      label_ar: "Tokyo rainfall station"
    )
  end

  let(:seismic_intensity_level) do
    SeismicIntensityLevel.create!(
      code: "5_weak_obs_spec",
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

  subject(:observation) do
    described_class.new(
      station: seismic_station,
      seismic_intensity_level: seismic_intensity_level,
      event_id: "event-123",
      simulated: false,
      observed_at: Time.current
    )
  end

  it { is_expected.to belong_to(:station) }
  it { is_expected.to validate_presence_of(:observed_at) }

  it "requires seismic intensity for seismic stations" do
    observation.seismic_intensity_level = nil
    observation.valid?
    expect(observation.errors[:seismic_intensity_level]).to include("can't be blank")
  end

  it "forbids rainfall value for seismic stations" do
    observation.rainfall_mm = 10.0
    expect(observation).not_to be_valid
    expect(observation.errors[:rainfall_mm]).to include("must be blank for seismic stations")
  end

  it "requires rainfall values for rainfall stations" do
    observation.station = rainfall_station
    observation.seismic_intensity_level = nil
    observation.rainfall_mm = nil
    observation.event_id = nil # event_id must be nil for rainfall

    observation.valid?
    expect(observation.errors[:rainfall_mm]).to include("can't be blank")
  end

  it "forbids seismic intensity for rainfall stations" do
    observation.station = rainfall_station
    observation.rainfall_mm = 50.0
    observation.event_id = nil
    observation.seismic_intensity_level = seismic_intensity_level
    expect(observation).not_to be_valid
    expect(observation.errors[:seismic_intensity_level]).to include("must be blank for rainfall stations")
  end

  it "requires event_id for seismic stations" do
    observation.event_id = nil
    observation.valid?
    expect(observation.errors[:event_id]).to include("can't be blank")
  end

  it "forbids event_id for rainfall stations" do
    observation.station = rainfall_station
    observation.rainfall_mm = 50.0
    observation.event_id = "event-123"
    observation.valid?
    expect(observation.errors[:event_id]).to include("must be blank for rainfall stations")
  end

  it "enforces uniqueness of event_id scope to station_id for seismic stations" do
    observation.save!
    duplicate = described_class.new(
      station: seismic_station,
      seismic_intensity_level: seismic_intensity_level,
      event_id: "event-123",
      observed_at: Time.current + 1.hour
    )
    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:event_id]).to include("has already been taken")
  end

  it "enforces uniqueness of observed_at scope to station_id for rainfall stations" do
    obs_time = Time.current.change(usec: 0)
    described_class.create!(
      station: rainfall_station,
      rainfall_mm: 50.0,
      observed_at: obs_time
    )
    duplicate = described_class.new(
      station: rainfall_station,
      rainfall_mm: 30.0,
      observed_at: obs_time
    )
    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:observed_at]).to include("has already been taken")
  end

  it "does not enforce uniqueness of observed_at scope to station_id for seismic stations with different event_ids" do
    obs_time = Time.current.change(usec: 0)
    described_class.create!(
      station: seismic_station,
      seismic_intensity_level: seismic_intensity_level,
      event_id: "event-123",
      observed_at: obs_time
    )
    duplicate = described_class.new(
      station: seismic_station,
      seismic_intensity_level: seismic_intensity_level,
      event_id: "event-456",
      observed_at: obs_time
    )
    expect(duplicate).to be_valid
  end

  context "when referenced by payouts" do
    before do
      observation.observed_at = Time.current + 80.hours
      observation.save!
      Payout.create!(
        policy: Policy.create!(
          user: User.create!(google_sub: "google-sub-observation-guard"),
          plan: Plan.first || Plan.create!(
            code: "temp_plan_obs_guard",
            trigger_type: "seismic",
            label_ja: "temp", label_en: "temp", label_fr: "temp", label_zh: "temp", label_ru: "temp", label_es: "temp", label_ar: "temp"
          ),
          station: seismic_station,
          payout_tier: PayoutTier.first || PayoutTier.create!(
            code: "temp_tier_obs_guard",
            amount_yen: 10_000,
            label_ja: "temp", label_en: "temp", label_fr: "temp", label_zh: "temp", label_ru: "temp", label_es: "temp", label_ar: "temp"
          ),
          policy_status: PolicyStatus.first || PolicyStatus.create!(
            code: "temp_status_obs_guard",
            sort_order: 1,
            label_ja: "temp", label_en: "temp", label_fr: "temp", label_zh: "temp", label_ru: "temp", label_es: "temp", label_ar: "temp"
          ),
          threshold: "5弱"
        ),
        payout_tier: PayoutTier.first || PayoutTier.find_by(code: "temp_tier_obs_guard"),
        payout_status: PayoutStatus.first || PayoutStatus.create!(
          code: "temp_payout_status_obs_guard",
          sort_order: 1,
          label_ja: "temp", label_en: "temp", label_fr: "temp", label_zh: "temp", label_ru: "temp", label_es: "temp", label_ar: "temp"
        ),
        observation: observation,
        idempotency_key: "observation-guard-payout"
      )
    end

    it "prevents updating station_id" do
      another_station = Station.create!(
        code: "another_station_obs_guard",
        measurement_type: "seismic",
        label_ja: "別観測点",
        label_en: "Another",
        label_fr: "Another",
        label_zh: "Another",
        label_ru: "Another",
        label_es: "Another",
        label_ar: "Another"
      )
      observation.station = another_station
      expect(observation).not_to be_valid
      expect(observation.errors[:station]).to include("cannot be changed because it is referenced by payouts")
    end

    it "prevents updating event_id" do
      observation.event_id = "another-event-guard-id"
      expect(observation).not_to be_valid
      expect(observation.errors[:event_id]).to include("cannot be changed because it is referenced by payouts")
    end

    it "prevents updating observed_at" do
      observation.observed_at = observation.observed_at + 1.hour
      expect(observation).not_to be_valid
      expect(observation.errors[:observed_at]).to include("cannot be changed because it is referenced by payouts")
    end
  end

  context "when updating measurement values" do
    before { observation.save! }

    it "prevents decreasing seismic intensity level" do
      lower_level = SeismicIntensityLevel.create!(
        code: "4_obs_spec_decrease",
        sort_order: 4,
        label_ja: "4", label_en: "4", label_fr: "4", label_zh: "4", label_ru: "4", label_es: "4", label_ar: "4"
      )
      observation.seismic_intensity_level = lower_level
      expect(observation).not_to be_valid
      expect(observation.errors[:seismic_intensity_level]).to include("cannot decrease from previous value")
    end

    it "allows increasing seismic intensity level" do
      higher_level = SeismicIntensityLevel.create!(
        code: "6_weak_obs_spec_increase",
        sort_order: 6,
        label_ja: "6弱", label_en: "6 weak", label_fr: "6 weak", label_zh: "6 weak", label_ru: "6 weak", label_es: "6 weak", label_ar: "6 weak"
      )
      observation.seismic_intensity_level = higher_level
      expect(observation).to be_valid
    end

    it "prevents decreasing rainfall_mm" do
      observation.station = rainfall_station
      observation.seismic_intensity_level = nil
      observation.rainfall_mm = 50.0
      observation.event_id = nil
      observation.save!

      observation.rainfall_mm = 40.0
      expect(observation).not_to be_valid
      expect(observation.errors[:rainfall_mm]).to include("cannot decrease from previous value")
    end

    it "allows increasing rainfall_mm" do
      observation.station = rainfall_station
      observation.seismic_intensity_level = nil
      observation.rainfall_mm = 50.0
      observation.event_id = nil
      observation.save!

      observation.rainfall_mm = 60.0
      expect(observation).to be_valid
    end

    it "does not raise NoMethodError when updating rainfall_mm to nil" do
      observation.station = rainfall_station
      observation.seismic_intensity_level = nil
      observation.rainfall_mm = 50.0
      observation.event_id = nil
      observation.save!

      observation.rainfall_mm = nil
      expect { observation.valid? }.not_to raise_error
      expect(observation).not_to be_valid
    end
  end
end

RSpec.describe Payout, type: :model do
  let(:station) do
    Station.create!(
      code: "seismic_tokyo_payout_spec",
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
      code: "ten_thousand_payout_spec",
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

  let(:payout_status) do
    PayoutStatus.create!(
      code: "ordered_payout_spec",
      sort_order: 0,
      label_ja: "指図済",
      label_en: "Ordered",
      label_fr: "Ordered",
      label_zh: "Ordered",
      label_ru: "Ordered",
      label_es: "Ordered",
      label_ar: "Ordered"
    )
  end

  let(:policy) do
    Policy.create!(
      user: User.create!(google_sub: "google-sub-payout"),
      plan: Plan.create!(
        code: "seismic_payout_spec",
        trigger_type: "seismic",
        label_ja: "震度連動",
        label_en: "Seismic-linked",
        label_fr: "Lié aux séismes",
        label_zh: "震度連動",
        label_ru: "Сейсмическая привязка",
        label_es: "Vinculado a sismos",
        label_ar: "مرتبط بالزلازل"
      ),
      station: station,
      payout_tier: payout_tier,
      policy_status: PolicyStatus.create!(
        code: "active_payout_spec",
        sort_order: 1,
        label_ja: "有効",
        label_en: "Active",
        label_fr: "Active",
        label_zh: "Active",
        label_ru: "Active",
        label_es: "Active",
        label_ar: "Active"
      ),
      threshold: "5弱"
    )
  end

  let(:observation) do
    Observation.create!(
      station: station,
      seismic_intensity_level: SeismicIntensityLevel.create!(
        code: "5_weak_payout_spec",
        sort_order: 5,
        label_ja: "5弱",
        label_en: "5 weak",
        label_fr: "5 weak",
        label_zh: "5 weak",
        label_ru: "5 weak",
        label_es: "5 weak",
        label_ar: "5 weak"
      ),
      event_id: "event-456",
      observed_at: Time.current + 80.hours
    )
  end

  subject(:payout) do
    described_class.new(
      policy: policy,
      payout_tier: payout_tier,
      payout_status: payout_status,
      observation: observation,
      idempotency_key: "payout-123"
    )
  end

  it { is_expected.to belong_to(:policy) }
  it { is_expected.to belong_to(:payout_tier) }
  it { is_expected.to belong_to(:payout_status) }
  it { is_expected.to belong_to(:observation) }
  it { is_expected.to have_one(:survey_response).dependent(:destroy) }
  it { is_expected.to validate_presence_of(:idempotency_key) }
  it { is_expected.to validate_uniqueness_of(:idempotency_key) }

  it "validates that payout_tier matches policy payout_tier" do
    different_tier = PayoutTier.create!(
      code: "different_tier_payout_spec",
      amount_yen: 30_000,
      label_ja: "3万円相当（模擬）",
      label_en: "Equivalent to JPY 30,000 (simulated)",
      label_fr: "Equivalent to JPY 30,000 (simulated)",
      label_zh: "Equivalent to JPY 30,000 (simulated)",
      label_ru: "Equivalent to JPY 30,000 (simulated)",
      label_es: "Equivalent to JPY 30,000 (simulated)",
      label_ar: "Equivalent to JPY 30,000 (simulated)"
    )
    payout.payout_tier = different_tier
    expect(payout).not_to be_valid
    expect(payout.errors[:payout_tier]).to include("must match policy payout tier")
  end

  it "validates that observation station matches policy station" do
    different_station = Station.create!(
      code: "different_station_payout_spec",
      measurement_type: "seismic",
      label_ja: "大阪震度観測点",
      label_en: "Osaka seismic station",
      label_fr: "Osaka seismic station",
      label_zh: "Osaka seismic station",
      label_ru: "Osaka seismic station",
      label_es: "Osaka seismic station",
      label_ar: "Osaka seismic station"
    )
    different_obs = Observation.create!(
      station: different_station,
      seismic_intensity_level: observation.seismic_intensity_level,
      event_id: "event-789",
      observed_at: Time.current
    )
    payout.observation = different_obs
    expect(payout).not_to be_valid
    expect(payout.errors[:observation]).to include("must match policy station")
  end

  it "validates that observation observed_at is after policy waiting_until" do
    early_obs = Observation.create!(
      station: station,
      seismic_intensity_level: observation.seismic_intensity_level,
      event_id: "early-event-payout-spec",
      observed_at: policy.waiting_until - 1.hour
    )
    payout.observation = early_obs
    expect(payout).not_to be_valid
    expect(payout.errors[:observation]).to include("observed_at must be after policy waiting_until")
  end

  context "when updating attributes" do
    before do
      payout.save!
    end

    it "forbids updating policy_id regardless of survey response existence" do
      another_policy = Policy.create!(
        user: policy.user,
        plan: policy.plan,
        station: station,
        payout_tier: payout_tier,
        policy_status: policy.policy_status,
        threshold: "5弱"
      )
      payout.policy = another_policy
      expect(payout).not_to be_valid
      expect(payout.errors[:policy]).to include("cannot be changed once created")
    end

    it "forbids updating observation_id once created" do
      another_observation = Observation.create!(
        station: station,
        seismic_intensity_level: observation.seismic_intensity_level,
        event_id: "another-payout-obs-update-spec",
        observed_at: Time.current
      )
      payout.observation = another_observation
      expect(payout).not_to be_valid
      expect(payout.errors[:observation]).to include("cannot be changed once created")
    end
  end
end

RSpec.describe Notification, type: :model do
  let(:station) do
    Station.create!(
      code: "seismic_tokyo_notif_spec",
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
      code: "ten_thousand_notif_spec",
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

  let(:policy) do
    Policy.create!(
      user: User.create!(google_sub: "google-sub-notification-policy"),
      plan: Plan.create!(
        code: "seismic_notif_spec",
        trigger_type: "seismic",
        label_ja: "震度連動",
        label_en: "Seismic-linked",
        label_fr: "Lié aux séismes",
        label_zh: "震度連動",
        label_ru: "Сейсмическая привязка",
        label_es: "Vinculado a sismos",
        label_ar: "مرتبط بالズラゼル"
      ),
      station: station,
      payout_tier: payout_tier,
      policy_status: PolicyStatus.create!(
        code: "active_notif_spec",
        sort_order: 1,
        label_ja: "有効",
        label_en: "Active",
        label_fr: "Active",
        label_zh: "Active",
        label_ru: "Active",
        label_es: "Active",
        label_ar: "Active"
      ),
      threshold: "5弱"
    )
  end

  let(:observation) do
    Observation.create!(
      station: station,
      seismic_intensity_level: SeismicIntensityLevel.create!(
        code: "5_weak_notif_spec",
        sort_order: 5,
        label_ja: "5弱",
        label_en: "5 weak",
        label_fr: "5 weak",
        label_zh: "5 weak",
        label_ru: "5 weak",
        label_es: "5 weak",
        label_ar: "5 weak"
      ),
      event_id: "event-notif",
      observed_at: Time.current
    )
  end

  let(:payout) do
    Payout.create!(
      policy: policy,
      payout_tier: payout_tier,
      payout_status: PayoutStatus.create!(
        code: "ordered_notif_spec",
        sort_order: 0,
        label_ja: "指図済",
        label_en: "Ordered",
        label_fr: "Ordered",
        label_zh: "Ordered",
        label_ru: "Ordered",
        label_es: "Ordered",
        label_ar: "Ordered"
      ),
      observation: observation,
      idempotency_key: "payout-notif-123"
    )
  end

  subject(:notification) do
    described_class.new(
      user: User.create!(google_sub: "google-sub-notification"),
      kind: "payout_ready",
      message: "模擬支払の通知です"
    )
  end

  it { is_expected.to belong_to(:user) }
  it { is_expected.to belong_to(:policy).optional }
  it { is_expected.to belong_to(:payout).optional }
  it { is_expected.to validate_presence_of(:kind) }
  it { is_expected.to validate_presence_of(:message) }
end

RSpec.describe SurveyResponse, type: :model do
  let(:station) do
    Station.create!(
      code: "seismic_tokyo_survey_spec",
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
      code: "ten_thousand_survey_spec",
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

  let(:user) { User.create!(google_sub: "google-sub-survey-policy") }

  let(:policy) do
    Policy.create!(
      user: user,
      plan: Plan.create!(
        code: "seismic_survey_spec",
        trigger_type: "seismic",
        label_ja: "震度連動",
        label_en: "Seismic-linked",
        label_fr: "Lié aux séismes",
        label_zh: "震度連動",
        label_ru: "Сейсмическая привязка",
        label_es: "Vinculado a sismos",
        label_ar: "مرتبط بالズラゼル"
      ),
      station: station,
      payout_tier: payout_tier,
      policy_status: PolicyStatus.find_or_create_by!(
        code: "active",
        sort_order: 1,
        label_ja: "有効",
        label_en: "Active",
        label_fr: "Active",
        label_zh: "Active",
        label_ru: "Active",
        label_es: "Active",
        label_ar: "Active"
      ),
      threshold: "5弱"
    )
  end

  let(:observation) do
    Observation.create!(
      station: station,
      seismic_intensity_level: SeismicIntensityLevel.create!(
        code: "5_weak_survey_spec",
        sort_order: 5,
        label_ja: "5弱",
        label_en: "5 weak",
        label_fr: "5 weak",
        label_zh: "5 weak",
        label_ru: "5 weak",
        label_es: "5 weak",
        label_ar: "5 weak"
      ),
      event_id: "event-survey",
      observed_at: Time.current + 80.hours
    )
  end

  let(:payout) do
    Payout.create!(
      policy: policy,
      payout_tier: payout_tier,
      payout_status: PayoutStatus.find_or_create_by!(
        code: "completed_simulated",
        sort_order: 1,
        label_ja: "完了（シミュレーション）",
        label_en: "Completed (simulated)",
        label_fr: "Completed (simulated)",
        label_zh: "Completed (simulated)",
        label_ru: "Completed (simulated)",
        label_es: "Completed (simulated)",
        label_ar: "Completed (simulated)"
      ),
      observation: observation,
      idempotency_key: "payout-survey-123"
    )
  end

  subject(:survey_response) do
    described_class.new(
      user: user,
      payout: payout,
      response_data: { "q1" => "yes" }
    )
  end

  it { is_expected.to belong_to(:user) }
  it { is_expected.to belong_to(:payout) }
  it { is_expected.to validate_presence_of(:response_data) }
  it { is_expected.to validate_uniqueness_of(:payout_id) }

  it "requires the survey response user to match the payout policy owner" do
    another_user = User.create!(google_sub: "another-user-survey")
    survey_response.user = another_user
    expect(survey_response).not_to be_valid
    expect(survey_response.errors[:user]).to include("must be the owner of the policy payout")
  end

  it "successfully destroys policy, payouts, and associated survey responses without database foreign key errors" do
    survey_response.save!
    expect { policy.destroy! }.not_to raise_error
    expect(Payout.exists?(payout.id)).to be_falsey
    expect(SurveyResponse.exists?(survey_response.id)).to be_falsey
  end

  context "with LegacySurveyResponse" do
    it "does not prevent user deletion and cascades deletes" do
      ActiveRecord::Base.connection.execute(
        "INSERT INTO legacy_survey_responses (user_id, response_data, isolation_reason, created_at, updated_at) " \
        "VALUES (#{user.id}, '{}', 'test_reason', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)"
      )
      expect { user.destroy! }.not_to raise_error
      count = ActiveRecord::Base.connection.select_value("SELECT COUNT(*) FROM legacy_survey_responses WHERE user_id = #{user.id}")
      expect(count).to eq(0)
    end
  end
end

RSpec.describe "Schema contract", type: :model do
  it "does not store personal information columns on users" do
    forbidden_columns = %w[email name first_name last_name given_name family_name avatar_url phone_number]

    expect(User.column_names).to include("google_sub")
    expect(User.column_names & forbidden_columns).to be_empty
  end

  it "references status and intensity masters by foreign keys" do
    expect(Policy.column_names).to include("policy_status_id", "plan_id", "payout_tier_id", "station_id", "threshold", "waiting_until", "expires_at", "terminated_at")
    expect(Payout.column_names).to include("payout_status_id", "idempotency_key", "payout_tier_id", "observation_id")
    expect(Observation.column_names).to include("seismic_intensity_level_id", "station_id", "event_id")

    expect(Policy.column_names).not_to include("status")
    expect(Payout.column_names).not_to include("status")
    expect(Observation.column_names).not_to include("policy_id")
  end

  it "creates all 26 master records from seeds" do
    seed_path = Rails.root.join("db/seeds.rb")

    expect do
      2.times { load seed_path }
    end.to change {
      [ Plan, SeismicIntensityLevel, Station, PayoutTier, PolicyStatus, PayoutStatus ].sum(&:count)
    }.from(0).to(26)
  end

  it "renames legacy_survey_responses.migration_error_reason to isolation_reason and cascades on user deletion" do
    connection = ActiveRecord::Base.connection

    column_names = connection.columns(:legacy_survey_responses).map(&:name)
    expect(column_names).to include("isolation_reason")
    expect(column_names).not_to include("migration_error_reason")

    user_fk = connection.foreign_keys(:legacy_survey_responses).find { |fk| fk.to_table == "users" }
    expect(user_fk).not_to be_nil
    expect(user_fk.on_delete).to eq(:cascade)
  end
end
