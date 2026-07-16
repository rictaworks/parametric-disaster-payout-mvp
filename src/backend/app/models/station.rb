class Station < LocalizedMasterRecord
  MEASUREMENT_TYPES = %w[seismic rainfall].freeze

  has_many :observations, dependent: :restrict_with_exception

  before_validation :normalize_blank_jma_code

  validates :measurement_type, presence: true, inclusion: { in: MEASUREMENT_TYPES }
  validates :jma_code, uniqueness: { allow_blank: true }, if: -> { self.class.column_names.include?("jma_code") }

  private

  def normalize_blank_jma_code
    return unless self.class.column_names.include?("jma_code")
    self.jma_code = nil if jma_code.blank?
  end
end
