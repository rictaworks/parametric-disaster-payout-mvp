class UpdateStage1DomainModelsForReviewComments < ActiveRecord::Migration[7.2]
  # 一時的なActiveRecordクラス定義（マイグレーション安全性のため）
  class Policy < ActiveRecord::Base; end
  class Plan < ActiveRecord::Base; end
  class Station < ActiveRecord::Base; end
  class Observation < ActiveRecord::Base; end
  class Payout < ActiveRecord::Base; end
  class SurveyResponse < ActiveRecord::Base; end
  class SeismicIntensityLevel < ActiveRecord::Base; end
  class PolicyStatus < ActiveRecord::Base; end
  class LegacySurveyResponse < ActiveRecord::Base
    self.table_name = 'legacy_survey_responses'
  end

  def up
    # 1. policies へのカラム追加（旧ポリシー互換性のため nullable のまま移行完了させる）
    add_reference :policies, :station, null: true, foreign_key: true
    add_column :policies, :waiting_until, :datetime, null: true
    add_column :policies, :terminated_at, :datetime

    # 2. observations へのカラム追加（event_id, simulated）
    add_column :observations, :event_id, :string
    add_column :observations, :simulated, :boolean, null: false, default: false

    # 3. survey_responses への payout_id 追加（最初は nullable）
    add_reference :survey_responses, :payout, null: true, foreign_key: true

    # 4. 移行不能なアンケート回答の隔離用アーカイブテーブルの作成
    create_table :legacy_survey_responses do |t|
      t.integer :user_id, null: false
      t.integer :policy_id
      t.json :response_data, null: false, default: {}
      t.datetime :legacy_created_at
      t.string :migration_error_reason
      t.timestamps
    end

    # --- バックフィルデータ移行処理 ---

    Policy.reset_column_information
    Plan.reset_column_information
    Station.reset_column_information
    Observation.reset_column_information
    Payout.reset_column_information
    SurveyResponse.reset_column_information
    PolicyStatus.reset_column_information

    # フォールバック用レコードの遅延作成定義（必要となったときのみ実行）
    get_or_create_seismic_station = -> {
      Station.find_by(code: "temp_seismic_migration") || Station.create!(
        code: "temp_seismic_migration", measurement_type: "seismic",
        label_ja: "temp", label_en: "temp", label_fr: "temp", label_zh: "temp", label_ru: "temp", label_es: "temp", label_ar: "temp"
      )
    }

    get_or_create_rainfall_station = -> {
      Station.find_by(code: "temp_rainfall_migration") || Station.create!(
        code: "temp_rainfall_migration", measurement_type: "rainfall",
        label_ja: "temp", label_en: "temp", label_fr: "temp", label_zh: "temp", label_ru: "temp", label_es: "temp", label_ar: "temp"
      )
    }

    # A. Policy のバックフィル (station_id と waiting_until)
    # 支払が参照する観測点（実データ上の支払根拠）を優先決定し、特定不能・複数ある契約は nil として継続移行する
    # 設定前に、プランの種別と観測点種別が一致しているか厳密に照合し、不一致データは移行を停止して整合性を保証
    Policy.find_each do |policy|
      obs_station_ids = Observation.where(policy_id: policy.id).pluck(:station_id).uniq

      # 支払（Payout）が参照する観測点の station_id を抽出
      payouts = Payout.where(policy_id: policy.id).to_a
      payout_station_ids = payouts.map do |p|
        obs = Observation.find_by(id: p.observation_id)
        obs&.station_id
      end.compact.uniq

      candidate_station_ids = if payout_station_ids.size == 1
                               payout_station_ids
      elsif payout_station_ids.size > 1
                               raise "Policy #{policy.id} has payouts referencing multiple stations (#{payout_station_ids.join(', ')}). Cannot backfill station_id unambiguously."
      else
                               obs_station_ids
      end

      # プラン種別と観測点種別の照合
      plan = Plan.find_by(id: policy.plan_id)
      matched_station_ids = candidate_station_ids.select do |sid|
        st = Station.find_by(id: sid)
        st && plan && st.measurement_type == plan.trigger_type
      end

      # 支払（Payout）がすでに存在しているのに、その支払が参照する観測点がプラン種別と不一致の場合は不整合例外
      if payout_station_ids.present? && matched_station_ids.empty?
        raise "Data corruption: Policy #{policy.id} has payouts referencing stations (#{payout_station_ids.join(', ')}) whose measurement type does not match plan trigger type '#{plan&.trigger_type}'."
      end

      # 複数候補が存在する場合や、特定不能な場合は例外にせず nil (レガシー契約) として安全に継続移行
      station_id = if matched_station_ids.size == 1
                     matched_station_ids.first
      else
                     nil
      end

      # 既存の支払との互換調整が必要な場合だけ、その支払が参照する観測日時（または支払作成日時）を基準にする。
      # 支払実績の無いポリシーに関しては、たとえ免責期間中に通常観測があっても、一律で created_at + 72.hours を維持する。
      first_observed_at = if payouts.present?
                            payouts.map { |p| Observation.find_by(id: p.observation_id)&.observed_at }.compact.min
      end
      first_payout_created_at = payouts.map(&:created_at).compact.min
      reference_time = [ first_observed_at, first_payout_created_at ].compact.min

      waiting_until = if reference_time
                        [ policy.created_at + 72.hours, reference_time - 1.second ].min
      else
                        policy.created_at + 72.hours
      end

      policy.update_columns(
        station_id: station_id,
        waiting_until: waiting_until
      )
    end

    # B. 重複する降雨観測データの統合 (station_id & observed_at)
    # 空文字 "" は正規化して一意制約の重複対象にする
    rainfall_station_ids = Station.where(measurement_type: "rainfall").pluck(:id)
    Observation.where(station_id: rainfall_station_ids, event_id: "").update_all(event_id: nil)

    rainfall_obs = Observation.where(station_id: rainfall_station_ids).to_a
    grouped_obs = rainfall_obs.group_by { |o| [ o.station_id, o.observed_at ] }

    grouped_obs.each do |(station_id, observed_at), records|
      next if records.size <= 1

      unique_rainfall_values = records.map(&:rainfall_mm).uniq
      if unique_rainfall_values.size > 1
        raise "Conflicting duplicate rainfall values found at station #{station_id} at #{observed_at}: #{unique_rainfall_values.join(', ')}mm. Cannot merge unambiguously."
      end

      # 代表レコードを決定（IDが最小のもの）
      representative = records.min_by(&:id)
      duplicates = records - [ representative ]
      duplicate_ids = duplicates.map(&:id)

      # 関連する Payout の observation_id を代表レコードへ付け替える
      Payout.where(observation_id: duplicate_ids).update_all(observation_id: representative.id)

      # 重複レコードを削除する
      Observation.where(id: duplicate_ids).delete_all
    end

    # C. 重複する地震観測データの統合 (station_id & observed_at) と event_id バックフィル
    seismic_station_ids = Station.where(measurement_type: "seismic").pluck(:id)
    seismic_obs = Observation.where(station_id: seismic_station_ids).to_a
    grouped_seismic = seismic_obs.group_by { |o| [ o.station_id, o.observed_at ] }

    grouped_seismic.each do |(station_id, observed_at), records|
      next if records.size <= 1

      # 震度レベルが全て一致しているか確認。一致しない場合はデータ完全性が崩れているため例外
      levels = records.map(&:seismic_intensity_level_id).uniq
      if levels.size > 1
        raise "Data corruption: Multiple seismic observations found at station #{station_id} at #{observed_at} with conflicting intensity levels: #{levels.join(', ')}"
      end

      representative = records.min_by(&:id)
      duplicates = records - [ representative ]
      duplicate_ids = duplicates.map(&:id)

      # 関連する Payout の observation_id を代表レコードへ付け替える
      Payout.where(observation_id: duplicate_ids).update_all(observation_id: representative.id)

      # 重複レコードを削除する
      Observation.where(id: duplicate_ids).delete_all
    end

    # 統合後に、残った各地震観測に対して一意なイベントIDを設定
    Observation.where(station_id: seismic_station_ids).find_each do |obs|
      obs.update_columns(event_id: "legacy-event-#{obs.id}")
    end

    # D. 既存支払の観測点整合性の検証 (全支払の走査)
    # 支払と契約の支払額区分（payout_tier_id）が不一致なデータは、契約側に安全に統一補正する
    Payout.find_each do |payout|
      policy = Policy.find_by(id: payout.policy_id)
      next if policy.nil?

      if payout.payout_tier_id != policy.payout_tier_id
        payout.update_columns(payout_tier_id: policy.payout_tier_id)
      end
    end

    Payout.where.not(observation_id: nil).find_each do |payout|
      policy = Policy.find_by(id: payout.policy_id)
      obs = Observation.find_by(id: payout.observation_id)
      if policy && obs && obs.station_id != policy.station_id
        raise "Data corruption detected: Payout #{payout.id} has observation station #{obs.station_id} which does not match policy station #{policy.station_id}. Migration aborted."
      end
    end

    # E. Payout のバックフィル (observation_id が NULL の既存支払)
    # 新しい観測レコードを追加する際、既存の同一キー（station_id & observed_at）の観測が存在すれば再利用し、重複を防ぐ
    Payout.where(observation_id: nil).find_each do |payout|
      policy = Policy.find_by(id: payout.policy_id)
      if policy.nil?
        payout.destroy
        next
      end

      # 観測履歴のない契約に支払がある場合、プランから特定したダミーの移行用観測点をバックフィルする
      if policy.station_id.nil?
        plan = Plan.find_by(id: policy.plan_id)
        station = (plan&.trigger_type == "seismic" ? get_or_create_seismic_station.call : get_or_create_rainfall_station.call)
        policy.update_columns(station_id: station.id)
      end

      station = Station.find(policy.station_id)

      # 既に同一観測点・同時刻の降雨観測（event_id: nil）が存在するか確認して再利用
      existing_obs = Observation.find_by(station_id: station.id, observed_at: payout.created_at, event_id: nil)

      if existing_obs
        payout.update_columns(observation_id: existing_obs.id)
      else
        obs_attrs = {
          station_id: station.id,
          observed_at: payout.created_at,
          simulated: true
        }

        if station.measurement_type == "seismic"
          level = SeismicIntensityLevel.first || SeismicIntensityLevel.create!(
            code: "temp_level_migration", sort_order: 99,
            label_ja: "temp", label_en: "temp", label_fr: "temp", label_zh: "temp", label_ru: "temp", label_es: "temp", label_ar: "temp"
          )
          obs_attrs[:seismic_intensity_level_id] = level.id
          obs_attrs[:event_id] = "legacy-event-payout-#{payout.id}"
        else
          obs_attrs[:rainfall_mm] = 0.0
        end

        observation = Observation.create!(obs_attrs)
        payout.update_columns(observation_id: observation.id)
      end
    end

    # F. SurveyResponse のバックフィル (payout_id) & 隔離
    SurveyResponse.all.to_a.group_by { |r| r.read_attribute(:policy_id) }.each do |policy_id, responses|
      if policy_id.nil?
        responses.each do |resp|
          isolate_survey_response(resp, "policy_id is NULL")
        end
        next
      end

      policy = Policy.find_by(id: policy_id)
      if policy.nil?
        responses.each do |resp|
          isolate_survey_response(resp, "Associated policy with ID #{policy_id} not found")
        end
        next
      end

      payouts = Payout.where(policy_id: policy_id).to_a

      # 同一契約に複数の支払がある場合、回答が一意に特定できないため安全に隔離
      if payouts.size > 1
        responses.each do |resp|
          isolate_survey_response(resp, "Ambiguous mapping: Multiple payouts (#{payouts.size}) exist for policy #{policy_id}")
        end
        next
      end

      payout = payouts.first

      if payout.nil?
        responses.each do |resp|
          isolate_survey_response(resp, "No matching payout available (policy_id: #{policy_id})")
        end
        next
      end

      # 同一支払に対し、重複したアンケートが存在する場合も一意制約を満たせないため隔離
      if responses.size > 1
        responses.each do |resp|
          isolate_survey_response(resp, "Duplicate survey responses for a single payout")
        end
        next
      end

      resp = responses.first

      # 所有者整合性の検証
      if resp.user_id != policy.user_id
        isolate_survey_response(resp, "Owner mismatch: response user_id=#{resp.user_id}, policy user_id=#{policy.user_id}")
      else
        resp.update_columns(payout_id: payout.id)
      end
    end

    # --- 制約の適用とクリーンアップ ---

    # 注意: Policy の station_id と waiting_until は旧レガシー契約の nullable 互換性を保つため NOT NULL に変更しない。
    # 新規作成されるポリシーに対しては、モデルレベルで station_id と waiting_until を必須に検証している。

    # Observation のインデックス追加
    add_index :observations, [ :station_id, :event_id ], unique: true, name: 'idx_obs_station_event', where: "event_id IS NOT NULL"
    add_index :observations, [ :station_id, :observed_at ], unique: true, name: 'idx_obs_station_observed', where: "event_id IS NULL"

    # Observation の policy_id 関連を削除
    remove_reference :observations, :policy, foreign_key: true

    # Payout の NOT NULL 制約
    change_column_null :payouts, :observation_id, false

    # SurveyResponse の NOT NULL 化、一意インデックス追加、旧参照削除
    change_column_null :survey_responses, :payout_id, false
    add_index :survey_responses, :payout_id, unique: true, name: 'idx_survey_responses_payout'
    remove_reference :survey_responses, :policy, foreign_key: true
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private

  # 不整合データを消去せず、隔離・退避テーブルへ格納する
  def isolate_survey_response(resp, reason)
    LegacySurveyResponse.create!(
      user_id: resp.user_id,
      policy_id: resp.read_attribute(:policy_id),
      response_data: resp.read_attribute(:response_data),
      legacy_created_at: resp.created_at,
      migration_error_reason: reason
    )
    resp.destroy
  end
end
