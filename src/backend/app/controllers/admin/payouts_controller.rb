module Admin
  class PayoutsController < HtmlController
    def index
      @payouts = Payout.includes(
        { policy: [ :user, :plan, :station, :policy_status, :payout_tier ] },
        :payout_status,
        :observation
      ).order(created_at: :desc)
    end
  end
end
