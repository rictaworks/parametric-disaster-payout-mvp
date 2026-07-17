# PR #48「観測取込コアロジックを追加し、最大値更新と履歴保存を分離」
#
# 対象は F2 ingestObservationEvent の実装である IngestObservationEvent
# （src/backend/app/services/ingest_observation_event.rb）と、それに付随して
# 変更された Observation / ObservationEvent モデル（src/backend/app/models/）。
#
# PR本文の「非エンジニア向けユーザーテスト手順」（bin/rails runner を使った4手順）を、
# 開発サーバーと同じ Rails 環境（テストDB）上で自動テストとして再現する。
#   手順1: 新しい観測データを投入する（震度4の地震が発生した想定） -> "手順1"
#   手順2: 続報で震度がさらに強く（5弱に）修正された場合           -> "手順2"
#   手順3: 続報で震度が手順1の値まで下方修正された場合             -> "手順3"
#   手順4: 存在しない観測点にデータを送った場合（無視される）       -> "手順4"
#
# あわせて、PR本文が「レビューで指摘を受け追加コミットで修正した」と説明している
# 以下の3点も、独立した観点から再検証する。
#   fix1: 同時取込（レース条件）でも大きい方の観測値が消えない（条件付きUPDATE）
#   fix2: 再判定ジョブ（ObservationReevaluationJob）は「更新・新規作成時のみ」キューへ
#         投入され、「下方修正で最大値が変わらない場合」は投入されない
#   fix3: max_value列が未バックフィル（NULL）の古いデータでも正しく更新される
#
# QC10（エラーハンドリング：不正な観測点・不正な入力文字列でも例外にならず、想定された
# 応答になること）と OWASP10（特に A03 Injection: 観測点コードにSQLメタ文字を含む値が
# 渡されてもテーブル破壊やインジェクションが起きないこと、A04 Insecure Design: 「一度
# 上がった最大観測値は下方修正の続報で下げない」というパラメトリック保険の支払算定の
# 根幹をなす不変条件が、サービス層だけでなくモデル層でも多重に保護されていること）の
# 該当観点を確認する。
#
# [重要] 固定の絶対日時はハードコードしない。「取込遅延が発生した場合も発生時刻をそのまま
# 保持する」（設計資料 1.5 F2）という仕様を確認する箇所以外は、現在時刻からの相対値
# （Time.current, 3.days.ago 等）でシナリオを組み立てる。
#
# 実行方法（開発/テストDBのみを対象。本番サーバーへは一切接続しない。
# config/database.yml の test 環境は sqlite3 の storage/test.sqlite3 を使用する）:
#   cd src/backend
#   RAILS_ENV=test bin/rails db:test:prepare
#   bundle exec rspec ../../test/pr48/pr48_ingest_observation_event_spec.rb

require "rails_helper"

