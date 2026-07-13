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
  subject(:policy) do
    described_class.new(
      user: User.create!(google_sub: "google-sub-policy"),
      plan: Plan.create!(
        code: "seismic",
        trigger_type: "seismic",
        label_ja: "震度連動",
        label_en: "Seismic-linked",
        label_fr: "Lié aux séismes",
        label_zh: "震度連動",
        label_ru: "Сейсмическая привязка",
        label_es: "Vinculado a sismos",
        label_ar: "مرتبط بالزلازل"
      ),
      payout_tier: PayoutTier.create!(
        code: "ten_thousand",
        amount_yen: 10_000,
        label_ja: "1万円相当（模擬）",
        label_en: "Equivalent to JPY 10,000 (simulated)",
        label_fr: "Équivalent à 10 000 JPY (simulé)",
        label_zh: "相當於 10,000 日圓（模擬）",
        label_ru: "Эквивалент 10 000 иен (имитация)",
        label_es: "Equivalente a 10.000 JPY (simulado)",
        label_ar: "ما يعادل 10000 ين (محاكاة)"
      ),
      policy_status: PolicyStatus.create!(
        code: "active",
        sort_order: 1,
        label_ja: "有効",
        label_en: "Active",
        label_fr: "Actif",
        label_zh: "有效",
        label_ru: "Активен",
        label_es: "Activo",
        label_ar: "نشط"
      ),
      threshold: "5弱"
    )
  end

  it { is_expected.to belong_to(:user) }
  it { is_expected.to belong_to(:plan) }
  it { is_expected.to belong_to(:payout_tier) }
  it { is_expected.to belong_to(:policy_status) }
  it { is_expected.to have_many(:observations).dependent(:destroy) }
  it { is_expected.to have_many(:payouts).dependent(:destroy) }
  it { is_expected.to have_many(:notifications).dependent(:destroy) }
  it { is_expected.to have_many(:survey_responses).dependent(:destroy) }
  it { is_expected.to validate_presence_of(:threshold) }

  it "sets expires_at to one year after creation when omitted" do
    policy.expires_at = nil
    policy.valid?
    expect(policy.expires_at).to be_present
    expect(policy.expires_at).to be_within(5.seconds).of(Time.current + 1.year)
  end
end

RSpec.describe Observation, type: :model do
  let(:policy) do
    Policy.create!(
      user: User.create!(google_sub: "google-sub-observation"),
      plan: Plan.create!(
        code: "seismic",
        trigger_type: "seismic",
        label_ja: "震度連動",
        label_en: "Seismic-linked",
        label_fr: "Lié aux séismes",
        label_zh: "震度連動",
        label_ru: "Сейсмическая привязка",
        label_es: "Vinculado a sismos",
        label_ar: "مرتبط بالزلازل"
      ),
      payout_tier: PayoutTier.create!(
        code: "ten_thousand",
        amount_yen: 10_000,
        label_ja: "1万円相当（模擬）",
        label_en: "Equivalent to JPY 10,000 (simulated)",
        label_fr: "Équivalent à 10 000 JPY (simulé)",
        label_zh: "相當於 10,000 日圓（模擬）",
        label_ru: "Эквивалент 10 000 иен (имитация)",
        label_es: "Equivalente a 10.000 JPY (simulado)",
        label_ar: "ما يعادل 10000 ين (محاكاة)"
      ),
      policy_status: PolicyStatus.create!(
        code: "active",
        sort_order: 1,
        label_ja: "有効",
        label_en: "Active",
        label_fr: "Actif",
        label_zh: "有效",
        label_ru: "Активен",
        label_es: "Activo",
        label_ar: "نشط"
      ),
      threshold: "5弱"
    )
  end

  subject(:observation) do
    described_class.new(
      policy: policy,
      station: Station.create!(
        code: "seismic_tokyo",
        measurement_type: "seismic",
        label_ja: "東京震度観測点",
        label_en: "Tokyo seismic station",
        label_fr: "Station sismique de Tokyo",
        label_zh: "東京震度觀測站",
        label_ru: "Сейсмостанция Токио",
        label_es: "Estación sísmica de Tokio",
        label_ar: "محطة طوكيو الزلزالية"
      ),
      seismic_intensity_level: SeismicIntensityLevel.create!(
        code: "5_weak",
        sort_order: 5,
        label_ja: "5弱",
        label_en: "5 weak",
        label_fr: "5 weak",
        label_zh: "5 weak",
        label_ru: "5 weak",
        label_es: "5 weak",
        label_ar: "5 weak"
      ),
      observed_at: Time.current
    )
  end

  it { is_expected.to belong_to(:policy) }
  it { is_expected.to belong_to(:station) }
  it { is_expected.to validate_presence_of(:observed_at) }

  it "requires seismic intensity for seismic stations" do
    observation.seismic_intensity_level = nil
    observation.valid?

    expect(observation.errors[:seismic_intensity_level]).to include("can't be blank")
  end

  it "requires rainfall values for rainfall stations" do
    observation.station = Station.create!(
      code: "rainfall_tokyo",
      measurement_type: "rainfall",
      label_ja: "東京雨量観測点",
      label_en: "Tokyo rainfall station",
      label_fr: "Station pluviométrique de Tokyo",
      label_zh: "東京雨量觀測站",
      label_ru: "Дождемерная станция Токио",
      label_es: "Estación pluvial de Tokio",
      label_ar: "محطة طوكيو للأمطار"
    )
    observation.seismic_intensity_level = nil
    observation.rainfall_mm = nil

    observation.valid?
    expect(observation.errors[:rainfall_mm]).to include("can't be blank")
  end
