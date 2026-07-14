class PayoutTier < LocalizedMasterRecord
  has_many :policies, dependent: :restrict_with_exception
  has_many :payouts, dependent: :restrict_with_exception

  validates :amount_yen, presence: true, numericality: { only_integer: true, greater_than: 0 }
end
