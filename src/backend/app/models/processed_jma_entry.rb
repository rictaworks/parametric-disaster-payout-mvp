class ProcessedJmaEntry < ApplicationRecord
  validates :entry_id, presence: true, uniqueness: true
end
