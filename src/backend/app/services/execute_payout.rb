class ExecutePayout
  Result = Struct.new(:payout, :status, keyword_init: true) do
    def success?
      status == :ok
    end
  end

  def initialize(payout:)
    @payout = payout
  end

  def call
    payout.with_lock do
      return Result.new(payout: payout, status: :ok) if completed_payout?

      ActiveRecord::Base.transaction do
        payout.update!(payout_status: completed_status)
        create_notifications!
      end
    end

    Result.new(payout: payout.reload, status: :ok)
  end

  private

  attr_reader :payout

  def completed_payout?
    payout.payout_status == completed_status
  end

  def completed_status
    @completed_status ||= PayoutStatus.find_by!(code: "completed_simulated")
  end

  def create_notifications!
    Notification.create!(
      user: payout.policy.user,
      policy: payout.policy,
      payout: payout,
      kind: Notification::KIND_PAYOUT_COMPLETED,
      message: I18n.t("notifications.payout_completed")
    )

    Notification.create!(
      user: payout.policy.user,
      policy: payout.policy,
      payout: payout,
      kind: Notification::KIND_SURVEY_REQUEST,
      message: I18n.t("notifications.survey_request")
    )
  end
end
