class PolicyStatus < ApplicationRecord
  has_many :policies, dependent: :restrict_with_exception

  validates :code, presence: true, uniqueness: true
end
