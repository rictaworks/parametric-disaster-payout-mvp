class Notification < ApplicationRecord
  belongs_to :user
  belongs_to :policy, optional: true
  belongs_to :payout, optional: true

  validates :message, presence: true
end
