require "rails_helper"

RSpec.describe "model validation i18n" do
  MODEL_FILES = %w[
    app/models/observation.rb
    app/models/payout.rb
    app/models/policy.rb
    app/models/survey_response.rb
  ].freeze

  def read_model(path)
    File.read(Rails.root.join(path))
  end

  it "does not hardcode validation messages in model files" do
    hardcoded_lines = MODEL_FILES.flat_map do |path|
      read_model(path).lines.select { |line| line.match?(/errors\.add\([^,]+,\s*["']/) }
    end

    expect(hardcoded_lines).to be_empty
  end

  it "translates policy validation messages when the locale changes" do
    policy = Policy.new(
      user: User.create!(google_sub: "google-sub-i18n-policy"),
      plan: Plan.create!(
        code: "i18n_policy_plan",
        trigger_type: "seismic",
        label_ja: "震度連動",
        label_en: "Seismic-linked",
        label_fr: "Lié aux séismes",
        label_zh: "震度連動",
        label_ru: "Сейсмическая привязка",
        label_es: "Vinculado a sismos",
        label_ar: "مرتبط بالزلازل"
      ),
      station: Station.create!(
        code: "i18n_policy_station",
        measurement_type: "rainfall",
        label_ja: "雨量",
        label_en: "Rainfall",
        label_fr: "Rainfall",
        label_zh: "Rainfall",
        label_ru: "Rainfall",
        label_es: "Rainfall",
        label_ar: "Rainfall"
      ),
      payout_tier: PayoutTier.create!(
        code: "i18n_policy_tier",
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
        code: "i18n_policy_status",
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

    I18n.with_locale(:en) do
      policy.valid?
      expect(policy.errors[:station]).to include("measurement type must match plan trigger type")
    end

    I18n.with_locale(:ja) do
      policy.errors.clear
      policy.valid?
      expect(policy.errors[:station]).to include("観測種別は保険プランのトリガー種別と一致する必要があります")
    end
  end

  it "translates blank validation messages when the locale changes" do
    observation = Observation.new(
      station: Station.create!(
        code: "i18n_observation_station",
        measurement_type: "seismic",
        label_ja: "観測点",
        label_en: "Station",
        label_fr: "Station",
        label_zh: "Station",
        label_ru: "Station",
        label_es: "Station",
        label_ar: "Station"
      ),
      seismic_intensity_level: SeismicIntensityLevel.create!(
        code: "i18n_observation_level",
        sort_order: 5,
        label_ja: "5弱",
        label_en: "5 weak",
        label_fr: "5 weak",
        label_zh: "5 weak",
        label_ru: "5 weak",
        label_es: "5 weak",
        label_ar: "5 weak"
      ),
      event_id: nil,
      observed_at: Time.current
    )

    I18n.with_locale(:en) do
      observation.valid?
      expect(observation.errors[:event_id]).to include("can't be blank")
    end

    I18n.with_locale(:ja) do
      observation.errors.clear
      observation.valid?
      expect(observation.errors[:event_id]).to include("を入力してください")
    end
  end
end
