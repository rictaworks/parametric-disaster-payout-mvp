require "net/http"
require "nokogiri"

class JmaPoller
  DEFAULT_FEED_URL = ENV["JMA_OBSERVATION_FEED_URL"].presence

  def self.parse(xml)
    new(xml: xml).parse
  end

  def initialize(xml: nil, feed_url: DEFAULT_FEED_URL, ingest_service_class: IngestObservationEvent)
    @xml = xml
    @feed_url = feed_url
    @ingest_service_class = ingest_service_class
  end

  def call
    parse.each do |payload|
      ingest_service_class.new(payload: payload).call
    end
  end

  def parse
    document = Nokogiri::XML(source_xml, nil, nil, Nokogiri::XML::ParseOptions::NONET)
    seismic_observations(document) + rainfall_observations(document)
  end

  private

  attr_reader :xml, :feed_url, :ingest_service_class

  def source_xml
    return xml if xml.present?
    return fetch_xml(feed_url) if feed_url.present?

    raise ArgumentError, "JMA_OBSERVATION_FEED_URL must be configured when xml is not provided"
  end

  def fetch_xml(feed_url)
    uri = URI(feed_url)

    Net::HTTP.start(
      uri.host,
      uri.port,
      use_ssl: uri.scheme == "https",
      open_timeout: 5,
      read_timeout: 10
    ) do |http|
      http.get(uri.request_uri).body
    end
  end

  def seismic_observations(document)
    document.xpath("//*[local-name()='City'][*[local-name()='Code'] and *[local-name()='Intensity']]").filter_map do |city|
      payload = {
        station_code: text_at(city, "./*[local-name()='Code']"),
        occurred_at: text_at(document, "//*[local-name()='Earthquake']/*[local-name()='OriginTime']") || text_at(document, "//*[local-name()='ReportDateTime']"),
        event_id: text_at(document, "//*[local-name()='Earthquake']/*[local-name()='EventID']") || text_at(document, "//*[local-name()='ReportId']"),
        seismic_intensity_level_label_ja: text_at(city, "./*[local-name()='Intensity']"),
        simulated: false
      }

      payload if required_seismic_payload?(payload)
    end
  end

  def rainfall_observations(document)
    document.xpath("//*[local-name()='Station'][*[local-name()='Precipitation']]").filter_map do |station|
      payload = {
        station_code: text_at(station, "./*[local-name()='Code']"),
        occurred_at: text_at(station, ".//*[local-name()='Time'][1]") || text_at(document, "//*[local-name()='ReportDateTime']"),
        rainfall_mm: text_at(station, "./*[local-name()='Precipitation']"),
        simulated: false
      }

      payload if required_rainfall_payload?(payload)
    end
  end

  def required_seismic_payload?(payload)
    payload[:station_code].present? &&
      payload[:occurred_at].present? &&
      payload[:event_id].present? &&
      payload[:seismic_intensity_level_label_ja].present?
  end

  def required_rainfall_payload?(payload)
    payload[:station_code].present? &&
      payload[:occurred_at].present? &&
      payload[:rainfall_mm].present?
  end

  def text_at(node, xpath)
    node.at_xpath(xpath)&.text&.strip
  end
end
