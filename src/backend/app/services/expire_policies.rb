class ExpirePolicies
  Result = Struct.new(:updated_count, :status, keyword_init: true) do
    def success?
      status == :ok
    end
  end

  EXPIRABLE_POLICY_STATUS_CODES = %w[active cap_reached].freeze

  def self.call(now: Time.current)
    new(now: now).call
  end

  def initialize(now:)
    @now = now
  end

  def call
    updated_count = 0

    expirable_policies.find_each do |policy|
      policy.with_lock do
        next unless expirable_policy?(policy)

        policy.update!(policy_status: expired_status)
        updated_count += 1
      end
    end

    Result.new(updated_count: updated_count, status: :ok)
  end

  private

  attr_reader :now

  def expirable_policies
    Policy.joins(:policy_status)
          .where(policy_statuses: { code: EXPIRABLE_POLICY_STATUS_CODES })
          .where("policies.expires_at <= ?", now)
  end

  def expirable_policy?(policy)
    EXPIRABLE_POLICY_STATUS_CODES.include?(policy.policy_status.code) && policy.expires_at <= now
  end

  def expired_status
    @expired_status ||= PolicyStatus.find_by!(code: "expired")
  end
end
