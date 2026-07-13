class Station < LocalizedMasterRecord
  MEASUREMENT_TYPES = %w[seismic rainfall].freeze

  has_many :observations, dependent: :restrict_with_exception

  validates :measurement_type, presence: true, inclusion: { in: MEASUREMENT_TYPES }
end