RSpec.describe "PR48: 観測取込コアロジック(F2 IngestObservationEvent) - 最大値更新と履歴保存の分離" do
  include ActiveSupport::Testing::TimeHelpers

  # 他のスペックファイル・シード（db/seeds.rb）と code/sort_order が衝突しないよう、
  # PR48専用のサフィックスを付ける。RSpecはデフォルトでトランザクション内実行・自動
  # ロールバックのため、example をまたいでの衝突は起きない。
  let(:suffix) { "pr48_#{SecureRandom.hex(4)}" }

  let!(:seismic_station) do
    Station.create!(
      code: "seismic_tokyo_#{suffix}",
      measurement_type: "seismic",
      label_ja: "東京震度観測点", label_en: "Tokyo", label_fr: "Tokyo", label_zh: "Tokyo",
      label_ru: "Tokyo", label_es: "Tokyo", label_ar: "Tokyo"
    )
  end

  let!(:rainfall_station) do
    Station.create!(
      code: "rainfall_tokyo_#{suffix}",
      measurement_type: "rainfall",
      label_ja: "東京雨量観測点", label_en: "Tokyo rainfall", label_fr: "Tokyo rainfall", label_zh: "Tokyo rainfall",
      label_ru: "Tokyo rainfall", label_es: "Tokyo rainfall", label_ar: "Tokyo rainfall"
    )
  end

  let!(:level_4) do
    SeismicIntensityLevel.create!(
      code: "4_#{suffix}", sort_order: 4,
      label_ja: "4", label_en: "4", label_fr: "4", label_zh: "4", label_ru: "4", label_es: "4", label_ar: "4"
    )
  end

  let!(:level_5_weak) do
    SeismicIntensityLevel.create!(
      code: "5weak_#{suffix}", sort_order: 5,
      label_ja: "5弱", label_en: "5w", label_fr: "5w", label_zh: "5w", label_ru: "5w", label_es: "5w", label_ar: "5w"
    )
  end

  let(:queue_spy) { class_spy(ObservationReevaluationJob) }

  def ingest(payload)
    IngestObservationEvent.new(payload: payload, queue_job: queue_spy).call
  end

  # ---------------------------------------------------------------------
  # 手順1: 新しい観測データを投入する（震度4の地震が発生した想定）
  # ---------------------------------------------------------------------
  describe "手順1: 新しい観測データを投入する（震度4）" do
    it "処理結果: created となり、最大観測値(max_value)が4として記録され、履歴・再判定キューも作られる" do
      # 「取込遅延が発生した場合も発生時刻をそのまま保持する」ことを確認するため、
      # 意図的に過去の時刻（3日前）を発生時刻として投入する。
      occurred_at = 3.days.ago

      result = ingest(
        station_id: seismic_station.id,
        event_id: "pr48-quake-001",
        occurred_at: occurred_at,
        seismic_intensity_level_id: level_4.id,
        simulated: true
      )

      expect(result).to be_success
      expect(result.status).to eq(:created)
      expect(result.observation).to be_persisted
      expect(result.observation.max_value).to eq(BigDecimal("4"))
      # 取込（ingest）時刻ではなく、渡された発生時刻がそのまま保持されていること
      expect(result.observation.observed_at).to be_within(1.second).of(occurred_at)
      expect(result.observation.simulated).to eq(true)

      expect(result.history_event).to be_persisted
      expect(ObservationEvent.where(observation: result.observation).count).to eq(1)
      expect(result.history_event.occurred_at).to be_within(1.second).of(occurred_at)

      expect(queue_spy).to have_received(:perform_later).with(result.observation.id)
    end
  end

  # ---------------------------------------------------------------------
  # 手順2: 続報が届き、震度がさらに強く（5弱に）修正された場合
  # ---------------------------------------------------------------------
  describe "手順2: 続報で震度が上回る（5弱に上方修正）場合" do
    let!(:existing_observation) do
      Observation.create!(
        station: seismic_station, event_id: "pr48-quake-001",
        observed_at: 1.hour.ago, seismic_intensity_level: level_4, max_value: 4, simulated: true
      )
    end

    it "処理結果: updated となり、最大観測値が5に更新され、再判定キューへ投入される" do
      result = ingest(
        station_id: seismic_station.id,
        event_id: "pr48-quake-001",
        occurred_at: Time.current,
        seismic_intensity_level_id: level_5_weak.id,
        simulated: true
      )

      expect(result).to be_success
      expect(result.status).to eq(:updated)
      expect(existing_observation.reload.max_value).to eq(BigDecimal("5"))
      expect(existing_observation.seismic_intensity_level).to eq(level_5_weak)
      # 観測の同一性は event_id で識別されるため、集計行(summary row)自体は
      # 新規作成されず、既存の1件のまま更新されること
      expect(Observation.where(station: seismic_station, event_id: "pr48-quake-001").count).to eq(1)

      expect(result.history_event).to be_persisted
      expect(ObservationEvent.where(observation: existing_observation).count).to eq(1)

      expect(queue_spy).to have_received(:perform_later).with(existing_observation.id)
    end
  end

  # ---------------------------------------------------------------------
  # 手順3: 続報が届いたが、震度が手順1の値まで下方修正された場合
  # ---------------------------------------------------------------------
  describe "手順3: 続報で震度が下回る（4に下方修正）場合" do
    let!(:existing_observation) do
      Observation.create!(
        station: seismic_station, event_id: "pr48-quake-001",
        observed_at: 1.hour.ago, seismic_intensity_level: level_5_weak, max_value: 5, simulated: true
      )
    end

    it "処理結果: recorded となり、最大観測値は5のまま変わらず、再判定キューへは投入されない" do
      result = ingest(
        station_id: seismic_station.id,
        event_id: "pr48-quake-001",
        occurred_at: Time.current,
        seismic_intensity_level_id: level_4.id,
        simulated: true
      )

      expect(result).to be_success
      expect(result.status).to eq(:recorded)
      # 「一度上がった最大観測値は下方修正の続報で下げない」という不変条件そのもの
      expect(existing_observation.reload.max_value).to eq(BigDecimal("5"))
      expect(existing_observation.seismic_intensity_level).to eq(level_5_weak)

      expect(result.history_event).to be_persisted
      expect(queue_spy).not_to have_received(:perform_later)
    end

    it "下方修正の続報であっても、履歴（ObservationEvent）には別レコードとして追記される" do
      # 「下回る続報は履歴として記録するのみとする」（設計資料 F2）ことを、
      # 「何も起きない」ではなく「履歴として実際に残る」という肯定的な形で確認する
      first_follow_up_at = 30.minutes.ago
      second_follow_up_at = Time.current

      ingest(
        station_id: seismic_station.id, event_id: "pr48-quake-001",
        occurred_at: first_follow_up_at, seismic_intensity_level_id: level_4.id, simulated: true
      )
      ingest(
        station_id: seismic_station.id, event_id: "pr48-quake-001",
        occurred_at: second_follow_up_at, seismic_intensity_level_id: level_4.id, simulated: true
      )

      history = ObservationEvent.where(observation: existing_observation).order(:occurred_at)
      expect(history.count).to eq(2)
      expect(history.first.occurred_at).to be_within(1.second).of(first_follow_up_at)
      expect(history.second.occurred_at).to be_within(1.second).of(second_follow_up_at)
      expect(existing_observation.reload.max_value).to eq(BigDecimal("5"))
    end
  end

  # ---------------------------------------------------------------------
  # 手順4: 存在しない観測点にデータを送った場合（無視されることの確認）
  # ---------------------------------------------------------------------
  describe "手順4: 存在しない観測点は無視される" do
    it "処理結果: ignored となり、Observation/ObservationEventの件数が変化せず、再判定キューにも積まれない" do
      before_observation_count = Observation.count
      before_history_count = ObservationEvent.count

      result = ingest(
        station_id: 999_999_999,
        event_id: "pr48-quake-unknown-station",
        occurred_at: Time.current,
        seismic_intensity_level_id: level_4.id,
        simulated: true
      )

      expect(result.status).to eq(:ignored)
      expect(result).not_to be_success
      expect(Observation.count).to eq(before_observation_count)
      expect(ObservationEvent.count).to eq(before_history_count)
      expect(queue_spy).not_to have_received(:perform_later)
    end

    it "OWASP A03: 観測点コードにSQLメタ文字が含まれていても例外にならず ignored として安全に処理される" do
      malicious_code = "'; DROP TABLE observations; --"

      result = nil
      expect do
        result = ingest(
          station_code: malicious_code,
          event_id: "pr48-quake-injection",
          occurred_at: Time.current,
          seismic_intensity_level_id: level_4.id,
          simulated: true
        )
      end.not_to raise_error

      expect(result.status).to eq(:ignored)
      # テーブルが破壊されていないこと（実行後も既存データを問題なく参照できること）を
      # 肯定的に確認する
      expect(Station.where(id: seismic_station.id)).to exist
      expect(Observation.count).to eq(0)
    end
  end

  # ---------------------------------------------------------------------
  # fix1（レビュー指摘の追加修正）: 同時取込（レース条件）対策
  # ---------------------------------------------------------------------
  describe "fix1: 同時取込によるロストアップデートの防止（条件付きUPDATE）" do
    let!(:existing_observation) do
      Observation.create!(
        station: seismic_station, event_id: "pr48-quake-race",
        observed_at: 1.hour.ago, seismic_intensity_level: level_4, max_value: 4, simulated: false
      )
    end

    it "自分の読み取りより後に、別プロセスがより大きい最大値を先にコミットした場合、その値を上書きしない" do
      # find_by で観測を読み取った直後に、別プロセス（5分ポーリングと管理画面注入の同時到着
      # 等）が既により大きい最大値(6)をコミットしていた状況を再現する
      allow(Observation).to receive(:find_by).and_wrap_original do |method, *args|
        record = method.call(*args)
        if record&.id == existing_observation.id
          Observation.where(id: existing_observation.id).update_all(max_value: 6)
        end
        record
      end

      result = ingest(
        station_id: seismic_station.id, event_id: "pr48-quake-race",
        occurred_at: Time.current, seismic_intensity_level_id: level_5_weak.id, simulated: false
      )

      expect(result).to be_success
      # 5弱(5)は自分の読み取り時点のmax_value(4)より大きいが、実際にDBに
      # 既にコミットされている6より小さいため、条件付きUPDATEが失敗し
      # 「記録のみ(recorded)」にフォールバックする
      expect(result.status).to eq(:recorded)
      expect(existing_observation.reload.max_value).to eq(BigDecimal("6"))
      expect(queue_spy).not_to have_received(:perform_later)
    end

    it "新規作成時に2つの取込が同時に競合しても、最終的に観測行は1件だけになり、大きい方の値が残る" do
      # 1回目の存在チェックが「まだ無い」と誤判定した直後に、別プロセスが同じ
      # (station_id, event_id) の行を先にコミットしてしまうレースを再現する
      call_count = 0
      allow(Observation).to receive(:find_by).and_wrap_original do |method, *args|
        call_count += 1
        if call_count == 1
          Observation.create!(
            station: seismic_station, event_id: "pr48-quake-race-create",
            observed_at: 30.minutes.ago, seismic_intensity_level: level_4, max_value: 4, simulated: false
          )
          nil
        else
          method.call(*args)
        end
      end

      result = nil
      expect do
        result = ingest(
          station_id: seismic_station.id, event_id: "pr48-quake-race-create",
          occurred_at: Time.current, seismic_intensity_level_id: level_5_weak.id, simulated: false
        )
      end.not_to raise_error

      expect(result).to be_success
      expect(result.status).to eq(:updated)
      expect(Observation.where(station: seismic_station, event_id: "pr48-quake-race-create").count).to eq(1)
      expect(Observation.find_by(station: seismic_station, event_id: "pr48-quake-race-create").max_value).to eq(BigDecimal("5"))
    end
  end

  # ---------------------------------------------------------------------
  # fix3（レビュー指摘の追加修正）: max_value未バックフィル（NULL）の古いデータ
  # ---------------------------------------------------------------------
  describe "fix3: max_value列が未バックフィル（NULL）の古いデータでも正しく更新される" do
    it "震度観測: NULLの古いデータでも上回る続報で最大値が更新され、再判定キューへ投入される" do
      legacy_observation = Observation.create!(
        station: seismic_station, event_id: "pr48-legacy-seismic",
        observed_at: 1.day.ago, seismic_intensity_level: level_4, max_value: 4, simulated: false
      )
      # マイグレーション直後の未バックフィル状態（max_valueだけがNULL）を再現する
      Observation.where(id: legacy_observation.id).update_all(max_value: nil)

      result = ingest(
        station_id: seismic_station.id, event_id: "pr48-legacy-seismic",
        occurred_at: Time.current, seismic_intensity_level_id: level_5_weak.id, simulated: false
      )

      expect(result.status).to eq(:updated)
      expect(legacy_observation.reload.max_value).to eq(BigDecimal("5"))
      expect(queue_spy).to have_received(:perform_later).with(legacy_observation.id)
    end

    it "降雨観測: NULLの古いデータでも上回る続報で最大値が更新され、再判定キューへ投入される" do
      legacy_observation = Observation.create!(
        station: rainfall_station, observed_at: 1.day.ago, rainfall_mm: "10.00", max_value: 10, simulated: false
      )
      Observation.where(id: legacy_observation.id).update_all(max_value: nil)

      result = ingest(
        station_id: rainfall_station.id, occurred_at: legacy_observation.observed_at,
        rainfall_mm: "25.50", simulated: false
      )

      expect(result.status).to eq(:updated)
      expect(legacy_observation.reload.max_value).to eq(BigDecimal("25.50"))
      expect(legacy_observation.rainfall_mm).to eq(BigDecimal("25.50"))
      expect(queue_spy).to have_received(:perform_later).with(legacy_observation.id)
    end
  end

  # ---------------------------------------------------------------------
  # 降雨観測点の識別単位（観測点ID × 観測時刻）の確認
  # ---------------------------------------------------------------------
  describe "降雨観測は(観測点ID × 観測時刻)を単位として同一観測を識別する" do
    it "観測時刻が異なれば、たとえ同じ観測点でも別の観測として新規作成される" do
      first_time = 2.hours.ago
      second_time = 1.hour.ago

      first_result = ingest(station_id: rainfall_station.id, occurred_at: first_time, rainfall_mm: "5.00", simulated: true)
      second_result = ingest(station_id: rainfall_station.id, occurred_at: second_time, rainfall_mm: "8.00", simulated: true)

      expect(first_result.status).to eq(:created)
      expect(second_result.status).to eq(:created)
      expect(first_result.observation.id).not_to eq(second_result.observation.id)
      expect(Observation.where(station: rainfall_station).count).to eq(2)
    end

    it "観測時刻が同一であれば、上回る雨量の続報は同一観測の最大値更新として扱われる" do
      observed_at = 1.hour.ago
      first_result = ingest(station_id: rainfall_station.id, occurred_at: observed_at, rainfall_mm: "5.00", simulated: true)
      second_result = ingest(station_id: rainfall_station.id, occurred_at: observed_at, rainfall_mm: "12.00", simulated: true)

      expect(first_result.status).to eq(:created)
      expect(second_result.status).to eq(:updated)
      expect(second_result.observation.id).to eq(first_result.observation.id)
      expect(second_result.observation.reload.max_value).to eq(BigDecimal("12.00"))
      expect(Observation.where(station: rainfall_station).count).to eq(1)
    end
  end

  # ---------------------------------------------------------------------
  # OWASP A04 Insecure Design: モデル層での多重防御
  # （サービス層の条件付きUPDATEをバイパスして直接ActiveRecordで更新しても、
  #   「一度上がった最大観測値を下げる」変更はバリデーションで拒否されること）
  # ---------------------------------------------------------------------
  describe "モデル層の多重防御: 最大観測値・震度・雨量を下げる直接更新はバリデーションで拒否される" do
    it "震度: seismic_intensity_level を既存より低い等級へ直接updateしようとするとRecordInvalidになる" do
      observation = Observation.create!(
        station: seismic_station, event_id: "pr48-model-guard-seismic",
        observed_at: Time.current, seismic_intensity_level: level_5_weak, max_value: 5, simulated: false
      )

      expect do
        observation.update!(seismic_intensity_level: level_4)
      end.to raise_error(ActiveRecord::RecordInvalid)
      expect(observation.reload.seismic_intensity_level).to eq(level_5_weak)
    end

    it "降雨: rainfall_mm を既存より低い値へ直接updateしようとするとRecordInvalidになる" do
      observation = Observation.create!(
        station: rainfall_station, observed_at: Time.current, rainfall_mm: "20.00", max_value: 20, simulated: false
      )

      expect do
        observation.update!(rainfall_mm: "5.00")
      end.to raise_error(ActiveRecord::RecordInvalid)
      expect(observation.reload.rainfall_mm).to eq(BigDecimal("20.00"))
    end
  end

  # ---------------------------------------------------------------------
  # QC10 エラーハンドリング: 不正・不足した入力データでも例外にならない
  # ---------------------------------------------------------------------
  describe "QC10: 不正な入力（不足した必須項目）でも例外にならず ignored になる" do
    it "震度観測なのに震度等級が指定されていない場合はignoredになる" do
      result = nil
      expect do
        result = ingest(
          station_id: seismic_station.id, event_id: "pr48-missing-level",
          occurred_at: Time.current, simulated: true
        )
      end.not_to raise_error

      expect(result.status).to eq(:ignored)
      expect(Observation.count).to eq(0)
    end

    it "震度観測なのにevent_idが指定されていない場合はignoredになる" do
      result = ingest(
        station_id: seismic_station.id, occurred_at: Time.current,
        seismic_intensity_level_id: level_4.id, simulated: true
      )

      expect(result.status).to eq(:ignored)
      expect(Observation.count).to eq(0)
    end

    it "降雨観測なのに雨量が指定されていない場合はignoredになる" do
      result = ingest(station_id: rainfall_station.id, occurred_at: Time.current, simulated: true)

      expect(result.status).to eq(:ignored)
      expect(Observation.count).to eq(0)
    end

    it "occurred_at（発生時刻）が指定されていない場合はignoredになる" do
      result = ingest(
        station_id: seismic_station.id, event_id: "pr48-missing-occurred-at",
        seismic_intensity_level_id: level_4.id, simulated: true
      )

      expect(result.status).to eq(:ignored)
      expect(Observation.count).to eq(0)
    end
  end
end
