class KpiAggregator
  JST_ZONE = ActiveSupport::TimeZone["Asia/Tokyo"]
  TERMINAL_POLICY_STATUS_CODES = %w[cancelled expired].freeze

  def call
    {
      registered_users_count: User.count,
      application_completion_rate: rate(Policy.distinct.count(:user_id), User.count),
      contract_continuation_rate: rate(continuing_policies_count, Policy.count),
      survey_response_count: SurveyResponse.count,
      average_satisfaction: average_satisfaction,
      todays_payout_orders_count: todays_payout_orders_count,
      average_order_latency_minutes: average_order_latency_minutes
    }
  end

  private

  def rate(numerator, denominator)
    return 0.0 if denominator.zero?

    numerator.to_f / denominator
  end

  def continuing_policies_count
    Policy.left_outer_joins(:policy_status)
          .where.not(policy_statuses: { code: TERMINAL_POLICY_STATUS_CODES })
          .count
  end

  def average_satisfaction
    values = SurveyResponse.pluck(:response_data).filter_map do |response_data|
      extract_preferred_value(response_data)
    end
    return 0.0 if values.empty?

    values.sum.to_f / values.size
  end

  def extract_preferred_value(response_data)
    hash = response_data.respond_to?(:to_h) ? response_data.to_h : {}
    preferred_keys = %w[satisfaction satisfaction_score rating score]

    preferred_keys.each do |key|
      value = extract_number(hash[key] || hash[key.to_sym])
      return value if value
    end

    nil
  end

  def extract_number(value)
    case value
    when Numeric
      value.to_f
    when String
      Float(value)
    else
      nil
    end
  rescue ArgumentError, TypeError
    nil
  end

  def todays_payout_orders_count
    Payout.where(decided_at: jst_today_range).count
  end

  def average_order_latency_minutes
    durations = Payout.joins(:observation)
                      .where.not(decided_at: nil)
                      .pluck(:decided_at, "observations.observed_at")
                      .filter_map do |decided_at, observed_at|
      next if decided_at.blank? || observed_at.blank?

      (decided_at - observed_at) / 60.0
    end

    return 0.0 if durations.empty?

    durations.sum.to_f / durations.size
  end

  def jst_today_range
    current_time_in_jst = Time.current.in_time_zone(JST_ZONE)
    current_time_in_jst.beginning_of_day..current_time_in_jst.end_of_day
  end
end
