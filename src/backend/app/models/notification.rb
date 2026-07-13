class Notification < ApplicationRecord
  TYPES = %w[payout_created payout_completed survey_request limit_reached].freeze

  belongs_to :user
  belongs_to :policy, optional: true
  belongs_to :payout, optional: true

  validates :notification_type, presence: true, inclusion: { in: TYPES }
  validates :body, presence: true

  scope :unread, -> { where(read_at: nil) }

  def read?
    read_at.present?
  end

  def mark_as_read!
    update!(read_at: Time.current)
  end
end
