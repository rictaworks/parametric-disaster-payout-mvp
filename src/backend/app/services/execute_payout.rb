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
      return Result.new(payout: payout, status: :unprocessable_entity) unless payout.payout_status.code == "ordered"

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
    # 管理画面（Admin::Authenticationのaround_action）が呼び出しスレッドのI18n.localeを
    # 常に:jaへ固定するため、契約者本人宛の通知だけは契約者のUser#localeで明示的に
    # 上書きして生成する（Issue #65）
    I18n.with_locale(payout.policy.user.locale) do
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
end
