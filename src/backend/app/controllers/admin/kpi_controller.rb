module Admin
  class KpiController < HtmlController
    def index
      @kpi_metrics = KpiAggregator.new.call

      respond_to do |format|
        format.html
        format.json { render json: @kpi_metrics }
      end
    end
  end
end
