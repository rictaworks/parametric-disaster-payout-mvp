require "rails_helper"

RSpec.describe JmaPoller do
  describe ".parse" do
    it "extracts seismic observation data from the sample XML fixture" do
      xml = File.read(Rails.root.join("spec/fixtures/jma/seismic.xml"))

      expect(described_class.parse(xml)).to eq(
        [
          {
            station_code: "seismic_tokyo",
            occurred_at: "2026-07-15T09:00:00+09:00",
            event_id: "eq-20260715-090000",
            seismic_intensity_level_label_ja: "5弱",
            simulated: false
          }
        ]
      )
    end

    it "extracts rainfall observation data from the sample XML fixture" do
      xml = File.read(Rails.root.join("spec/fixtures/jma/rainfall.xml"))

      expect(described_class.parse(xml)).to eq(
        [
          {
            station_code: "rainfall_tokyo",
            occurred_at: "2026-07-15T10:00:00+09:00",
            rainfall_mm: "12.5",
            simulated: false
          }
        ]
      )
    end
  end

  describe "#call" do
    it "invokes IngestObservationEvent with parsed payloads" do
      xml = File.read(Rails.root.join("spec/fixtures/jma/seismic.xml"))
      ingest_service = instance_double(IngestObservationEvent)

      expect(IngestObservationEvent).to receive(:new).with(
        payload: {
          station_code: "seismic_tokyo",
          occurred_at: "2026-07-15T09:00:00+09:00",
          event_id: "eq-20260715-090000",
          seismic_intensity_level_label_ja: "5弱",
          simulated: false
        }
      ).and_return(ingest_service)

      expect(ingest_service).to receive(:call)

      described_class.new(xml: xml).call
    end
  end
end
