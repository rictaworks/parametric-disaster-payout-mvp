class ValidateAndCreatePolicy
  Result = Struct.new(:policy, :status, :error, :details, keyword_init: true) do
    def success?
      error.nil?
    end
  end

  def initialize(user:, plan_id:, station_id:, payout_tier_id:, threshold:, recaptcha_token:)
    @user = user
    @plan_id = plan_id
    @station_id = station_id
    @payout_tier_id = payout_tier_id
    @threshold = threshold
    @recaptcha_token = recaptcha_token
  end

  def call
    return failure(:bad_request, "recaptcha_failed") unless recaptcha_valid?

    masters = load_masters
    missing_masters = masters.select { |_, value| value.nil? }.keys
    return failure(:unprocessable_entity, "master_not_found", missing_masters) if missing_masters.any?

    return failure(:unprocessable_entity, "threshold_invalid") unless threshold_valid?(masters)

    policy, duplicate = create_policy_within_lock(masters)

    return failure(:conflict, "duplicate_policy") if duplicate
    return Result.new(policy: policy, status: :created) if policy.persisted?

    failure(:unprocessable_entity, "validation_failed", policy.errors.to_hash(true))
  rescue ActiveRecord::StatementInvalid, ActiveRecord::Deadlocked => e
    # ロック競合に関連する例外以外（外部キー違反、タイムアウト、SQLエラーなど）は
    # 再試行や409変換の対象外とし、直ちに再送出する
    unless lock_conflict_error?(e)
      raise e
    end

    # データベース例外が発生した際、競合相手（先行トランザクション）のコミット完了まで
    # 一定時間バックオフ（リトライ）しながら重複契約の存在を再確認する。
    max_attempts = 10
    sleep_duration = 0.1 # 100ms
    attempts = 0
    confirmed = false

    # HTTPリクエストではクエリキャッシュが有効なため、uncached を使用して
    # 先行トランザクションのコミット結果を常に最新のDB状態から読み取れるようにする
    ActiveRecord::Base.uncached do
      while attempts < max_attempts
        begin
          if masters && duplicate_policy_exists?(masters)
            confirmed = true
            break
          end
        rescue ActiveRecord::StatementInvalid, ActiveRecord::Deadlocked => read_error
          # 読み取り自体がロック競合で失敗した場合はリトライを継続する
          unless lock_conflict_error?(read_error)
            raise read_error
          end
        end

        attempts += 1
        sleep sleep_duration
      end
    end

    if confirmed
      Rails.logger.warn "Database lock/conflict occurred during policy creation. Duplicate policy confirmed after #{attempts} retries: #{e.message}"
      failure(:conflict, "duplicate_policy")
    else
      # 重複が確認できなかった場合は、他の要因（外部キー違反、構文エラーなど）による例外として再送出する
      raise e
    end
  end

  private

  attr_reader :user, :plan_id, :station_id, :payout_tier_id, :threshold, :recaptcha_token

  def recaptcha_valid?
    RecaptchaVerifier.new.valid?(recaptcha_token)
  end

  def load_masters
    {
      plan: Plan.find_by(id: plan_id),
      station: Station.find_by(id: station_id),
      payout_tier: PayoutTier.find_by(id: payout_tier_id),
      pending_status: PolicyStatus.find_by(code: "pending"),
      active_status: PolicyStatus.find_by(code: "active"),
      processing_status: PolicyStatus.find_by(code: "processing")
    }
  end

  def threshold_valid?(masters)
    case masters.fetch(:plan).trigger_type
    when "seismic"
      SeismicIntensityLevel.exists?(label_ja: threshold)
    when "rainfall"
      normalized_rainfall_threshold.present?
    else
      true
    end
  end

  # 検証を通過した値はそのまま Policy#threshold に保存する。RainfallThresholdParser は
  # evaluate_trigger.rb でも同じ解析ロジックとして使われるため、ここで正規化した数値文字列は
  # 評価時にも問題なく解析できる
  def normalized_rainfall_threshold
    return @normalized_rainfall_threshold if defined?(@normalized_rainfall_threshold)

    value = RainfallThresholdParser.parse(threshold)
    @normalized_rainfall_threshold = value&.to_s("F")
  end

  def create_policy_within_lock(masters)
    policy = nil
    duplicate = false

    ActiveRecord::Base.transaction do
      user.lock!

      if duplicate_policy_exists?(masters)
        duplicate = true
        raise ActiveRecord::Rollback
      end

      policy = Policy.new(
        user: user,
        plan: masters.fetch(:plan),
        station: masters.fetch(:station),
        payout_tier: masters.fetch(:payout_tier),
        policy_status: masters.fetch(:pending_status),
        threshold: policy_threshold(masters)
      )
      policy.save
    end

    [ policy, duplicate ]
  end

  def policy_threshold(masters)
    masters.fetch(:plan).trigger_type == "rainfall" ? normalized_rainfall_threshold : threshold
  end

  def duplicate_policy_exists?(masters)
    Policy.joins(:plan).where(
      user_id: user.id,
      plans: { trigger_type: masters.fetch(:plan).trigger_type },
      policy_status_id: [
        masters.fetch(:pending_status),
        masters.fetch(:active_status),
        masters.fetch(:processing_status)
      ].compact.map(&:id)
    ).exists?
  end

  def failure(status, error, details = nil)
    Result.new(status: status, error: error, details: details)
  end

  def lock_conflict_error?(error)
    return true if error.is_a?(ActiveRecord::Deadlocked)
    return true if defined?(ActiveRecord::LockWaitTimeout) && error.is_a?(ActiveRecord::LockWaitTimeout)

    cause = error.cause
    if cause
      return true if defined?(SQLite3::BusyException) && cause.is_a?(SQLite3::BusyException)
      return true if defined?(SQLite3::LockedException) && cause.is_a?(SQLite3::LockedException)
    end

    false
  end
end
