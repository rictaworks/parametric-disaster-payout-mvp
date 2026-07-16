class Notification < ApplicationRecord
  KIND_PAYOUT_ORDERED = "payout_ordered".freeze
  KIND_PAYOUT_COMPLETED = "payout_completed".freeze
  KIND_SURVEY_REQUEST = "survey_request".freeze

  belongs_to :user
  belongs_to :policy, optional: true
  belongs_to :payout, optional: true

  validates :kind, presence: true
  validates :message, presence: true
end
