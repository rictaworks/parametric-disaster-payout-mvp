require "bigdecimal"

class FixRainfallObservationThresholds < ActiveRecord::Migration[7.2]
  # 一時的なActiveRecordクラス定義（マイグレーション安全性のため）
  class Policy < ActiveRecord::Base; end
  class Station < ActiveRecord::Base; end
  class Observation < ActiveRecord::Base; end
  class Payout < ActiveRecord::Base; end
  class Notification < ActiveRecord::Base; end
  class SurveyResponse < ActiveRecord::Base; end
  class LegacyPayout < ActiveRecord::Base
    self.table_name = 'legacy_payouts'
  end
  class LegacySurveyResponse < ActiveRecord::Base
    self.table_name = 'legacy_survey_responses'
  end

  def up
    Policy.reset_column_information
    Station.reset_column_information
    Observation.reset_column_information
    Payout.reset_column_information
    Notification.reset_column_information
    SurveyResponse.reset_column_information
    LegacyPayout.reset_column_information
    LegacySurveyResponse.reset_column_information

    # Payout を観測（observation_id）単位で集約して処理する
    Payout.all.to_a.group_by(&:observation_id).each do |obs_id, payouts|
      obs = Observation.find_by(id: obs_id)
      next if obs.nil?
      next unless obs.simulated

      station = Station.find_by(id: obs.station_id)
      next if station.nil? || station.measurement_type != "rainfall"

      resolved = []

      payouts.each do |payout|
        policy = Policy.find_by(id: payout.policy_id)
        if policy.nil?
          isolate_payout(payout, "Associated policy with ID #{payout.policy_id} not found")
          next
        end

        begin
          val = resolve_rainfall_threshold_mm!(policy)
          resolved << { payout: payout, threshold: val }
        rescue => e
          isolate_payout(payout, e.message)
        end
      end

      next if resolved.empty?

      unique_vals = resolved.map { |r| r[:threshold] }.uniq

      if unique_vals.size == 1
        # すべての関連契約で閾値が一意に決定できる場合は、その値で観測レコードを更新する
        obs.update_columns(rainfall_mm: unique_vals.first)
      else
        # 閾値が異なる複数契約が同一の模擬観測を共有している（一意に決定できない）場合、
        # 監査データの不整合を防ぐため、対象 of Payout をすべて隔離退避する
        resolved.each do |r|
          isolate_payout(r[:payout], "Ambiguous threshold resolution: multiple sharing policies have conflicting thresholds: #{unique_vals.join(', ')} mm")
        end
      end
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private

  def isolate_payout(payout, reason)
    # 外部キー制約で payout.destroy が失敗しないよう、紐づくアンケート回答を
    # 先に legacy_survey_responses へ退避してから削除する
    survey_response = SurveyResponse.find_by(payout_id: payout.id)
    if survey_response
      isolate_survey_response(survey_response, payout, "Associated payout #{payout.id} was isolated during rainfall threshold backfill: #{reason}")
    end

    LegacyPayout.create!(
      policy_id: payout.policy_id,
      payout_tier_id: payout.payout_tier_id,
      payout_status_id: payout.payout_status_id,
      observation_id: payout.observation_id,
      idempotency_key: payout.idempotency_key,
      decided_at: payout.decided_at,
      isolation_reason: reason,
      legacy_created_at: payout.created_at
    )
    Notification.where(payout_id: payout.id).update_all(payout_id: nil)
    payout.destroy
  end

  def isolate_survey_response(resp, payout, reason)
    LegacySurveyResponse.create!(
      user_id: resp.user_id,
      policy_id: payout.policy_id,
      response_data: resp.response_data,
      legacy_created_at: resp.created_at,
      isolation_reason: reason
    )
    resp.destroy
  end

  def resolve_rainfall_threshold_mm!(policy)
    # 前後の空白・タブを除去してから単位表記（"mm-h", "mm", "mm/h", "mm/1h", "mm_h" など、
    # 大文字小文字問わず）を除去する。単位除去後にも再度 strip し、
    # 数値と単位の間に空白が挟まっていても解決できるようにする
    normalized = policy.threshold.to_s.strip.gsub(/(?:mm-h|mm\/1h|mm\/h|mm_h|mm)\s*\z/i, '').strip
    BigDecimal(normalized)
  rescue ArgumentError, TypeError
    raise "Migration blocked: Cannot resolve rainfall threshold for Policy #{policy.id} threshold '#{policy.threshold}'."
  end
end
