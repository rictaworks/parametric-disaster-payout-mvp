class User < ApplicationRecord
  has_many :policies, dependent: :destroy
  has_many :payouts, through: :policies
  has_many :notifications, dependent: :destroy
  has_many :survey_responses, dependent: :destroy

  validates :google_sub, presence: true, uniqueness: true
end
