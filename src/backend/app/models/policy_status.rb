class PolicyStatus < ApplicationRecord
  has_many :policies

  WAITING    = "waiting"
  ACTIVE     = "active"
  PROCESSING = "processing"
  CAP_REACHED = "cap_reached"
  CANCELLED  = "cancelled"
  LAPSED     = "lapsed"

  validates :code, presence: true, uniqueness: true
end
