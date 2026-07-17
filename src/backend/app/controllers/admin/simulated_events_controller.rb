require "securerandom"

module Admin
  class SimulatedEventsController < HtmlController
    def index
      load_form_data
    end

    def create
      load_form_data

      payload = build_payload
      unless payload
        flash.now[:alert] = t("admin_ui.simulated_events.index.create.failure")
        render :index, status: :unprocessable_entity
        return
      end

      result = IngestObservationEvent.new(payload: payload).call

      if result.success?
        redirect_to admin_simulated_events_path, notice: t("admin_ui.simulated_events.index.create.success")
      else
        flash.now[:alert] = t("admin_ui.simulated_events.index.create.failure")
        render :index, status: :unprocessable_entity
      end
    end

    private

    def load_form_data
      @stations = Station.order(:measurement_type, :code)
      @seismic_intensity_levels = SeismicIntensityLevel.order(:sort_order)
      @recent_observations = Observation.where(simulated: true, admin_injected: true).includes(:station, :seismic_intensity_level).order(created_at: :desc).limit(50)
      @recent_observation_options = @recent_observations.map { |observation| [ observation_option_label(observation), observation.id ] }
    end

    def build_payload
      station = Station.find_by(id: params[:station_id])
      return nil if station.nil?

      follow_up_observation = follow_up? ? Observation.where(simulated: true, admin_injected: true).includes(:station, :seismic_intensity_level).find_by(id: params[:observation_id]) : nil
      return nil if follow_up? && follow_up_observation.nil?
      return nil if follow_up_observation.present? && follow_up_observation.station_id != station.id

      if station.measurement_type == "seismic"
        build_seismic_payload(station, follow_up_observation)
      else
        build_rainfall_payload(station, follow_up_observation)
      end
    end

    def build_seismic_payload(station, follow_up_observation)
      seismic_intensity_level_id = params[:seismic_intensity_level_id].presence
      return nil if seismic_intensity_level_id.nil?

      {
        station_id: station.id,
        event_id: follow_up_observation&.event_id.presence || simulated_event_id(station),
        occurred_at: follow_up_observation&.observed_at || Time.current,
        seismic_intensity_level_id: seismic_intensity_level_id,
        simulated: true,
        admin_injected: true
      }
    end

    def build_rainfall_payload(station, follow_up_observation)
      rainfall_mm = params[:rainfall_mm].presence
      return nil if rainfall_mm.nil?
      return nil unless valid_rainfall_mm?(rainfall_mm)

      {
        station_id: station.id,
        occurred_at: follow_up_observation&.observed_at || Time.current,
        rainfall_mm: rainfall_mm,
        simulated: true,
        admin_injected: true
      }
    end

    def follow_up?
      params[:event_mode] == "follow_up"
    end

    def valid_rainfall_mm?(rainfall_mm)
      value = BigDecimal(rainfall_mm.to_s)
      value >= 0
    rescue ArgumentError
      false
    end

    def simulated_event_id(station)
      "simulated-#{station.code}-#{SecureRandom.uuid}"
    end

    def observation_option_label(observation)
      value =
        if observation.station.measurement_type == "seismic"
          observation.seismic_intensity_level&.label_ja || observation.max_value
        else
          observation.rainfall_mm
        end

      "#{observation.station.code} / #{observation.observed_at.strftime("%Y-%m-%d %H:%M")} / #{value}"
    end
  end
end
