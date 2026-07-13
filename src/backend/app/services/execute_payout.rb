# F4 executePayout
# 支払指図の生成と同時に契約者へアプリ内通知を送る。
# 年間支払回数が上限（2回）に達した契約は「上限到達」状態に遷移する。
class ExecutePayout
  def initialize(policy:, observation: nil, amount:, idempotency_key:)
    @policy = policy
    @observation = observation
    @amount = amount
    @idempotency_key = idempotency_key
  end

  # 支払指図を生成し、通知を作成する。
  # 既に同じidempotency_keyで支払が生成されている場合は既存を返す（冪等性）。
  # @return [Payout]
  def call
    existing = Payout.find_by(idempotency_key: @idempotency_key)
    return existing if existing

    payout = nil
    ActiveRecord::Base.transaction do
      payout = Payout.create!(
        policy: @policy,
        observation: @observation,
        amount: @amount,
        status: "pending",
        idempotency_key: @idempotency_key
      )

      @policy.increment!(:annual_payout_count)

      Notification.create!(
        user: @policy.user,
        policy: @policy,
        payout: payout,
        notification_type: "payout_created",
        body: "【保険（デモ）】模擬支払指図が生成されました。支払金額（模擬）: #{format_amount(@amount)}円。管理者確認後に模擬支払完了となります。"
      )

      if @policy.reload.limit_reached?
        @policy.update!(status: "limit_reached")
        Notification.create!(
          user: @policy.user,
          policy: @policy,
          payout: payout,
          notification_type: "limit_reached",
          body: "【保険（デモ）】今年度の模擬支払回数が上限（#{Policy::ANNUAL_PAYOUT_LIMIT}回）に達しました。契約は「上限到達」状態に遷移しました。"
        )
      end
    end

    payout
  end

  private

  def format_amount(amount)
    amount.to_i.to_s.gsub(/(\d)(?=(\d\d\d)+(?!\d))/, "\\1,")
  end
end
