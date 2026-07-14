class Plan < LocalizedMasterRecord
  TRIGGER_TYPES = %w[seismic rainfall].freeze

  has_many :policies, dependent: :restrict_with_exception

  validates :trigger_type, presence: true, inclusion: { in: TRIGGER_TYPES }
end
