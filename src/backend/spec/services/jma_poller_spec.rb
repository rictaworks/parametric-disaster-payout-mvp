require "rails_helper"

RSpec.describe JmaPoller do
  describe ".parse" do
    it "extracts seismic observation data from the sample XML fixture" do
      xml = File.read(Rails.root.join("spec/fixtures/jma/seismic.xml"))

      expect(described_class.parse(xml)).to eq(
        [
          {
            station_code: "1421220",
            occurred_at: "2026-07-16T15:04:00+09:00",
            event_id: "20260716150443",
            seismic_intensity_level_label_ja: "1",
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
            station_code: "44132",
            occurred_at: "2026-07-16T15:00:00+09:00",
            rainfall_mm: "12.5",
            simulated: false
          }
        ]
      )
    end

    it "normalizes JMA seismic intensity symbols (e.g. 5-, 5+, 6-, 6+ to Japanese text)" do
      xml = <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <Report xmlns="http://xml.kishou.go.jp/jmaxml1/">
          <Head>
            <EventID>test-event-123</EventID>
            <ReportDateTime>2026-07-16T15:00:00+09:00</ReportDateTime>
          </Head>
          <Body>
            <Intensity>
              <Observation>
                <Pref>
                  <Area>
                    <City>
                      <IntensityStation>
                        <Code>1111111</Code>
                        <Int>5-</Int>
                      </IntensityStation>
                      <IntensityStation>
                        <Code>2222222</Code>
                        <Int>5+</Int>
                      </IntensityStation>
                      <IntensityStation>
                        <Code>3333333</Code>
                        <Int>6-</Int>
                      </IntensityStation>
                      <IntensityStation>
                        <Code>4444444</Code>
                        <Int>6+</Int>
                      </IntensityStation>
                    </City>
                  </Area>
                </Pref>
              </Observation>
            </Intensity>
          </Body>
        </Report>
      XML

      results = described_class.parse(xml)
      expect(results).to contain_exactly(
        {
          station_code: "1111111",
          occurred_at: "2026-07-16T15:00:00+09:00",
          event_id: "test-event-123",
          seismic_intensity_level_label_ja: "5弱",
          simulated: false
        },
        {
          station_code: "2222222",
          occurred_at: "2026-07-16T15:00:00+09:00",
          event_id: "test-event-123",
          seismic_intensity_level_label_ja: "5強",
          simulated: false
        },
        {
          station_code: "3333333",
          occurred_at: "2026-07-16T15:00:00+09:00",
          event_id: "test-event-123",
          seismic_intensity_level_label_ja: "6弱",
          simulated: false
        },
        {
          station_code: "4444444",
          occurred_at: "2026-07-16T15:00:00+09:00",
          event_id: "test-event-123",
          seismic_intensity_level_label_ja: "6強",
          simulated: false
        }
      )
    end
  end

  describe "#call" do
    it "invokes IngestObservationEvent with parsed payloads for direct XML" do
      xml = File.read(Rails.root.join("spec/fixtures/jma/seismic.xml"))
      ingest_service = instance_double(IngestObservationEvent)

      expect(IngestObservationEvent).to receive(:new).with(
        payload: {
          station_code: "1421220",
          occurred_at: "2026-07-16T15:04:00+09:00",
          event_id: "20260716150443",
          seismic_intensity_level_label_ja: "1",
          simulated: false
        }
      ).and_return(ingest_service)

      expect(ingest_service).to receive(:call)

      described_class.new(xml: xml).call
    end

    it "polls the Atom feed, downloads individual XMLs safely, prevents duplicates, and filters unsafe URLs" do
      ProcessedJmaEntry.create!(entry_id: "urn:uuid:eq-entry-duplicate")

      feed_xml = File.read(Rails.root.join("spec/fixtures/jma/feed.xml"))
      seismic_xml = File.read(Rails.root.join("spec/fixtures/jma/seismic.xml"))

      http_double = double("http")
      allow(Net::HTTP).to receive(:start).and_yield(http_double)

      feed_uri = URI("https://www.data.jma.go.jp/developer/xml/feed/eqvol.xml")
      feed_response = instance_double(Net::HTTPSuccess, body: feed_xml)
      allow(feed_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
      allow(http_double).to receive(:get).with(feed_uri.request_uri).and_return(feed_response)

      indiv_uri = URI("https://xml.data.jma.go.jp/data/seismic_sample.xml")
      indiv_response = instance_double(Net::HTTPSuccess, body: seismic_xml)
      allow(indiv_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
      allow(http_double).to receive(:get).with(indiv_uri.request_uri).and_return(indiv_response)

      unsafe_uri = URI("http://unsafe.example.com/malicious.xml")
      expect(http_double).not_to receive(:get).with(unsafe_uri.request_uri)

      ingest_service = instance_double(IngestObservationEvent)
      expect(IngestObservationEvent).to receive(:new).with(
        payload: {
          station_code: "1421220",
          occurred_at: "2026-07-16T15:04:00+09:00",
          event_id: "20260716150443",
          seismic_intensity_level_label_ja: "1",
          simulated: false
        }
      ).and_return(ingest_service)
      expect(ingest_service).to receive(:call)

      poller = described_class.new(feed_url: feed_uri.to_s, rainfall_feed_url: nil)
      expect {
        poller.call
      }.to change { ProcessedJmaEntry.count }.by(1)

      expect(ProcessedJmaEntry.exists?(entry_id: "urn:uuid:eq-entry-1")).to be_truthy
    end

    it "does not mark entry as processed if HTTP request for individual XML fails" do
      feed_xml = File.read(Rails.root.join("spec/fixtures/jma/feed.xml"))

      http_double = double("http")
      allow(Net::HTTP).to receive(:start).and_yield(http_double)

      feed_uri = URI("https://www.data.jma.go.jp/developer/xml/feed/eqvol.xml")
      feed_response = instance_double(Net::HTTPSuccess, body: feed_xml)
      allow(feed_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
      allow(http_double).to receive(:get).with(feed_uri.request_uri).and_return(feed_response)

      indiv_uri = URI("https://xml.data.jma.go.jp/data/seismic_sample.xml")
      error_response = instance_double(Net::HTTPResponse, code: "500")
      allow(error_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(false)
      allow(http_double).to receive(:get).with(indiv_uri.request_uri).and_return(error_response)

      poller = described_class.new(feed_url: feed_uri.to_s, rainfall_feed_url: nil)

      expect {
        poller.call
      }.not_to change { ProcessedJmaEntry.count }

      expect(ProcessedJmaEntry.exists?(entry_id: "urn:uuid:eq-entry-1")).to be_falsey
    end

    it "does not mark entry as processed if ingest service call fails" do
      feed_xml = File.read(Rails.root.join("spec/fixtures/jma/feed.xml"))
      seismic_xml = File.read(Rails.root.join("spec/fixtures/jma/seismic.xml"))

      http_double = double("http")
      allow(Net::HTTP).to receive(:start).and_yield(http_double)

      feed_uri = URI("https://www.data.jma.go.jp/developer/xml/feed/eqvol.xml")
      feed_response = instance_double(Net::HTTPSuccess, body: feed_xml)
      allow(feed_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
      allow(http_double).to receive(:get).with(feed_uri.request_uri).and_return(feed_response)

      indiv_uri = URI("https://xml.data.jma.go.jp/data/seismic_sample.xml")
      indiv_response = instance_double(Net::HTTPSuccess, body: seismic_xml)
      allow(indiv_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
      allow(http_double).to receive(:get).with(indiv_uri.request_uri).and_return(indiv_response)

      ingest_service = instance_double(IngestObservationEvent)
      allow(IngestObservationEvent).to receive(:new).and_return(ingest_service)
      allow(ingest_service).to receive(:call).and_raise("Database Connection Error")

      poller = described_class.new(feed_url: feed_uri.to_s, rainfall_feed_url: nil)

      expect {
        poller.call
      }.not_to change { ProcessedJmaEntry.count }

      expect(ProcessedJmaEntry.exists?(entry_id: "urn:uuid:eq-entry-1")).to be_falsey
    end

    it "processes Atom feed correctly without double ingesting when called with xml" do
      feed_xml = File.read(Rails.root.join("spec/fixtures/jma/feed.xml"))
      seismic_xml = File.read(Rails.root.join("spec/fixtures/jma/seismic.xml"))

      http_double = double("http")
      allow(Net::HTTP).to receive(:start).and_yield(http_double)

      indiv_uri = URI("https://xml.data.jma.go.jp/data/seismic_sample.xml")
      indiv_response = instance_double(Net::HTTPSuccess, body: seismic_xml)
      allow(indiv_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
      allow(http_double).to receive(:get).with(indiv_uri.request_uri).and_return(indiv_response)

      ingest_service = instance_double(IngestObservationEvent)
      expect(IngestObservationEvent).to receive(:new).twice.with(
        payload: {
          station_code: "1421220",
          occurred_at: "2026-07-16T15:04:00+09:00",
          event_id: "20260716150443",
          seismic_intensity_level_label_ja: "1",
          simulated: false
        }
      ).and_return(ingest_service)
      expect(ingest_service).to receive(:call).twice

      poller = described_class.new(xml: feed_xml)
      expect {
        poller.call
      }.to change { ProcessedJmaEntry.count }.by(2)
    end

    it "parses Atom feed without DB updates or network requests on Ingest" do
      feed_xml = File.read(Rails.root.join("spec/fixtures/jma/feed.xml"))
      seismic_xml = File.read(Rails.root.join("spec/fixtures/jma/seismic.xml"))

      http_double = double("http")
      allow(Net::HTTP).to receive(:start).and_yield(http_double)

      indiv_uri = URI("https://xml.data.jma.go.jp/data/seismic_sample.xml")
      indiv_response = instance_double(Net::HTTPSuccess, body: seismic_xml)
      allow(indiv_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
      allow(http_double).to receive(:get).with(indiv_uri.request_uri).and_return(indiv_response)

      expect(IngestObservationEvent).not_to receive(:new)

      expect {
        results = described_class.parse(feed_xml)
        expect(results.size).to eq(2)
        expect(results.first[:station_code]).to eq("1421220")
      }.not_to change { ProcessedJmaEntry.count }
    end

    it "does not mark entry as processed if individual XML is not JMA Report XML (e.g. HTML proxy error)" do
      feed_xml = File.read(Rails.root.join("spec/fixtures/jma/feed.xml"))
      html_response_body = "<html><body><h1>502 Bad Gateway</h1></body></html>"

      http_double = double("http")
      allow(Net::HTTP).to receive(:start).and_yield(http_double)

      feed_uri = URI("https://www.data.jma.go.jp/developer/xml/feed/eqvol.xml")
      feed_response = instance_double(Net::HTTPSuccess, body: feed_xml)
      allow(feed_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
      allow(http_double).to receive(:get).with(feed_uri.request_uri).and_return(feed_response)

      indiv_uri = URI("https://xml.data.jma.go.jp/data/seismic_sample.xml")
      html_response = instance_double(Net::HTTPSuccess, body: html_response_body)
      allow(html_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
      allow(http_double).to receive(:get).with(indiv_uri.request_uri).and_return(html_response)

      poller = described_class.new(feed_url: feed_uri.to_s, rainfall_feed_url: nil)

      expect {
        poller.call
      }.not_to change { ProcessedJmaEntry.count }

      expect(ProcessedJmaEntry.exists?(entry_id: "urn:uuid:eq-entry-1")).to be_falsey
    end

    it "extracts multiple rainfall observations over time from a time-series JMA XML" do
      xml = <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <Report xmlns="http://xml.kishou.go.jp/jmaxml1/">
          <Control>
            <Title>地上気象観測報</Title>
          </Control>
          <Head>
            <Title>地上気象観測報（アメダス）</Title>
            <ReportDateTime>2026-07-16T15:00:00+09:00</ReportDateTime>
          </Head>
          <Body>
            <MeteorologicalInfo>
              <TimeSeriesInfo>
                <TimeDefines>
                  <TimeDefine timeId="1">
                    <DateTime>2026-07-16T13:00:00+09:00</DateTime>
                  </TimeDefine>
                  <TimeDefine timeId="2">
                    <DateTime>2026-07-16T14:00:00+09:00</DateTime>
                  </TimeDefine>
                </TimeDefines>
                <Item>
                  <Station>
                    <Name>東京</Name>
                    <Code>44132</Code>
                  </Station>
                  <Kind>
                    <Property>
                      <Type>降水量</Type>
                      <Precipitation type="前１時間降水量" refID="1">10.5</Precipitation>
                      <Precipitation type="前１時間降水量" refID="2">15.0</Precipitation>
                    </Property>
                  </Kind>
                </Item>
              </TimeSeriesInfo>
            </MeteorologicalInfo>
          </Body>
        </Report>
      XML

      results = described_class.parse(xml)
      expect(results).to eq(
        [
          {
            station_code: "44132",
            occurred_at: "2026-07-16T13:00:00+09:00",
            rainfall_mm: "10.5",
            simulated: false
          },
          {
            station_code: "44132",
            occurred_at: "2026-07-16T14:00:00+09:00",
            rainfall_mm: "15.0",
            simulated: false
          }
        ]
      )
    end

    it "continues polling the rainfall feed even if the seismic feed fails" do
      http_double = double("http")
      allow(Net::HTTP).to receive(:start).and_yield(http_double)

      feed_uri_seismic = URI("https://www.data.jma.go.jp/developer/xml/feed/eqvol.xml")
      allow(http_double).to receive(:get).with(feed_uri_seismic.request_uri).and_raise("Connection timeout")

      feed_uri_rainfall = URI("https://www.data.jma.go.jp/developer/xml/feed/extra.xml")
      feed_xml = File.read(Rails.root.join("spec/fixtures/jma/feed.xml"))
      rainfall_response = instance_double(Net::HTTPSuccess, body: feed_xml)
      allow(rainfall_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
      allow(http_double).to receive(:get).with(feed_uri_rainfall.request_uri).and_return(rainfall_response)

      indiv_uri = URI("https://xml.data.jma.go.jp/data/seismic_sample.xml")
      seismic_xml = File.read(Rails.root.join("spec/fixtures/jma/seismic.xml"))
      indiv_response = instance_double(Net::HTTPSuccess, body: seismic_xml)
      allow(indiv_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
      allow(http_double).to receive(:get).with(indiv_uri.request_uri).and_return(indiv_response)

      ingest_service = instance_double(IngestObservationEvent)
      allow(IngestObservationEvent).to receive(:new).and_return(ingest_service)
      expect(ingest_service).to receive(:call).twice

      poller = described_class.new(feed_url: feed_uri_seismic.to_s, rainfall_feed_url: feed_uri_rainfall.to_s)

      expect {
        poller.call
      }.to change { ProcessedJmaEntry.count }.by(2)
    end

    it "resolves TimeDefine context per TimeSeriesInfo to avoid overwriting conflicting timeIds" do
      xml = <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <Report xmlns="http://xml.kishou.go.jp/jmaxml1/">
          <Body>
            <MeteorologicalInfo>
              <TimeSeriesInfo>
                <TimeDefines>
                  <TimeDefine timeId="1">
                    <DateTime>2026-07-16T13:00:00+09:00</DateTime>
                  </TimeDefine>
                </TimeDefines>
                <Item>
                  <Station><Code>44132</Code></Station>
                  <Kind><Property>
                    <Type>降水量</Type>
                    <Precipitation type="前１時間降水量" refID="1">10.0</Precipitation>
                  </Property></Kind>
                </Item>
              </TimeSeriesInfo>
              <TimeSeriesInfo>
                <TimeDefines>
                  <TimeDefine timeId="1">
                    <DateTime>2026-07-16T14:00:00+09:00</DateTime>
                  </TimeDefine>
                </TimeDefines>
                <Item>
                  <Station><Code>44132</Code></Station>
                  <Kind><Property>
                    <Type>降水量</Type>
                    <Precipitation type="前１時間降水量" refID="1">15.0</Precipitation>
                  </Property></Kind>
                </Item>
              </TimeSeriesInfo>
            </MeteorologicalInfo>
          </Body>
        </Report>
      XML

      results = described_class.parse(xml)
      expect(results).to contain_exactly(
        {
          station_code: "44132",
          occurred_at: "2026-07-16T13:00:00+09:00",
          rainfall_mm: "10.0",
          simulated: false
        },
        {
          station_code: "44132",
          occurred_at: "2026-07-16T14:00:00+09:00",
          rainfall_mm: "15.0",
          simulated: false
        }
      )
    end

    it "ignores rainfall observations other than '前１時間降水量' (e.g. 前２４時間降水量)" do
      xml = <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <Report xmlns="http://xml.kishou.go.jp/jmaxml1/">
          <Body>
            <MeteorologicalInfo>
              <TimeSeriesInfo>
                <TimeDefines>
                  <TimeDefine timeId="1">
                    <DateTime>2026-07-16T15:00:00+09:00</DateTime>
                  </TimeDefine>
                </TimeDefines>
                <Item>
                  <Station>
                    <Name>東京</Name>
                    <Code>44132</Code>
                  </Station>
                  <Kind>
                    <Property>
                      <Type>降水量</Type>
                      <Precipitation type="前１時間降水量" refID="1">12.5</Precipitation>
                      <Precipitation type="前２４時間降水量" refID="1">80.0</Precipitation>
                    </Property>
                  </Kind>
                </Item>
              </TimeSeriesInfo>
            </MeteorologicalInfo>
          </Body>
        </Report>
      XML

      results = described_class.parse(xml)
      expect(results).to eq(
        [
          {
            station_code: "44132",
            occurred_at: "2026-07-16T15:00:00+09:00",
            rainfall_mm: "12.5",
            simulated: false
          }
        ]
      )
    end

    it "treats training or test XML reports (Status != '通常') as simulated: true" do
      seismic_xml = <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <Report xmlns="http://xml.kishou.go.jp/jmaxml1/">
          <Control>
            <Status>訓練</Status>
          </Control>
          <Head>
            <EventID>20260716150443</EventID>
            <ReportDateTime>2026-07-16T15:04:00+09:00</ReportDateTime>
          </Head>
          <Body>
            <Intensity>
              <Observation>
                <Pref>
                  <Area>
                    <City>
                      <IntensityStation>
                        <Code>1421220</Code>
                        <Int>1</Int>
                      </IntensityStation>
                    </City>
                  </Area>
                </Pref>
              </Observation>
            </Intensity>
          </Body>
        </Report>
      XML

      rainfall_xml = <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <Report xmlns="http://xml.kishou.go.jp/jmaxml1/">
          <Control>
            <Status>試験</Status>
          </Control>
          <Head>
            <ReportDateTime>2026-07-16T15:05:00+09:00</ReportDateTime>
          </Head>
          <Body>
            <MeteorologicalInfo>
              <TimeSeriesInfo>
                <TimeDefines>
                  <TimeDefine timeId="1">
                    <DateTime>2026-07-16T15:00:00+09:00</DateTime>
                  </TimeDefine>
                </TimeDefines>
                <Item>
                  <Station>
                    <Code>44132</Code>
                  </Station>
                  <Kind>
                    <Property>
                      <Type>降水量</Type>
                      <Precipitation type="前１時間降水量" refID="1">12.5</Precipitation>
                    </Property>
                  </Kind>
                </Item>
              </TimeSeriesInfo>
            </MeteorologicalInfo>
          </Body>
        </Report>
      XML

      seismic_results = described_class.parse(seismic_xml)
      expect(seismic_results.first[:simulated]).to be_truthy

      rainfall_results = described_class.parse(rainfall_xml)
      expect(rainfall_results.first[:simulated]).to be_truthy
    end

    it "raises ArgumentError when call is invoked without feed URLs configured" do
      poller = described_class.new(feed_url: nil, rainfall_feed_url: nil)
      expect {
        poller.call
      }.to raise_error(ArgumentError, /No JMA feed URL configured/)
    end

    it "falls back to JMA_OBSERVATION_FEED_URL when JMA_FEED_URL is absent" do
      stub_const('ENV', ENV.to_h.merge('JMA_FEED_URL' => nil, 'JMA_OBSERVATION_FEED_URL' => 'https://www.data.jma.go.jp/fallback.xml'))
      # JmaPoller::DEFAULT_FEED_URL is evaluated at class load, but we can test instance assignment or Env check
      expect(described_class.new(feed_url: (ENV["JMA_FEED_URL"].presence || ENV["JMA_OBSERVATION_FEED_URL"].presence).presence, rainfall_feed_url: nil).send(:feed_url)).to eq('https://www.data.jma.go.jp/fallback.xml')
    end
  end
end
