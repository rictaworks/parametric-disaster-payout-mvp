class User < ApplicationRecord
  has_many :policies
  has_many :notifications

  validates :google_sub, presence: true, uniqueness: true
end
