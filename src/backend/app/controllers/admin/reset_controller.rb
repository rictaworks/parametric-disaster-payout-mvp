module Admin
  class ResetController < HtmlController
    before_action :reject_production!

    def index
      load_counts
    end

    def create
      load_counts

      unless valid_confirmation?
        flash.now[:alert] = t("admin_ui.reset.index.failure")
        render :index, status: :unprocessable_entity
        return
      end

      result = ResetDemoData.new.call

      if result.success?
        redirect_to admin_reset_path, notice: t("admin_ui.reset.index.success")
      else
        flash.now[:alert] = t("admin_ui.reset.index.failure")
        render :index, status: :unprocessable_entity
      end
    end

    private

    def reject_production!
      head :not_found if Rails.env.production?
    end

    def load_counts
      @record_counts = {
        policies: Policy.count,
        observations: Observation.count,
        payouts: Payout.count,
        notifications: Notification.count,
        survey_responses: SurveyResponse.count,
        users: User.count,
        masters: [ Plan, Station, PayoutTier, PolicyStatus, PayoutStatus, SeismicIntensityLevel ].sum(&:count)
      }
    end

    def valid_confirmation?
      params[:confirmation_text].to_s.strip == ResetDemoData::CONFIRMATION_TEXT
    end
  end
end
