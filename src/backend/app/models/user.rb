class User < ApplicationRecord
  has_many :policies, dependent: :restrict_with_exception

  validates :google_sub, presence: true, uniqueness: true
end
