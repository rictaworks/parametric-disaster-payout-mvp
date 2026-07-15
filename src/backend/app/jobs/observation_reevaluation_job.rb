class ObservationReevaluationJob < ApplicationJob
  # Placeholder queue entry point only: IngestObservationEvent (F2, Stage 6) enqueues this job
  # whenever an observation's max_value changes, but actual trigger evaluation (F3
  # evaluateTrigger — Stage 7 / Issue #8) is not implemented yet. This job intentionally does
  # not evaluate policies or create payouts; it must not be treated as a working payout path
  # until Stage 7 wires the real evaluation service in here.
  def perform(observation_id)
    Observation.find_by(id: observation_id)
  end
end
