class ResetDemoData
  CONFIRMATION_TEXT = "デモデータを初期化する".freeze

  Result = Struct.new(:status, keyword_init: true) do
    def success?
      status == :ok
    end
  end

  def initialize
  end

  def call
    ActiveRecord::Base.transaction do
      SurveyResponse.delete_all
      Notification.delete_all
      Payout.delete_all
      Policy.delete_all
      ObservationEvent.delete_all
      Observation.delete_all
      ProcessedJmaEntry.delete_all
    end

    Result.new(status: :ok)
  end
end
