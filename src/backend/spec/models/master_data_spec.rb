require 'rails_helper'

RSpec.shared_examples "a localized master record" do
  it { is_expected.to validate_presence_of(:code) }
  it { is_expected.to validate_uniqueness_of(:code) }
  it { is_expected.to validate_presence_of(:label_ja) }
  it { is_expected.to validate_presence_of(:label_en) }
  it { is_expected.to validate_presence_of(:label_fr) }
  it { is_expected.to validate_presence_of(:label_zh) }
  it { is_expected.to validate_presence_of(:label_ru) }
  it { is_expected.to validate_presence_of(:label_es) }
  it { is_expected.to validate_presence_of(:label_ar) }
end

RSpec.describe Plan, type: :model do
  subject(:plan) do
    described_class.new(
      code: "seismic",
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

  it_behaves_like "a localized master record"
  it { is_expected.to validate_inclusion_of(:trigger_type).in_array(%w[seismic rainfall]) }
end

RSpec.describe SeismicIntensityLevel, type: :model do
  subject(:level) do
    described_class.new(
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

  it_behaves_like "a localized master record"
  it { is_expected.to validate_presence_of(:sort_order) }
end

RSpec.describe Station, type: :model do
  subject(:station) do
    described_class.new(
      code: "seismic_tokyo",
      measurement_type: "seismic",
      label_ja: "東京震度観測点",
      label_en: "Tokyo seismic station",
      label_fr: "Station sismique de Tokyo",
      label_zh: "東京震度觀測站",
      label_ru: "Сейсмостанция Токио",
      label_es: "Estación sísmica de Tokio",
      label_ar: "محطة طوكيو الزلزالية"
    )
  end

  it_behaves_like "a localized master record"
  it { is_expected.to validate_inclusion_of(:measurement_type).in_array(%w[seismic rainfall]) }

  describe "validations" do
    it "requires jma_code to be unique (allow blank)" do
      described_class.create!(
        code: "station_1",
        measurement_type: "seismic",
        jma_code: "123456",
        label_ja: "観測点1",
        label_en: "Station 1",
        label_fr: "Station 1",
        label_zh: "Station 1",
        label_ru: "Station 1",
        label_es: "Station 1",
        label_ar: "Station 1"
      )

      duplicate = described_class.new(
        code: "station_2",
        measurement_type: "seismic",
        jma_code: "123456",
        label_ja: "観測点2",
        label_en: "Station 2",
        label_fr: "Station 2",
        label_zh: "Station 2",
        label_ru: "Station 2",
        label_es: "Station 2",
        label_ar: "Station 2"
      )
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:jma_code]).to include("has already been taken")

      # blank/nil are allowed to be duplicated
      described_class.create!(
        code: "station_3",
        measurement_type: "seismic",
        jma_code: nil,
        label_ja: "観測点3",
        label_en: "Station 3",
        label_fr: "Station 3",
        label_zh: "Station 3",
        label_ru: "Station 3",
        label_es: "Station 3",
        label_ar: "Station 3"
      )
      another_nil = described_class.new(
        code: "station_4",
        measurement_type: "seismic",
        jma_code: nil,
        label_ja: "観測点4",
        label_en: "Station 4",
        label_fr: "Station 4",
        label_zh: "Station 4",
        label_ru: "Station 4",
        label_es: "Station 4",
        label_ar: "Station 4"
      )
      expect(another_nil).to be_valid

      # empty string "" is normalized to nil, and multiple empty strings can be saved without RecordNotUnique
      empty_station_1 = described_class.create!(
        code: "station_5",
        measurement_type: "seismic",
        jma_code: "",
        label_ja: "観測点5",
        label_en: "Station 5",
        label_fr: "Station 5",
        label_zh: "Station 5",
        label_ru: "Station 5",
        label_es: "Station 5",
        label_ar: "Station 5"
      )
      expect(empty_station_1.reload.jma_code).to be_nil

      empty_station_2 = described_class.new(
        code: "station_6",
        measurement_type: "seismic",
        jma_code: "",
        label_ja: "観測点6",
        label_en: "Station 6",
        label_fr: "Station 6",
        label_zh: "Station 6",
        label_ru: "Station 6",
        label_es: "Station 6",
        label_ar: "Station 6"
      )
      expect(empty_station_2).to be_valid
      expect { empty_station_2.save! }.not_to raise_error
      expect(empty_station_2.reload.jma_code).to be_nil
    end
  end
end

RSpec.describe PayoutTier, type: :model do
  subject(:tier) do
    described_class.new(
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

  it_behaves_like "a localized master record"
  it { is_expected.to validate_numericality_of(:amount_yen).only_integer.is_greater_than(0) }
end

RSpec.describe PolicyStatus, type: :model do
  subject(:status) do
    described_class.new(
      code: "pending",
      sort_order: 0,
      label_ja: "待機中",
      label_en: "Pending",
      label_fr: "En attente",
      label_zh: "待機中",
      label_ru: "Ожидание",
      label_es: "Pendiente",
      label_ar: "قيد الانتظار"
    )
  end

  it_behaves_like "a localized master record"
  it { is_expected.to validate_presence_of(:sort_order) }
end

RSpec.describe PayoutStatus, type: :model do
  subject(:status) do
    described_class.new(
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

  it_behaves_like "a localized master record"
  it { is_expected.to validate_presence_of(:sort_order) }
end
