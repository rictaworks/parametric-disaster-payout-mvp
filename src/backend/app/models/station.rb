class Station < ApplicationRecord
  has_many :observations
  has_many :policies

  validates :code, presence: true, uniqueness: true
  validates :name, :prefecture, presence: true
end
