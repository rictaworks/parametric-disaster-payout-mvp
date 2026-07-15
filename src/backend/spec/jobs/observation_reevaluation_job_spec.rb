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

  it "delegates to EvaluateTrigger and does not create a payout when no policy matches" do
    expect { described_class.new.perform(observation.id) }.not_to raise_error
    expect(Payout.count).to eq(0)
  end

  it "does not raise when the observation no longer exists" do
    expect { described_class.new.perform(-1) }.not_to raise_error
  end

  describe "automatic retry on transient database errors" do
    include ActiveJob::TestHelper

    around do |example|
      original_adapter = ActiveJob::Base.queue_adapter
      ActiveJob::Base.queue_adapter = :test
      example.run
      ActiveJob::Base.queue_adapter = original_adapter
    end

    ApplicationJob::RETRYABLE_DATABASE_ERRORS.each do |error_class|
      it "retries instead of failing permanently when EvaluateTrigger raises #{error_class}" do
        call_count = 0
        allow(EvaluateTrigger).to receive(:call) do
          call_count += 1
          raise error_class if call_count == 1

          EvaluateTrigger::Result.new(payouts: [], status: :success)
        end

        perform_enqueued_jobs do
          expect {
            described_class.perform_later(observation.id)
          }.not_to raise_error
        end

        expect(call_count).to eq(2)
      end
    end

    it "does not retry (and re-raises) for a non-retryable error" do
      allow(EvaluateTrigger).to receive(:call).and_raise(StandardError, "unexpected failure")

      expect {
        described_class.new(observation.id).perform_now
      }.to raise_error(StandardError, "unexpected failure")
    end
  end
end
