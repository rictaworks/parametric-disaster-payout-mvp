class User < ApplicationRecord
  # config/locales/*.yml の7ファイルと対応させること
  SUPPORTED_LOCALES = %w[ja en fr zh ru es ar].freeze

  has_many :user_sessions, dependent: :destroy
  has_many :policies, dependent: :destroy
  has_many :payouts, through: :policies
  has_many :notifications, dependent: :destroy
  has_many :survey_responses, dependent: :destroy

  validates :google_sub, presence: true, uniqueness: true
  # if: spec/db/migrate/20260713213247_*_specがusersテーブルを本カラム追加前の
  # スキーマまで巻き戻して検証するため、その接続では:localeカラムが存在しない
  validates :locale, inclusion: { in: SUPPORTED_LOCALES }, if: -> { has_attribute?(:locale) }

  def internal_session_token
    _session, raw_token = UserSession.generate_for_user(self)
    raw_token
  end
end
