class ObservationReevaluationJob < ApplicationJob
  def perform(observation_id)
    Observation.find_by(id: observation_id)
  end
end
