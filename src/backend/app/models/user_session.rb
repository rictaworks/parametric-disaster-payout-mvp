class UserSession < ApplicationRecord
  belongs_to :user

  MAX_ACTIVE_SESSIONS_PER_USER = 10

  validates :token_digest, presence: true, uniqueness: true
  validates :expires_at, presence: true

  scope :active, -> { where(revoked_at: nil).where("expires_at > ?", Time.current) }

  def self.generate_for_user(user, expires_in: 30.days)
    raw_token = SecureRandom.hex(32)
    digest = Digest::SHA256.hexdigest(raw_token)

    session = user.with_lock do
      cleanup_expired_and_revoked_for(user)
      enforce_active_session_limit_for(user)

      user.user_sessions.create!(
        token_digest: digest,
        expires_at: expires_in.from_now
      )
    end

    [session, raw_token]
  end

  def self.cleanup_expired_and_revoked_for(user)
    user.user_sessions.where("expires_at <= ? OR revoked_at IS NOT NULL", Time.current).delete_all
  end

  def self.enforce_active_session_limit_for(user)
    active_sessions = user.user_sessions.active.order(created_at: :asc)
    overflow_count = active_sessions.count - (MAX_ACTIVE_SESSIONS_PER_USER - 1)
    if overflow_count > 0
      active_sessions.limit(overflow_count).destroy_all
    end
  end

  def self.find_active_by_token(raw_token)
    return nil if raw_token.blank?

    digest = Digest::SHA256.hexdigest(raw_token)
    active.find_by(token_digest: digest)
  end

  def revoke!
    update!(revoked_at: Time.current)
  end

  def active?
    revoked_at.nil? && expires_at > Time.current
  end
end
