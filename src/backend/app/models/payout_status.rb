class PayoutStatus < ApplicationRecord
  validates :code, presence: true, uniqueness: true
end