end

RSpec.describe Payout, type: :model do
  let(:payout_tier) do
    PayoutTier.create!(
      code: "ten_thousand",
      amount_yen: 10_000,
      label_ja: "1万円相当（模擬）",
      label_en: "Equivalent to JPY 10,000 (simulated)",
      label_fr: "Équivalent à 10 000 JPY (simulé)",
      label_zh: "相當於 10,000 日圓（模擬）",
      label_ru: "Эквивалент 10 000 иен (имитация)",
      label_es: "Equivalente a 10.000 JPY (simulado)",
      label_ar: "ما يعادل 10000 ين (محاكاة)"
    )
  end

  let(:payout_status) do
    PayoutStatus.create!(
      code: "ordered",
      sort_order: 0,
      label_ja: "指図済",
      label_en: "Ordered",
      label_fr: "Ordonné",
      label_zh: "已指示",
      label_ru: "Назначено",
      label_es: "Ordenado",
      label_ar: "تم الأمر"
    )
  end

  let(:policy) do
    Policy.create!(
      user: User.create!(google_sub: "google-sub-payout"),
      plan: Plan.create!(
        code: "seismic",
        trigger_type: "seismic",
        label_ja: "震度連動",
        label_en: "Seismic-linked",
        label_fr: "Lié aux séismes",
        label_zh: "震度連動",
        label_ru: "Сейсмическая привязка",
        label_es: "Vinculado a sismos",
        label_ar: "مرتبط بالزلازل"
      ),
      payout_tier: payout_tier,
      policy_status: PolicyStatus.create!(
        code: "active",
        sort_order: 1,
        label_ja: "有効",
        label_en: "Active",
        label_fr: "Actif",
        label_zh: "有效",
        label_ru: "Активен",
        label_es: "Activo",
        label_ar: "نشط"
      ),
      threshold: "5弱"
    )
  end

  subject(:payout) do
    described_class.new(
      policy: policy,
      payout_tier: payout_tier,
      payout_status: payout_status,
      idempotency_key: "payout-123"
    )
  end

  it { is_expected.to belong_to(:policy) }
  it { is_expected.to belong_to(:payout_tier) }
  it { is_expected.to belong_to(:payout_status) }
  it { is_expected.to validate_presence_of(:idempotency_key) }
  it { is_expected.to validate_uniqueness_of(:idempotency_key) }
end

RSpec.describe Notification, type: :model do
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
  subject(:survey_response) do
    described_class.new(
      user: User.create!(google_sub: "google-sub-survey"),
      response_data: { "q1" => "yes" }
    )
  end

  it { is_expected.to belong_to(:user) }
  it { is_expected.to belong_to(:policy).optional }
  it { is_expected.to validate_presence_of(:response_data) }
end

RSpec.describe "Schema contract", type: :model do
  it "does not store personal information columns on users" do
    forbidden_columns = %w[email name first_name last_name given_name family_name avatar_url phone_number]

    expect(User.column_names).to include("google_sub")
    expect(User.column_names & forbidden_columns).to be_empty
  end

  it "references status and intensity masters by foreign keys" do
    expect(Policy.column_names).to include("policy_status_id", "plan_id", "payout_tier_id", "threshold", "expires_at")
    expect(Payout.column_names).to include("payout_status_id", "idempotency_key", "payout_tier_id")
    expect(Observation.column_names).to include("seismic_intensity_level_id", "station_id", "policy_id")

    expect(Policy.column_names).not_to include("status")
    expect(Payout.column_names).not_to include("status")
    expect(Observation.column_names).not_to include("intensity")
  end

  it "creates all 26 master records from seeds" do
    seed_path = Rails.root.join("db/seeds.rb")

    expect do
      2.times { load seed_path }
    end.to change {
      [Plan, SeismicIntensityLevel, Station, PayoutTier, PolicyStatus, PayoutStatus].sum(&:count)
    }.from(0).to(26)
  end
end
