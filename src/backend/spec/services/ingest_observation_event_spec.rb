require "rails_helper"

RSpec.describe IngestObservationEvent do
  include ActiveSupport::Testing::TimeHelpers

  let!(:seismic_station) do
    Station.create!(
      code: "seismic_tokyo_ingest_spec",
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

  let!(:rainfall_station) do
    Station.create!(
      code: "rainfall_tokyo_ingest_spec",
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

  let!(:seismic_level_4) do
    SeismicIntensityLevel.create!(
      code: "4_ingest_spec",
      sort_order: 4,
      label_ja: "4",
      label_en: "4",
      label_fr: "4",
      label_zh: "4",
      label_ru: "4",
      label_es: "4",
      label_ar: "4"
    )
  end

  let!(:seismic_level_5_weak) do
    SeismicIntensityLevel.create!(
      code: "5_weak_ingest_spec",
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

  let(:queue_job) { class_spy(ObservationReevaluationJob) }

  subject(:service) do
    described_class.new(payload: payload, queue_job: queue_job)
  end

  describe "#call" do
    context "when ingesting a new seismic event" do
      let(:payload) do
        {
          station_id: seismic_station.id,
          event_id: "event-001",
          occurred_at: Time.zone.parse("2026-07-15 09:00:00"),
          seismic_intensity_level_id: seismic_level_4.id,
          simulated: false
        }
      end

      it "creates a summary observation, records history, and queues re-evaluation" do
        result = service.call

        expect(result).to be_success
        expect(result.status).to eq(:created)
        expect(result.observation).to be_persisted
        expect(result.observation.max_value).to eq(BigDecimal("4"))
        expect(result.observation.observed_at).to eq(payload[:occurred_at])
        expect(result.history_event).to be_persisted
        expect(result.history_event.payload).to include("event_id" => "event-001")
        expect(queue_job).to have_received(:perform_later).with(result.observation.id)
      end
    end

    context "when a follow-up seismic event exceeds the current maximum" do
      let!(:existing_observation) do
        Observation.create!(
          station: seismic_station,
          event_id: "event-001",
          observed_at: Time.zone.parse("2026-07-15 09:00:00"),
          seismic_intensity_level: seismic_level_4,
          max_value: 4,
          simulated: false
        )
      end

      let(:payload) do
        {
          station_id: seismic_station.id,
          event_id: "event-001",
          occurred_at: Time.zone.parse("2026-07-15 09:00:00"),
          seismic_intensity_level_id: seismic_level_5_weak.id,
          simulated: false
        }
      end

      it "updates the maximum and queues re-evaluation" do
        result = service.call

        expect(result).to be_success
        expect(result.status).to eq(:updated)
        expect(existing_observation.reload.max_value).to eq(BigDecimal("5"))
        expect(existing_observation.seismic_intensity_level).to eq(seismic_level_5_weak)
        expect(result.history_event).to be_persisted
        expect(queue_job).to have_received(:perform_later).with(existing_observation.id)
      end
    end

    context "when a follow-up seismic event is below the current maximum" do
      let!(:existing_observation) do
        Observation.create!(
          station: seismic_station,
          event_id: "event-001",
          observed_at: Time.zone.parse("2026-07-15 09:00:00"),
          seismic_intensity_level: seismic_level_5_weak,
          max_value: 5,
          simulated: false
        )
      end

      let(:payload) do
        {
          station_id: seismic_station.id,
          event_id: "event-001",
          occurred_at: Time.zone.parse("2026-07-15 09:00:00"),
          seismic_intensity_level_id: seismic_level_4.id,
          simulated: false
        }
      end

      it "records history without changing the maximum or queueing" do
        result = service.call

        expect(result).to be_success
        expect(result.status).to eq(:recorded)
        expect(existing_observation.reload.max_value).to eq(BigDecimal("5"))
        expect(existing_observation.seismic_intensity_level).to eq(seismic_level_5_weak)
        expect(result.history_event).to be_persisted
        expect(queue_job).not_to have_received(:perform_later)
      end
    end

    context "when ingesting a rainfall event" do
      let(:payload) do
        {
          station_id: rainfall_station.id,
          occurred_at: Time.zone.parse("2026-07-15 10:00:00"),
          rainfall_mm: "12.50",
          simulated: true
        }
      end

      it "preserves occurred_at and stores the rainfall maximum" do
        result = service.call

        expect(result).to be_success
        expect(result.observation.observed_at).to eq(payload[:occurred_at])
        expect(result.observation.max_value).to eq(BigDecimal("12.50"))
      end
    end

    context "when the existing observation predates the max_value backfill (NULL column)" do
      let!(:existing_observation) do
        Observation.create!(
          station: seismic_station,
          event_id: "event-001",
          observed_at: Time.zone.parse("2026-07-15 09:00:00"),
          seismic_intensity_level: seismic_level_4,
          max_value: 4,
          simulated: false
        ).tap do |observation|
          # Simulate a pre-migration row: the max_value column exists but was never
          # backfilled, so it is NULL even though the row has real measurement data.
          Observation.where(id: observation.id).update_all(max_value: nil)
        end
      end

      let(:payload) do
        {
          station_id: seismic_station.id,
          event_id: "event-001",
          occurred_at: Time.zone.parse("2026-07-15 09:00:00"),
          seismic_intensity_level_id: seismic_level_5_weak.id,
          simulated: false
        }
      end

      it "still updates the maximum and queues re-evaluation instead of silently skipping it" do
        result = service.call

        expect(result).to be_success
        expect(result.status).to eq(:updated)
        expect(existing_observation.reload.max_value).to eq(BigDecimal("5"))
        expect(queue_job).to have_received(:perform_later).with(existing_observation.id)
      end
    end

    context "when a concurrent process commits a higher maximum before this attempt applies its update" do
      let!(:existing_observation) do
        Observation.create!(
          station: seismic_station,
          event_id: "event-001",
          observed_at: Time.zone.parse("2026-07-15 09:00:00"),
          seismic_intensity_level: seismic_level_4,
          max_value: 4,
          simulated: false
        )
      end

      let(:payload) do
        {
          station_id: seismic_station.id,
          event_id: "event-001",
          occurred_at: Time.zone.parse("2026-07-15 09:00:00"),
          seismic_intensity_level_id: seismic_level_5_weak.id,
          simulated: false
        }
      end

      before do
        allow(Observation).to receive(:find_by).and_wrap_original do |method, *args|
          record = method.call(*args)
          if record&.id == existing_observation.id
            Observation.where(id: existing_observation.id).update_all(max_value: 6)
          end
          record
        end
      end

      it "does not overwrite the concurrently committed higher maximum and does not re-queue" do
        result = service.call

        expect(result).to be_success
        expect(result.status).to eq(:recorded)
        expect(existing_observation.reload.max_value).to eq(BigDecimal("6"))
        expect(queue_job).not_to have_received(:perform_later)
      end
    end

    context "when two ingests race to create the same new observation" do
      let!(:existing_observation) do
        Observation.create!(
          station: seismic_station,
          event_id: "event-002",
          observed_at: Time.zone.parse("2026-07-15 09:30:00"),
          seismic_intensity_level: seismic_level_4,
          max_value: 4,
          simulated: false
        )
      end

      let(:payload) do
        {
          station_id: seismic_station.id,
          event_id: "event-002",
          occurred_at: Time.zone.parse("2026-07-15 09:30:00"),
          seismic_intensity_level_id: seismic_level_5_weak.id,
          simulated: false
        }
      end

      before do
        # Simulate this attempt's existence check racing ahead of a concurrent insert: the
        # first lookup misses the row that (in reality) another process is about to commit,
        # so this attempt tries to create it too and collides with the real unique index.
        call_count = 0
        allow(Observation).to receive(:find_by).and_wrap_original do |method, *args|
          call_count += 1
          call_count == 1 ? nil : method.call(*args)
        end
      end

      it "retries after losing the create race and applies its update against the winning row" do
        result = nil
        expect { result = service.call }.not_to raise_error

        expect(result).to be_success
        expect(result.status).to eq(:updated)
        expect(existing_observation.reload.max_value).to eq(BigDecimal("5"))
        expect(Observation.where(station: seismic_station, event_id: "event-002").count).to eq(1)
      end
    end

    context "when station_code is a numerical JMA code that clashes with another station's ID" do
      let!(:station_a) do
        Station.create!(
          id: 44132,
          code: "station_a_ingest_spec",
          measurement_type: "rainfall",
          label_ja: "観測点A (ID: 44132)",
          label_en: "Station A",
          label_fr: "Station A",
          label_zh: "Station A",
          label_ru: "Station A",
          label_es: "Station A",
          label_ar: "Station A"
        )
      end
      let!(:station_b) do
        Station.create!(
          code: "station_b_ingest_spec",
          jma_code: "44132",
          measurement_type: "rainfall",
          label_ja: "観測点B (JMA: 44132)",
          label_en: "Station B",
          label_fr: "Station B",
          label_zh: "Station B",
          label_ru: "Station B",
          label_es: "Station B",
          label_ar: "Station B"
        )
      end

      let(:payload) do
        {
          station_code: "44132",
          occurred_at: Time.zone.parse("2026-07-15 10:00:00"),
          rainfall_mm: "12.50",
          simulated: true
        }
      end

      it "resolves the station by jma_code instead of the conflicting station ID" do
        result = service.call

        expect(result).to be_success
        expect(result.observation.station).to eq(station_b)
        expect(result.observation.station).not_to eq(station_a)
      end
    end

    context "when the station is unknown" do
      let(:payload) do
        {
          station_id: 999_999,
          occurred_at: Time.zone.parse("2026-07-15 10:00:00"),
          rainfall_mm: "12.50"
        }
      end

      it "ignores the payload" do
        expect { service.call }.not_to change(Observation, :count)
        expect { service.call }.not_to change(ObservationEvent, :count)
      end
    end
  end
end
