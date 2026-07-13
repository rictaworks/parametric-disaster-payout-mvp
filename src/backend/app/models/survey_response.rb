class SurveyResponse < ApplicationRecord
  belongs_to :user
  belongs_to :policy, optional: true

  validates :response_data, presence: true
end
