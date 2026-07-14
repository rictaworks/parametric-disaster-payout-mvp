class Notification < ApplicationRecord
  belongs_to :user
  belongs_to :policy, optional: true
  belongs_to :payout, optional: true

  validates :kind, presence: true
  validates :message, presence: true
end
