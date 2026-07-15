class IngestObservationEvent
  Result = Struct.new(:observation, :history_event, :queued, :status, keyword_init: true) do
    def success?
      status != :ignored
    end
  end

  # A concurrent ingest (5分ポーリングと管理画面注入の同時到着など) can race between the
  # existence check and the insert/update below. MAX_ATTEMPTS bounds the retry loop that
  # re-reads and re-applies the comparison after losing such a race exactly once or twice.
  MAX_ATTEMPTS = 3

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

    attempts = 0
    begin
      attempts += 1
      ingest(station, occurrence_time)
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
      # A concurrent insert can win either as a DB-level unique violation or, if the other
      # process commits between our own uniqueness validation and insert, as a validation
      # failure here. Both mean someone else just created the row we were about to create.
      raise if attempts >= MAX_ATTEMPTS

      retry
    end
  end

  private

  attr_reader :payload, :queue_job

  def ingest(station, occurrence_time)
    observation = find_summary_observation(station, occurrence_time)

    return create_summary_observation!(station, occurrence_time) if observation.nil?

    apply_update_or_record!(observation, occurrence_time)
  end

  def create_summary_observation!(station, occurrence_time)
    ActiveRecord::Base.transaction do
      observation = build_summary_observation(station, occurrence_time)
      observation.save!
      history_event = record_history!(observation, occurrence_time)
      enqueue_re_evaluation!(observation)
      Result.new(observation: observation, history_event: history_event, queued: true, status: :created)
    end
  end

  # Uses a single conditional UPDATE (`WHERE max_value < ?`) instead of read-then-write so a
  # concurrent ingest that already committed a higher max_value cannot be clobbered by this
  # attempt's stale in-memory comparison (see IngestObservationEvent MAX_ATTEMPTS comment).
  def apply_update_or_record!(observation, occurrence_time)
    ActiveRecord::Base.transaction do
      if incoming_value > observation.max_value.to_d && apply_conditional_max_update!(observation)
        history_event = record_history!(observation, occurrence_time)
        enqueue_re_evaluation!(observation)
        Result.new(observation: observation, history_event: history_event, queued: true, status: :updated)
      else
        history_event = record_history!(observation, occurrence_time)
        Result.new(observation: observation, history_event: history_event, queued: false, status: :recorded)
      end
    end
  end

  def apply_conditional_max_update!(observation)
    attrs =
      if observation.station.measurement_type == "seismic"
        { seismic_intensity_level_id: seismic_intensity_level.id }
      else
        { rainfall_mm: rainfall_mm }
      end
    attrs = attrs.merge(max_value: incoming_value, updated_at: Time.current)

    updated_rows = Observation.where(id: observation.id).where("max_value < ?", incoming_value).update_all(attrs)
    return false if updated_rows.zero?

    observation.assign_attributes(attrs)
    true
  end

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
