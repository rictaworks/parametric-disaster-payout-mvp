class ValidateAndCreatePolicy
  Result = Struct.new(:success, :policy, :error, :code, keyword_init: true)

  ACTIVE_POLICY_CODES = %w[waiting active processing capped].freeze

  def self.call(...)
    new(...).call
  end

  def initialize(user_id:, plan_id:, station_id:, threshold:, payout_tier_id:, recaptcha_token:, age_group: nil)
    @user_id = user_id
    @plan_id = plan_id
    @station_id = station_id
    @threshold = threshold
    @payout_tier_id = payout_tier_id
    @recaptcha_token = recaptcha_token
    @age_group = age_group.presence
  end

  def call
    return failure('reCAPTCHA verification failed', :unprocessable_entity) unless recaptcha_valid?

    plan = Plan.find_by(id: @plan_id)
    station = Station.find_by(id: @station_id)
    payout_tier = PayoutTier.find_by(id: @payout_tier_id)
    waiting_status = PolicyStatus.find_by!(code: 'waiting')

    return failure('Plan not found', :unprocessable_entity) unless plan
    return failure('Station not found', :unprocessable_entity) unless station
    return failure('Payout tier not found', :unprocessable_entity) unless payout_tier
    return failure('Station does not match plan', :unprocessable_entity) unless station.plan_type == plan.plan_type

    duplicate = Policy.joins(:policy_status)
                      .where(user_id: @user_id, plan_id: plan.id, policy_statuses: { code: ACTIVE_POLICY_CODES })
                      .exists?
    return failure('同一プランで有効な契約がすでに存在します', :conflict) if duplicate

    policy = Policy.create!(
      user_id: @user_id,
      plan: plan,
      station: station,
      payout_tier: payout_tier,
      policy_status: waiting_status,
      threshold: @threshold,
      age_group: @age_group,
      waiting_until: 72.hours.from_now,
      expires_at: 1.year.from_now
    )

    { success: true, policy: policy }
  end

  private

  def recaptcha_valid?
    return true if Rails.env.development? || Rails.env.test?
    return false if @recaptcha_token.blank?

    response = HTTParty.post(
      'https://www.google.com/recaptcha/api/siteverify',
      body: {
        secret: ENV['RECAPTCHA_SECRET_KEY'],
        response: @recaptcha_token
      }
    )

    response.parsed_response['success'] == true
  rescue StandardError
    false
  end

  def failure(error, code)
    { success: false, error: error, code: code }
  end
end
