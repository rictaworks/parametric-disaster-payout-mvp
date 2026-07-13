class PayoutTier < ApplicationRecord
  has_many :policies

  validates :code, presence: true, uniqueness: true
  validates :amount_yen, presence: true, numericality: { only_integer: true, greater_than: 0 }
end
