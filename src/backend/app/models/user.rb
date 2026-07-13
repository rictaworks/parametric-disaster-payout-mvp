class User < ApplicationRecord
  has_many :policies
  has_many :notifications
  has_many :survey_responses

  validates :google_sub, presence: true, uniqueness: true
end
