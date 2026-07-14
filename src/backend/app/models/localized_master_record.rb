class LocalizedMasterRecord < ApplicationRecord
  self.abstract_class = true

  LABEL_COLUMNS = %i[
    label_ja
    label_en
    label_fr
    label_zh
    label_ru
    label_es
    label_ar
  ].freeze

  LABEL_ATTRIBUTE_BY_LOCALE = {
    "ja" => :label_ja,
    "en" => :label_en,
    "fr" => :label_fr,
    "zh" => :label_zh,
    "ru" => :label_ru,
    "es" => :label_es,
    "ar" => :label_ar
  }.freeze

  validates :code, presence: true, uniqueness: true
  validates(*LABEL_COLUMNS, presence: true)

  def localized_label(locale = I18n.locale)
    public_send(LABEL_ATTRIBUTE_BY_LOCALE.fetch(locale.to_s, :label_ja))
  end
end
