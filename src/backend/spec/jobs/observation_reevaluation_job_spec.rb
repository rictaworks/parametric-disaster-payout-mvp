require "rails_helper"

RSpec.describe ObservationReevaluationJob do
  let!(:station) do
    Station.create!(
      code: "seismic_tokyo_reevaluation_job_spec",
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

  let!(:seismic_level) do
    SeismicIntensityLevel.create!(
      code: "5_weak_reevaluation_job_spec",
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

  let!(:observation) do
    Observation.create!(
      station: station,
      event_id: "event-001",
      observed_at: Time.zone.parse("2026-07-15 09:00:00"),
      seismic_intensity_level: seismic_level,
      max_value: 5,
      simulated: false
    )
  end

  # NOTE: This job is a Stage 6 placeholder queue entry point only (see the class comment).
  # It intentionally performs no trigger evaluation or payout creation yet; that lands in
  # Stage 7 (Issue #8). This spec only pins today's documented no-op contract so a future
  # change to real evaluation logic here is an intentional, visible diff rather than a
  # silent behavior change.
  it "does not raise and does not create any payouts" do
    expect { described_class.new.perform(observation.id) }.not_to raise_error
    expect(Payout.count).to eq(0)
  end

  it "does not raise when the observation no longer exists" do
    expect { described_class.new.perform(-1) }.not_to raise_error
  end
end
