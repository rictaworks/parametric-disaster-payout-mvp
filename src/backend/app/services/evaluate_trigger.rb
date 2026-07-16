class EvaluateTrigger
  Result = Struct.new(:payouts, :status, keyword_init: true)

  TERMINAL_POLICY_STATUS_CODES = %w[cancelled expired].freeze

  def self.call(observation)
    new(observation).call
  end

  def initialize(observation)
    @observation = observation
  end

  def call
    return Result.new(payouts: [], status: :ignored) if observation.nil? || observation.max_value.nil?

    payouts = []

    # 同一観測点・同一プラン種別のポリシーを抽出する。
    # 契約状態による事前絞り込みは行わない。有効性は (1)(2) の発生時刻チェックのみで判定するため
    # （F3仕様：解約・失効前＝発生時刻が終端時刻より前）。取込遅延により観測処理が
    # 契約の解約・失効後にずれ込んでも、有効期間中に発生した正当なイベントを見逃さないようにする
    policies = Policy.joins(:plan)
                     .where(station_id: observation.station_id, plans: { trigger_type: observation.station.measurement_type })

    policies.find_each do |policy|
      ActiveRecord::Base.transaction do
        policy.lock!

        # (1) イベント発生時刻が契約の免責明け時刻以降か
        next unless observation.observed_at >= policy.waiting_until

        # (2) イベント発生時刻が契約有効期間内（解約・失効前）か
        next unless observation.observed_at <= policy.expires_at
        next if policy.terminated_at.present? && observation.observed_at > policy.terminated_at

        # (3) 当該（契約×イベント）の支払が未発生か
        idempotency_key = generate_idempotency_key(policy)
        next if Payout.exists?(idempotency_key: idempotency_key)

        # (4) 年間支払回数が上限（2回）未満か
        next unless annual_payout_count_ok?(policy)

        # (5) 最大観測値≧契約閾値か
        next unless threshold_reached?(policy)

        # 全条件成立：支払指図を生成
        payout = Payout.create!(
          policy: policy,
          payout_tier: policy.payout_tier,
          payout_status: PayoutStatus.find_by!(code: "ordered"),
          observation: observation,
          idempotency_key: idempotency_key,
          decided_at: Time.current
        )

        # 契約状態を支払処理中(processing)に更新する。ただし契約が既に解約・失効している場合は
        # （取込遅延により発生時刻より後に状態変更されていた場合）、その終端状態を上書きしない
        unless TERMINAL_POLICY_STATUS_CODES.include?(policy.policy_status.code)
          processing_status = PolicyStatus.find_by!(code: "processing")
          policy.update!(policy_status: processing_status)
        end

        # F4仕様：支払指図の生成と同時に契約者へアプリ内通知を送る（メール等は使用しない）。
        # Payout・契約状態更新と同一トランザクション内で作成し、通知の欠落を防ぐ
        Notification.create!(
          user: policy.user,
          policy: policy,
          payout: payout,
          kind: Notification::KIND_PAYOUT_ORDERED,
          message: I18n.t("notifications.payout_ordered")
        )

        payouts << payout
      end
    rescue ActiveRecord::RecordNotUnique
      # 並行処理で同一の idempotency_key の Payout が既に作成された場合は無視して次に進む
      next
    end

    Result.new(payouts: payouts, status: :success)
  end

  private

  attr_reader :observation

  def generate_idempotency_key(policy)
    if observation.station.measurement_type == "seismic"
      # event_id は気象庁側の発番でカラム長（varchar(255)）まで許容されうるため、そのまま
      # 連結すると policies.idempotency_key（同じく varchar(255)）の上限を超えうる。
      # 固定長のSHA256ダイジェストに変換することで、衝突耐性を保ちつつ長さを確定させる
      "policy_#{policy.id}_event_#{Digest::SHA256.hexdigest(observation.event_id)}"
    else
      # observed_at.iso8601 は秒未満を切り捨てるため、同一秒内に複数の降雨観測が
      # 存在する場合にキーが衝突しうる。observation.id は当該レコードを一意に指すため、
      # 続報による同一レコードの更新でも同じキーを保ちつつ衝突を避けられる
      "policy_#{policy.id}_observed_#{observation.id}"
    end
  end

  def annual_payout_count_ok?(policy)
    year = observation.observed_at.year
    start_of_year = Time.zone.local(year, 1, 1).beginning_of_day
    end_of_year = Time.zone.local(year, 12, 31).end_of_day

    invalid_status = PayoutStatus.find_by(code: "invalid")
    payout_count = policy.payouts
                         .joins(:observation)
                         .where(observations: { observed_at: start_of_year..end_of_year })
                         .where.not(payout_status: invalid_status)
                         .count
    payout_count < 2
  end

  def threshold_reached?(policy)
    if observation.station.measurement_type == "seismic"
      threshold_level = SeismicIntensityLevel.find_by(label_ja: policy.threshold)
      return false if threshold_level.nil?

      observation.max_value >= threshold_level.sort_order
    else
      threshold_value = parse_rainfall_threshold(policy)
      return false if threshold_value.nil?

      observation.max_value >= threshold_value
    end
  end

  # 契約作成時（ValidateAndCreatePolicy）と同じ RainfallThresholdParser を使うことで、
  # 単位付きの旧形式（"10 mm" 等）が保存された既存契約も評価時に正しく解析できるようにする。
  # それでも解析できない不正データ（非数値・0以下・桁数超過）は当該契約のみスキップし、
  # ジョブ全体を止めない
  def parse_rainfall_threshold(policy)
    value = RainfallThresholdParser.parse(policy.threshold)
    return value if value

    Rails.logger.error(
      "[EvaluateTrigger] policy_id=#{policy.id} の降雨閾値が不正な値です: #{policy.threshold.inspect}"
    )
    nil
  end
end
