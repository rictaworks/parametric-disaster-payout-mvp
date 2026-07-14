class PayoutStatus < LocalizedMasterRecord
  has_many :payouts, dependent: :restrict_with_exception

  validates :sort_order, presence: true, uniqueness: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
