class IngestObservationEvent
  Result = Struct.new(:observation, :history_event, :queued, :status, keyword_init: true) do
    def success?
      status != :ignored
    end
  end

  def initialize(payload:, queue_job: ObservationReevaluationJob)
    @payload = payload.deep_symbolize_keys
    @queue_job = queue_job
  end

  def call
    station = find_station
    return Result.new(status: :ignored) if station.nil?

    occurrence_time = occurred_at
    return Result.new(status: :ignored) if occurrence_time.nil?
    return Result.new(status: :ignored) if station.measurement_type == "seismic" && event_id.nil?
    return Result.new(status: :ignored) if station.measurement_type == "seismic" && seismic_intensity_level.nil?
    return Result.new(status: :ignored) if station.measurement_type == "rainfall" && rainfall_mm.nil?

    ActiveRecord::Base.transaction do
      observation = find_summary_observation(station, occurrence_time)

      if observation.nil?
        observation = build_summary_observation(station, occurrence_time)
        observation.save!
        history_event = record_history!(observation, occurrence_time)
        enqueue_re_evaluation!(observation)
        return Result.new(observation: observation, history_event: history_event, queued: true, status: :created)
      end

      if incoming_value > observation.max_value.to_d
        update_max_observation!(observation)
        history_event = record_history!(observation, occurrence_time)
        enqueue_re_evaluation!(observation)
        return Result.new(observation: observation, history_event: history_event, queued: true, status: :updated)
      end

      history_event = record_history!(observation, occurrence_time)
      Result.new(observation: observation, history_event: history_event, queued: false, status: :recorded)
    end
  end

  private

  attr_reader :payload, :queue_job

  def find_station
    station_identifier = payload[:station_id] || payload[:station_code] || payload[:station]
    return station_identifier if station_identifier.is_a?(Station)

    Station.find_by(id: station_identifier) || Station.find_by(code: station_identifier)
  end

  def occurred_at
    value = payload[:occurred_at] || payload[:observed_at]
    return value if value.respond_to?(:to_time) || value.is_a?(Time)
    return Time.zone.parse(value) if value.is_a?(String)

    nil
  end

  def find_summary_observation(station, occurrence_time)
    case station.measurement_type
    when "seismic"
      Observation.find_by(station_id: station.id, event_id: event_id)
    when "rainfall"
      Observation.find_by(station_id: station.id, observed_at: occurrence_time)
    end
  end

  def build_summary_observation(station, occurrence_time)
    observation = Observation.new
    observation.max_value = incoming_value

    case station.measurement_type
    when "seismic"
      assign_seismic_attributes(observation, station, occurrence_time)
    when "rainfall"
      assign_rainfall_attributes(observation, station, occurrence_time)
    end

    observation
  end

  def update_max_observation!(observation)
    observation.max_value = incoming_value
    if observation.station.measurement_type == "seismic"
      observation.assign_attributes(seismic_intensity_level: seismic_intensity_level)
    else
      observation.assign_attributes(rainfall_mm: rainfall_mm)
    end
    observation.save!
  end

  def record_history!(observation, occurrence_time)
    observation.observation_events.create!(
      occurred_at: occurrence_time,
      payload: payload
    )
  end

  def enqueue_re_evaluation!(observation)
    queue_job.perform_later(observation.id)
  end

  def assign_seismic_attributes(observation, station, occurrence_time)
    observation.station = station
    observation.event_id = event_id
    observation.observed_at = occurrence_time
    observation.simulated = simulated?
    observation.seismic_intensity_level = seismic_intensity_level
    observation.rainfall_mm = nil
  end

  def assign_rainfall_attributes(observation, station, occurrence_time)
    observation.station = station
    observation.event_id = nil
    observation.observed_at = occurrence_time
    observation.simulated = simulated?
    observation.rainfall_mm = rainfall_mm
    observation.seismic_intensity_level = nil
  end

  def incoming_value
    @incoming_value ||= case station.measurement_type
    when "seismic"
      seismic_intensity_level.sort_order.to_d
    else
      rainfall_mm
    end
  end

  def station
    @station ||= find_station
  end

  def event_id
    payload[:event_id].presence
  end

  def seismic_intensity_level
    @seismic_intensity_level ||= begin
      value = payload[:seismic_intensity_level]
      return value if value.is_a?(SeismicIntensityLevel)

      SeismicIntensityLevel.find_by(id: payload[:seismic_intensity_level_id]) ||
        SeismicIntensityLevel.find_by(code: payload[:seismic_intensity_level_code]) ||
        SeismicIntensityLevel.find_by(label_ja: payload[:seismic_intensity_level_label_ja])
    end
  end

  def rainfall_mm
    @rainfall_mm ||= begin
      value = payload[:rainfall_mm]
      return nil if value.blank?

      BigDecimal(value.to_s)
    rescue ArgumentError
      nil
    end
  end

  def simulated?
    payload.fetch(:simulated, false)
  end
end
