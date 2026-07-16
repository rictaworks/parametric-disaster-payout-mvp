module Admin
  class PoliciesController < HtmlController
    def index
      @policies = Policy.includes(:user, :plan, :station, :policy_status, :payout_tier).order(created_at: :desc)
      @annual_payout_counts = Payout.annual_completed_counts(policy_ids: @policies.map(&:id))
    end
  end
end
