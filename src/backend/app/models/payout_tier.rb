class PayoutTier < ApplicationRecord
  has_many :policies, dependent: :restrict_with_exception

  validates :code, :amount_jpy, presence: true
  validates :code, uniqueness: true

  def localized_label(locale)
    value = self["label_#{locale}"]
    value.presence || label_en.presence || label_ja
  end
end
