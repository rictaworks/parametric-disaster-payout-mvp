# F4 completePayout (管理者確認操作)
# 管理者確認操作で「支払完了（模擬）」に遷移させ、完了通知とアンケート依頼を送る。
class CompletePayout
  def initialize(payout:)
    @payout = payout
  end

  # @return [Payout]
  def call
    ActiveRecord::Base.transaction do
      @payout.update!(status: "completed")

      policy = @payout.policy
      user = policy.user

      Notification.create!(
        user: user,
        policy: policy,
        payout: @payout,
        notification_type: "payout_completed",
        body: "【保険（デモ）】模擬支払が完了しました。支払金額（模擬）: #{format_amount(@payout.amount)}円。※実際の金銭は支払われません。"
      )

      Notification.create!(
        user: user,
        policy: policy,
        payout: @payout,
        notification_type: "survey_request",
        body: "【保険（デモ）】サービスご利用のアンケートにご協力ください。ご意見をお聞かせいただけると幸いです。"
      )
    end

    @payout
  end

  private

  def format_amount(amount)
    amount.to_i.to_s.gsub(/(\d)(?=(\d\d\d)+(?!\d))/, "\\1,")
  end
end
