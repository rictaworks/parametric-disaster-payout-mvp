module Admin
  class PoliciesController < HtmlController
    def index
      @policies = Policy.includes(:user, :plan, :station, :policy_status, :payout_tier).order(created_at: :desc)
      @annual_payout_counts = annual_payout_counts
    end

    private

    def annual_payout_counts
      year_range = Time.zone.local(Time.current.year, 1, 1).beginning_of_day..Time.zone.local(Time.current.year, 12, 31).end_of_day
      invalid_status = PayoutStatus.find_by(code: "invalid")

      payouts = Payout.joins(:observation).where(observations: { observed_at: year_range })
      payouts = payouts.where.not(payout_status: invalid_status) if invalid_status.present?

      payouts.group(:policy_id).count
    end
  end
end
