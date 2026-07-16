class RainfallThresholdParser
  # フロントエンドの降雨プラン選択肢は "10 mm" のように単位付きで送信される。
  # 文字列全体をこの形式（数値のみ、または末尾に任意の空白+mm単位）に一致させ、
  # 数値部分だけをキャプチャする。数字が複数箇所に分断された入力（例: "1abc2 mm"）や
  # 指数表記（例: "10e3"）はこの形式に一致せず拒否される。
  # 整数部4桁・小数部2桁までに制限しているのは observations.max_value / rainfall_mm の
  # カラム精度（precision: 6, scale: 2）に合わせるためで、これにより
  # policies.threshold（varchar(255)）へ桁数無制限の値が保存されることも防げる。
  #
  # 契約作成（ValidateAndCreatePolicy）とトリガー判定（EvaluateTrigger）の両方で
  # 同一のロジックを使うことで、作成時に許容された旧形式（単位付き文字列など）が
  # 評価時にだけ解析不能になり支払が永久に生成されない、という不整合を防ぐ
  PATTERN = /\A(-?\d{1,4}(?:\.\d{1,2})?)(?:\s*mm)?\z/i

  def self.parse(raw_value)
    new(raw_value).parse
  end

  def initialize(raw_value)
    @raw_value = raw_value
  end

  def parse
    match = PATTERN.match(raw_value.to_s.strip)
    return nil if match.nil?

    value = BigDecimal(match[1])
    value.finite? && value.positive? ? value : nil
  rescue ArgumentError, TypeError
    nil
  end

  private

  attr_reader :raw_value
end
