require "rails_helper"
require_relative "../../../db/migrate/20260713213247_update_stage1_domain_models_for_review_comments"

RSpec.describe UpdateStage1DomainModelsForReviewComments, type: :migration do
  subject(:migration) { described_class.new }

  let(:rainfall_policy) { Struct.new(:id, :threshold).new(101, "12.5") }
  let(:invalid_rainfall_policy) { Struct.new(:id, :threshold).new(102, "5弱") }
  let(:seismic_policy) { Struct.new(:id, :threshold).new(201, "5弱") }
  let(:invalid_seismic_policy) { Struct.new(:id, :threshold).new(202, "not-a-seismic-level") }

  describe "#resolve_rainfall_threshold_mm!" do
    it "resolves the rainfall threshold from policy.threshold" do
      expect(migration.send(:resolve_rainfall_threshold_mm!, rainfall_policy)).to eq(BigDecimal("12.5"))
    end

    it "raises when rainfall threshold cannot be parsed" do
      expect { migration.send(:resolve_rainfall_threshold_mm!, invalid_rainfall_policy) }
        .to raise_error(
          RuntimeError,
          "Migration blocked: Cannot resolve rainfall threshold for Policy 102 threshold '5弱'. Isolate this payout manually before retrying."
        )
    end
  end

  describe "#resolve_seismic_threshold_level!" do
    let!(:threshold_level) do
      SeismicIntensityLevel.create!(
        code: "5_weak_migration_spec",
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

    it "resolves the seismic threshold level from policy.threshold" do
      resolved = migration.send(:resolve_seismic_threshold_level!, seismic_policy)
      expect(resolved.id).to eq(threshold_level.id)
      expect(resolved.label_ja).to eq("5弱")
    end

    it "raises when seismic threshold cannot be resolved" do
      expect { migration.send(:resolve_seismic_threshold_level!, invalid_seismic_policy) }
        .to raise_error(
          RuntimeError,
          "Migration blocked: Cannot resolve SeismicIntensityLevel for Policy 202 threshold 'not-a-seismic-level'. Isolate this payout manually before retrying."
        )
    end
  end
end
