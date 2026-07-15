class ObservationReevaluationJob < ApplicationJob
  def perform(observation_id)
    observation = Observation.find_by(id: observation_id)
    return unless observation

    EvaluateTrigger.call(observation)
  end
end
