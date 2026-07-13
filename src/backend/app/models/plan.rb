class Plan < ApplicationRecord
  has_many :policies

  validates :code, presence: true, uniqueness: true
  validates :plan_type, presence: true, inclusion: { in: %w[seismic rainfall] }
end
