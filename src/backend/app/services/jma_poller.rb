require "net/http"
require "nokogiri"

class JmaPoller
  DEFAULT_FEED_URL = (ENV["JMA_FEED_URL"].presence || ENV["JMA_OBSERVATION_FEED_URL"].presence).presence
  DEFAULT_RAINFALL_FEED_URL = ENV["JMA_RAINFALL_FEED_URL"].presence

  ALLOWED_HOSTS = %w[www.data.jma.go.jp xml.data.jma.go.jp].freeze

  SEISMIC_INTENSITY_MAP = {
    "0" => "0",
    "1" => "1",
    "2" => "2",
    "3" => "3",
    "4" => "4",
    "5-" => "5弱",
    "5+" => "5強",
    "6-" => "6弱",
    "6+" => "6強",
    "7" => "7"
  }.freeze

  def self.parse(xml)
    new(xml: xml).parse
  end

  def initialize(xml: nil, feed_url: DEFAULT_FEED_URL, rainfall_feed_url: DEFAULT_RAINFALL_FEED_URL, ingest_service_class: IngestObservationEvent)
    @xml = xml
    @feed_url = feed_url
    @rainfall_feed_url = rainfall_feed_url
    @ingest_service_class = ingest_service_class
  end

  def call
    if xml.present?
      document = Nokogiri::XML(xml, nil, nil, Nokogiri::XML::ParseOptions::NONET)
      if is_atom_feed?(document)
        process_atom_feed(document)
      else
        parse_individual_xml(document).each do |payload|
          ingest_service_class.new(payload: payload).call
        end
      end
    else
      if feed_url.blank? && rainfall_feed_url.blank?
        raise ArgumentError, "No JMA feed URL configured. Please set JMA_FEED_URL or JMA_RAINFALL_FEED_URL."
      end

      if feed_url.present?
        begin
          poll_and_ingest(feed_url)
        rescue => e
          Rails.logger.error("Failed to poll seismic feed: #{e.message}")
        end
      end

      if rainfall_feed_url.present?
        begin
          poll_and_ingest(rainfall_feed_url)
        rescue => e
          Rails.logger.error("Failed to poll rainfall feed: #{e.message}")
        end
      end
    end
  end

  def parse
    document = Nokogiri::XML(xml, nil, nil, Nokogiri::XML::ParseOptions::NONET)
    if is_atom_feed?(document)
      parse_atom_feed_only(document)
    else
      parse_individual_xml(document)
    end
  end

  private

  attr_reader :xml, :feed_url, :rainfall_feed_url, :ingest_service_class

  def poll_and_ingest(url)
    feed_xml = fetch_xml(url)
    document = Nokogiri::XML(feed_xml, nil, nil, Nokogiri::XML::ParseOptions::NONET)
    process_atom_feed(document)
  end

  def is_atom_feed?(document)
    document.root&.name == "feed"
  end

  def process_atom_feed(document)
    namespaces = { "xmlns" => "http://www.w3.org/2005/Atom" }

    document.xpath("//xmlns:entry", namespaces).each do |entry|
      entry_id = text_at(entry, "./xmlns:id", namespaces)
      next if entry_id.blank?
      next if ProcessedJmaEntry.exists?(entry_id: entry_id)

      link = entry.at_xpath("./xmlns:link[@type='application/xml']", namespaces)
      next if link.nil?

      href = link["href"]
      next if href.blank?
      next unless valid_jma_url?(href)

      begin
        individual_xml = fetch_xml(href)
        indiv_doc = Nokogiri::XML(individual_xml, nil, nil, Nokogiri::XML::ParseOptions::NONET)

        validate_jma_report!(indiv_doc)
        entry_payloads = parse_individual_xml(indiv_doc)

        ActiveRecord::Base.transaction do
          entry_payloads.each do |payload|
            ingest_service_class.new(payload: payload).call
          end

          ProcessedJmaEntry.create!(entry_id: entry_id)
        end
      rescue => e
        Rails.logger.error("Failed to process JMA entry #{entry_id}: #{e.message}")
      end
    end
  end

  def parse_atom_feed_only(document)
    payloads = []
    namespaces = { "xmlns" => "http://www.w3.org/2005/Atom" }

    document.xpath("//xmlns:entry", namespaces).each do |entry|
      link = entry.at_xpath("./xmlns:link[@type='application/xml']", namespaces)
      next if link.nil?

      href = link["href"]
      next if href.blank?
      next unless valid_jma_url?(href)

      begin
        individual_xml = fetch_xml(href)
        indiv_doc = Nokogiri::XML(individual_xml, nil, nil, Nokogiri::XML::ParseOptions::NONET)
        validate_jma_report!(indiv_doc)
        payloads.concat(parse_individual_xml(indiv_doc))
      rescue => e
        Rails.logger.error("Failed to parse JMA entry: #{e.message}")
      end
    end
    payloads
  end

  def parse_individual_xml(document)
    seismic_observations(document) + rainfall_observations(document)
  end

  def valid_jma_url?(url_string)
    uri = URI(url_string)
    uri.scheme == "https" && ALLOWED_HOSTS.include?(uri.host)
  rescue URI::InvalidURIError
    false
  end

  def fetch_xml(url_string)
    uri = URI(url_string)

    response = Net::HTTP.start(
      uri.host,
      uri.port,
      use_ssl: uri.scheme == "https",
      open_timeout: 5,
      read_timeout: 10
    ) do |http|
      http.get(uri.request_uri)
    end

    unless response.is_a?(Net::HTTPSuccess)
      raise "HTTP request failed with status: #{response.code}"
    end

    response.body
  end

  def normalize_seismic_intensity(raw_int)
    SEISMIC_INTENSITY_MAP[raw_int.to_s.strip] || raw_int
  end

  def seismic_observations(document)
    event_id = text_at(document, "//*[local-name()='Head']/*[local-name()='EventID']") || text_at(document, "//*[local-name()='EventID']")
    occurred_at = text_at(document, "//*[local-name()='Earthquake']/*[local-name()='OriginTime']") || text_at(document, "//*[local-name()='ReportDateTime']")
    simulated = is_simulated_status?(document)

    document.xpath("//*[local-name()='IntensityStation']").filter_map do |station|
      raw_int = text_at(station, "./*[local-name()='Int']")
      payload = {
        station_code: text_at(station, "./*[local-name()='Code']"),
        occurred_at: occurred_at,
        event_id: event_id,
        seismic_intensity_level_label_ja: normalize_seismic_intensity(raw_int),
        simulated: simulated
      }

      payload if required_seismic_payload?(payload)
    end
  end

  def rainfall_observations(document)
    payloads = []
    tsis = document.xpath("//*[local-name()='TimeSeriesInfo']")
    simulated = is_simulated_status?(document)

    if tsis.any?
      tsis.each do |tsi|
        time_defines = {}
        tsi.xpath(".//*[local-name()='TimeDefine']").each do |td|
          time_id = td["timeId"]
          date_time = text_at(td, "./*[local-name()='DateTime']")
          time_defines[time_id] = date_time if time_id.present? && date_time.present?
        end

        tsi.xpath(".//*[local-name()='Item']").each do |item|
          process_rainfall_item(item, time_defines, document, payloads, simulated)
        end
      end
    else
      time_defines = {}
      document.xpath("//*[local-name()='TimeDefine']").each do |td|
        time_id = td["timeId"]
        date_time = text_at(td, "./*[local-name()='DateTime']")
        time_defines[time_id] = date_time if time_id.present? && date_time.present?
      end

      document.xpath("//*[local-name()='Item']").each do |item|
        process_rainfall_item(item, time_defines, document, payloads, simulated)
      end
    end

    payloads
  end

  def process_rainfall_item(item, time_defines, document, payloads, simulated)
    station_code = text_at(item, ".//*[local-name()='Station']/*[local-name()='Code']") ||
                   text_at(item, ".//*[local-name()='Area']/*[local-name()='Code']")
    return if station_code.blank?

    item.xpath(".//*[local-name()='Precipitation']").each do |precip|
      precip_type = precip["type"]
      next unless precip_type == "前１時間降水量"

      rainfall_val = precip.text.strip
      next if rainfall_val.blank?

      ref_id = precip["refID"] || precip["refId"]
      occurred_at = time_defines[ref_id] if ref_id.present?
      occurred_at ||= text_at(item, "ancestor::*[local-name()='MeteorologicalInfo']/*[local-name()='DateTime']") ||
                      text_at(document, "//*[local-name()='ReportDateTime']")

      payload = {
        station_code: station_code,
        occurred_at: occurred_at,
        rainfall_mm: rainfall_val,
        simulated: simulated
      }

      payloads << payload if required_rainfall_payload?(payload)
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

  def is_simulated_status?(document)
    status = text_at(document, "//*[local-name()='Control']/*[local-name()='Status']")
    status.present? && status != "normal" && status != "通常"
  end

  def text_at(node, xpath, namespaces = {})
    node.at_xpath(xpath, namespaces)&.text&.strip
  end

  def validate_jma_report!(document)
    if document.root.nil? || document.root.name != "Report"
      raise "Invalid JMA XML structure: root element is #{document.root&.name || 'nil'}, expected 'Report'"
    end
  end
end
