# PR #53「[Stage 10] 気象庁観測データポーリング（FR-03）を追加」
#
# PR本文に書かれた「非エンジニア向けユーザーテスト手順」を自動再現するテスト。
# 対象は開発サーバー・開発/テストDB（SQLite）のみで、本番サーバー・実際の気象庁サーバー
# には一切接続しない（すべてリポジトリ同梱のfixture XML、またはこのファイル内で組み立てた
# XML文字列、および Net::HTTP をスタブ化した疑似HTTP応答のみを使用する）。
#
# 対応する手順（PR本文より）:
#   手順1: サンプルの雨量データが正しく取り込まれることを確認する
#          -> "手順1" セクション（JmaPoller -> IngestObservationEvent -> DB保存の統合確認）
#   手順2: サンプルの震度データを正しく読み取れる（震度表記の変換）ことを確認する
#          -> "手順2" セクション（JmaPoller.parse の出力・5-/5+/6-/6+ の変換を確認）
#   手順3: 訓練報（訓練・試験用の配信）が「模擬」として区別されることを確認する
#          -> "手順3" セクション
#   手順4: 許可されていないドメインのURLへはアクセスしない（SSRF対策）ことを確認する
#          -> "手順4" セクション（OWASP A10: SSRF）
#   手順5: 同じ観測報告を2回登録しても重複しないことを確認する
#          -> "手順5" セクション
#   手順6（総合確認）: 開発チームが用意した自動テスト一式（spec/services/jma_poller_spec.rb）
#          を実行して確認する -> "手順6" セクション（既定ではオプトインでのみ実行。理由は後述）
#
# 併せて、設計資料 1.5 節「F2 観測取込 ingestObservationEvent」の要件
#   - 既存レコードがある場合、観測値が既存の最大値を上回るときのみ最大観測値を更新する
#   - 下回る続報は履歴として記録するのみとする（最大値は更新しない・再判定キューへは積まない）
#   - 未登録観測点のデータは無視する
# を "F2要件（設計資料1.5）" セクションで確認する。
#
# QC10（エラーハンドリング）・OWASP10（特にA10 SSRF、A04 Insecure Design）の該当観点も
# あわせて確認する。
#
# 実行方法（開発/テストDBのみを対象。本番サーバーへは一切接続しない）:
#   cd src/backend
#   RAILS_ENV=test bin/rails db:test:prepare
#   bundle exec rspec ../../test/pr53/pr53_jma_poller_spec.rb
#
# [重要] 本ファイルの「手順6」テストは、開発チームが用意した既存の自動テスト一式
# （spec/services/jma_poller_spec.rb）を bundle exec rspec のサブプロセスとして実際に
# 実行する“総合確認”です。本テストファイル自身のRSpecプロセスがトランザクション内で
# DBを操作している最中に、同じSQLiteファイルへ書き込む別プロセスを起動すると
# "database is locked" のような無関係な理由でCIが不安定化するおそれがあるため、
# 既定ではスキップし、環境変数 PR53_RUN_FULL_SUITE=1 を指定したときのみ実行する
# オプトイン方式にしている（test/pr59/pr59_live_dev_server_spec.rb と同じ考え方）。

require "rails_helper"
require "open3"

RSpec.describe "PR53: 気象庁観測データポーリング（JmaPoller, FR-03）" do
  include ActiveJob::TestHelper

  let(:fixtures_root) { Rails.root.join("spec/fixtures/jma") }

  # ===========================================================================
  # 手順1: サンプルの雨量データが正しく取り込まれることを確認する
  # ===========================================================================
  describe "手順1: サンプルの雨量データの取り込み（JmaPoller -> IngestObservationEvent -> DB）" do
    it "PR本文どおりのコマンド（rainfall.xml取り込み）で「東京雨量観測点」に12.5mmが観測時刻とともに保存される" do
      station = find_or_create_rainfall_station!

      xml = File.read(fixtures_root.join("rainfall.xml"))

      expect {
        JmaPoller.new(xml: xml).call
      }.to change(Observation, :count).by(1)

      obs = Observation.order(:id).last
      expect(obs.station_id).to eq(station.id)
      expect(obs.station.label_ja).to eq("東京雨量観測点")
      expect(obs.rainfall_mm).to eq(BigDecimal("12.5"))
      expect(obs.observed_at).to eq(Time.zone.parse("2026-07-16T15:00:00+09:00"))
      expect(obs.simulated).to be false
    end

    it "新規観測の取り込みは再判定キュー（ObservationReevaluationJob）へ投入される（F2: 即日性の起点）" do
      find_or_create_rainfall_station!
      xml = File.read(fixtures_root.join("rainfall.xml"))

      expect {
        JmaPoller.new(xml: xml).call
      }.to have_enqueued_job(ObservationReevaluationJob)
    end

    it "失敗パターン: 観測点マスタ未登録（db:seed未実施相当）の場合は例外を出さずに何も保存されない" do
      # あえて find_or_create_rainfall_station! を呼ばない = 「観測点:」の後ろが空欄になる状況を再現
      xml = File.read(fixtures_root.join("rainfall.xml"))

      expect {
        expect { JmaPoller.new(xml: xml).call }.not_to raise_error
      }.not_to change(Observation, :count)

      expect(Observation.order(:id).last).to be_nil
    end
  end

  # ===========================================================================
  # 手順2: サンプルの震度データを正しく読み取れる（震度表記の変換）ことを確認する
  # ===========================================================================
  describe "手順2: サンプルの震度データの読み取り・震度表記の変換（JmaPoller.parse）" do
    it "PR本文どおりのコマンド（seismic.xml解析）で station_code / event_id / 震度ラベルが読み取れる" do
      xml = File.read(fixtures_root.join("seismic.xml"))

      result = JmaPoller.parse(xml)

      expect(result).to eq(
        [
          {
            station_code: "1421220",
            occurred_at: "2026-07-16T15:04:00+09:00",
            event_id: "20260716150443",
            seismic_intensity_level_label_ja: "1",
            simulated: false
          }
        ]
      )
    end

    it "気象庁内部表記 5-/5+/6- を日本語表記（5弱/5強/6弱）へ変換する" do
      xml = seismic_report_xml(event_id: "conv-test-1", occurred_at: "2026-07-16T15:00:00+09:00", stations: {
        "1111111" => "5-",
        "2222222" => "5+",
        "3333333" => "6-"
      })

      result = JmaPoller.parse(xml)
      labels_by_station = result.to_h { |r| [ r[:station_code], r[:seismic_intensity_level_label_ja] ] }

      expect(labels_by_station).to eq(
        "1111111" => "5弱",
        "2222222" => "5強",
        "3333333" => "6弱"
      )
    end

    it "失敗パターンの確認: 震度階級を含まない不正なXMLでは空配列になる（例外で落ちない）" do
      xml = <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <Report xmlns="http://xml.kishou.go.jp/jmaxml1/">
          <Head><EventID>broken</EventID></Head>
          <Body></Body>
        </Report>
      XML

      expect { JmaPoller.parse(xml) }.not_to raise_error
      expect(JmaPoller.parse(xml)).to eq([])
    end
  end

  # ===========================================================================
  # 手順3: 訓練報（訓練・試験用の配信）が「模擬」として区別されることを確認する
  # ===========================================================================
  describe "手順3: 訓練報の simulated フラグ" do
    it "PR本文どおりのコマンド（Status=訓練の震度XML）で simulated: true になる" do
      xml = <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <Report xmlns="http://xml.kishou.go.jp/jmaxml1/">
          <Control><Status>訓練</Status></Control>
          <Head><EventID>test-training-001</EventID><ReportDateTime>2026-07-16T15:04:00+09:00</ReportDateTime></Head>
          <Body><Intensity><Observation><Pref><Area><City>
            <IntensityStation><Code>1421220</Code><Int>1</Int></IntensityStation>
          </City></Area></Pref></Observation></Intensity></Body>
        </Report>
      XML

      result = JmaPoller.parse(xml)

      expect(result).not_to be_empty
      expect(result.first[:simulated]).to be true
    end

    it "Status=試験 の降雨XMLでも simulated: true になる" do
      xml = <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <Report xmlns="http://xml.kishou.go.jp/jmaxml1/">
          <Control><Status>試験</Status></Control>
          <Head><ReportDateTime>2026-07-16T15:05:00+09:00</ReportDateTime></Head>
          <Body><MeteorologicalInfo><TimeSeriesInfo>
            <TimeDefines><TimeDefine timeId="1"><DateTime>2026-07-16T15:00:00+09:00</DateTime></TimeDefine></TimeDefines>
            <Item><Station><Code>44132</Code></Station><Kind><Property>
              <Type>降水量</Type>
              <Precipitation type="前１時間降水量" refID="1">12.5</Precipitation>
            </Property></Kind></Item>
          </TimeSeriesInfo></MeteorologicalInfo></Body>
        </Report>
      XML

      result = JmaPoller.parse(xml)

      expect(result).not_to be_empty
      expect(result.first[:simulated]).to be true
    end

    it "失敗パターンの否定確認: Status=通常（またはStatus省略）の実データは simulated: false のままである" do
      xml = File.read(fixtures_root.join("seismic.xml"))
      result = JmaPoller.parse(xml)

      expect(result.first[:simulated]).to be false
    end

    # ---------------------------------------------------------------------
    # 手順3関連: 訓練報からの誤支払防止（Issue #66で検出・修正済み）
    # ---------------------------------------------------------------------
    # PR本文は「訓練報を検知した場合に simulated フラグを立てることで、訓練報が
    # 実際の災害発生と誤認されて模擬支払の判定に使われてしまうことを防ぐ」と説明している。
    # EvaluateTrigger#call に `observation.simulated? && !observation.admin_injected?`
    # のガードが追加されたことで、JMA由来のsimulated（admin_injected: false）は
    # 判定対象から除外される。一方、管理画面からの模擬イベント注入（F5、
    # admin_injected: true）は従来どおりトリガー判定を通過し、デモ用の模擬支払を生成する
    # （test/pr56/pr56_admin_simulated_events_spec.rb で別途確認済み）。
    it "訓練報（simulated: true, admin_injected: false）の観測はトリガー判定から除外され、模擬支払が誤って発生しない" do
      station = find_or_create_seismic_station!(code: "seismic_pr53_training_bug", jma_code: "9990001")
      seed_seismic_intensity_levels!
      policy = create_active_seismic_policy!(station: station, threshold_label: "5強")

      training_xml = seismic_report_xml(
        event_id: "training-bug-check-001",
        occurred_at: Time.current.iso8601,
        status: "訓練",
        stations: { station.jma_code => "5+" }
      )

      perform_enqueued_jobs do
        JmaPoller.new(xml: training_xml).call
      end

      observation = Observation.find_by(station: station, event_id: "training-bug-check-001")
      expect(observation).to be_present
      expect(observation.simulated).to be true
      expect(observation.admin_injected).to be false

      # あるべき挙動: 訓練報からは模擬支払も一切発生しないこと
      expect(Payout.where(policy: policy).count).to eq(0)
      expect(Notification.where(policy: policy).count).to eq(0)
    end
  end

  # ===========================================================================
  # 手順4: 許可されていないドメインのURLへはアクセスしない（SSRF対策 / OWASP A10）
  # ===========================================================================
  describe "手順4: SSRF対策（気象庁の正規ドメイン・HTTPSのみ許可）" do
    it "PR本文どおりの3ケース（正規ドメイン許可・httpの気象庁ドメイン拒否・非気象庁ドメイン拒否）" do
      poller = JmaPoller.new(xml: "<feed xmlns=\"http://www.w3.org/2005/Atom\"></feed>")

      expect(poller.send(:valid_jma_url?, "https://xml.data.jma.go.jp/data/seismic_sample.xml")).to be true
      expect(poller.send(:valid_jma_url?, "http://unsafe.example.com/malicious.xml")).to be false
      expect(poller.send(:valid_jma_url?, "https://evil.example.com/data.xml")).to be false
    end

    it "気象庁ドメインをHTTPで取得しようとした場合も拒否される（HTTPS必須）" do
      poller = JmaPoller.new(xml: "<feed xmlns=\"http://www.w3.org/2005/Atom\"></feed>")

      expect(poller.send(:valid_jma_url?, "http://www.data.jma.go.jp/developer/xml/feed/eqvol.xml")).to be false
    end

    it "サブドメインなりすまし（www.data.jma.go.jp.evil.com）は拒否される（OWASP A10: SSRFのホスト検証バイパス対策）" do
      poller = JmaPoller.new(xml: "<feed xmlns=\"http://www.w3.org/2005/Atom\"></feed>")

      expect(poller.send(:valid_jma_url?, "https://www.data.jma.go.jp.evil.com/malicious.xml")).to be false
    end

    it "不正なURL文字列を渡しても例外を出さずfalseを返す（QC10: エラーハンドリング）" do
      poller = JmaPoller.new(xml: "<feed xmlns=\"http://www.w3.org/2005/Atom\"></feed>")

      expect { poller.send(:valid_jma_url?, "not a url ::: with spaces") }.not_to raise_error
      expect(poller.send(:valid_jma_url?, "not a url ::: with spaces")).to be false
    end

    it "統合確認: Atomフィード内の不正リンクへは実際にHTTPリクエストが送られない" do
      feed_xml = File.read(fixtures_root.join("feed.xml"))
      seismic_xml = File.read(fixtures_root.join("seismic.xml"))
      find_or_create_seismic_station!(code: "seismic_pr53_ssrf", jma_code: "1421220")
      seed_seismic_intensity_levels!

      http_double = double("http")
      allow(Net::HTTP).to receive(:start).and_yield(http_double)

      indiv_uri = URI("https://xml.data.jma.go.jp/data/seismic_sample.xml")
      indiv_response = instance_double(Net::HTTPSuccess, body: seismic_xml)
      allow(indiv_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
      allow(http_double).to receive(:get).with(indiv_uri.request_uri).and_return(indiv_response)

      unsafe_uri = URI("http://unsafe.example.com/malicious.xml")
      expect(http_double).not_to receive(:get).with(unsafe_uri.request_uri)

      feed_uri = URI("https://www.data.jma.go.jp/developer/xml/feed/eqvol.xml")
      feed_response = instance_double(Net::HTTPSuccess, body: feed_xml)
      allow(feed_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
      allow(http_double).to receive(:get).with(feed_uri.request_uri).and_return(feed_response)

      poller = JmaPoller.new(feed_url: feed_uri.to_s, rainfall_feed_url: nil)

      # `expect(http_double).not_to receive(:get).with(unsafe_uri.request_uri)` (上で設定済み) が
      # 不正URLへのアクセスが一切発生しないことを保証する。ここでは呼び出し自体が例外なく完了する
      # ことを確認する（不正URLへのアクセスがあれば上のnot_to receiveでこのcallの時点で失敗する）
      expect { poller.call }.not_to raise_error
    end
  end

  # ===========================================================================
  # 手順5: 同じ観測報告を2回登録しても重複しないことを確認する
  # ===========================================================================
  describe "手順5: 重複防止（ProcessedJmaEntry）" do
    it "PR本文どおりのコマンド（同一entry_idの2重作成）で2回目はバリデーションエラーになる" do
      ProcessedJmaEntry.create!(entry_id: "urn:uuid:pr53-eq-entry-1")

      expect {
        ProcessedJmaEntry.create!(entry_id: "urn:uuid:pr53-eq-entry-1")
      }.to raise_error(ActiveRecord::RecordInvalid, /Entry has already been taken|entry_id/i)

      expect(ProcessedJmaEntry.where(entry_id: "urn:uuid:pr53-eq-entry-1").count).to eq(1)
    end

    it "統合確認: 同じAtomフィードを2回ポーリングしても2件目のingestは実行されない" do
      find_or_create_seismic_station!(code: "seismic_pr53_dedupe", jma_code: "1421220")
      seed_seismic_intensity_levels!

      feed_xml = File.read(fixtures_root.join("feed.xml"))
      seismic_xml = File.read(fixtures_root.join("seismic.xml"))

      http_double = double("http")
      allow(Net::HTTP).to receive(:start).and_yield(http_double)

      feed_uri = URI("https://www.data.jma.go.jp/developer/xml/feed/eqvol.xml")
      feed_response = instance_double(Net::HTTPSuccess, body: feed_xml)
      allow(feed_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
      allow(http_double).to receive(:get).with(feed_uri.request_uri).and_return(feed_response)

      indiv_uri = URI("https://xml.data.jma.go.jp/data/seismic_sample.xml")
      indiv_response = instance_double(Net::HTTPSuccess, body: seismic_xml)
      allow(indiv_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
      allow(http_double).to receive(:get).with(indiv_uri.request_uri).and_return(indiv_response)

      poller = JmaPoller.new(feed_url: feed_uri.to_s, rainfall_feed_url: nil)

      # 1回目: フィードの3件中、安全なURLを持つ2件（"urn:uuid:eq-entry-1" と
      # "urn:uuid:eq-entry-duplicate"）が新規に処理済みとして記録される（不正URLの1件は除外）。
      # この2件は同じ地震（同一event_id）を指しているため、Observationとしては1件にまとまる
      # （2件目は「続報」として扱われ、履歴には残るがレコードは新規作成されない）
      expect { poller.call }.to change(ProcessedJmaEntry, :count).by(2)
                            .and change(Observation, :count).by(1)

      # 2回目（同じフィードを再度ポーリング＝5分後の次回ポーリング相当）: 既に処理済みのため増えない
      expect { poller.call }.not_to change(Observation, :count)
      expect { poller.call }.not_to change(ProcessedJmaEntry, :count)
    end
  end

  # ===========================================================================
  # 手順6（総合確認）: 開発チームが用意した自動テスト一式を実行する
  # ===========================================================================
  describe "手順6: 既存の自動テスト一式（spec/services/jma_poller_spec.rb）の実行結果確認" do
    around(:each) do |example|
      if ENV["PR53_RUN_FULL_SUITE"] == "1"
        example.run
      else
        skip "既定ではスキップ（オプトイン制）。手順1〜5で代表的な動作は個別に確認済み。" \
             "開発チーム提供の自動テスト一式を実際にサブプロセスとして実行し確認したい場合は、" \
             "PR53_RUN_FULL_SUITE=1 を指定して再実行してください。"
      end
    end

    it "spec/services/jma_poller_spec.rb を実行すると 0 failures で終了する" do
      assert_local_sqlite_test_db!

      env = { "RAILS_ENV" => "test", "DATABASE_URL" => nil }
      stdout_and_err, status = Open3.capture2e(
        env, "bundle", "exec", "rspec", "spec/services/jma_poller_spec.rb", "--format", "progress",
        chdir: Rails.root.to_s
      )

      expect(status.success?).to be(true), "既存テスト一式が失敗しました:\n#{stdout_and_err}"
      expect(stdout_and_err).to match(/0 failures/)
    end
  end

  # ===========================================================================
  # F2要件（設計資料1.5）: 最大値更新のみ反映・下方修正は履歴のみ・未登録観測点は無視
  # ===========================================================================
  describe "F2要件（設計資料1.5): 続報による最大観測値の更新ルール" do
    it "震度: 上方修正の続報（1→5+）でのみ最大観測値が更新され、再判定キューに積まれる" do
      station = find_or_create_seismic_station!(code: "seismic_pr53_max_up", jma_code: "1421220")
      seed_seismic_intensity_levels!

      first_report = seismic_report_xml(event_id: "max-update-001", occurred_at: "2026-07-16T15:04:00+09:00", stations: { station.jma_code => "1" })
      JmaPoller.new(xml: first_report).call
      observation = Observation.find_by(station: station, event_id: "max-update-001")
      expect(observation.seismic_intensity_level.label_ja).to eq("1")

      clear_enqueued_jobs

      follow_up_report = seismic_report_xml(event_id: "max-update-001", occurred_at: "2026-07-16T15:04:00+09:00", stations: { station.jma_code => "5+" })
      expect {
        JmaPoller.new(xml: follow_up_report).call
      }.to have_enqueued_job(ObservationReevaluationJob)

      observation.reload
      expect(observation.seismic_intensity_level.label_ja).to eq("5強")
      expect(observation.max_value.to_i).to eq(6)
    end

    it "震度: 下方修正の続報（5+→1）は履歴として記録されるだけで最大観測値は更新されず、再判定キューにも積まれない" do
      station = find_or_create_seismic_station!(code: "seismic_pr53_max_down", jma_code: "1421220")
      seed_seismic_intensity_levels!

      first_report = seismic_report_xml(event_id: "max-update-002", occurred_at: "2026-07-16T15:04:00+09:00", stations: { station.jma_code => "5+" })
      JmaPoller.new(xml: first_report).call
      observation = Observation.find_by(station: station, event_id: "max-update-002")
      expect(observation.seismic_intensity_level.label_ja).to eq("5強")

      clear_enqueued_jobs

      downgrade_report = seismic_report_xml(event_id: "max-update-002", occurred_at: "2026-07-16T15:04:00+09:00", stations: { station.jma_code => "1" })

      expect {
        JmaPoller.new(xml: downgrade_report).call
      }.not_to have_enqueued_job(ObservationReevaluationJob)

      observation.reload
      # 最大観測値は5強のまま（下方修正では更新されない）
      expect(observation.seismic_intensity_level.label_ja).to eq("5強")
      # ただし履歴（ObservationEvent）としては2件目が記録されている
      expect(observation.observation_events.count).to eq(2)
    end

    it "雨量: 下方修正（訂正値が下がる続報）はレコードのrainfall_mmを更新しない" do
      find_or_create_rainfall_station!
      first_xml = File.read(fixtures_root.join("rainfall.xml")) # 12.5mm, observed_at 2026-07-16T15:00:00+09:00
      JmaPoller.new(xml: first_xml).call
      observation = Observation.order(:id).last
      expect(observation.rainfall_mm).to eq(BigDecimal("12.5"))

      lower_value_xml = rainfall_report_xml(observed_at: "2026-07-16T15:00:00+09:00", rainfall_mm: "8.0")

      clear_enqueued_jobs
      expect {
        JmaPoller.new(xml: lower_value_xml).call
      }.not_to have_enqueued_job(ObservationReevaluationJob)

      observation.reload
      expect(observation.rainfall_mm).to eq(BigDecimal("12.5"))
    end

    it "未登録観測点（マスタに存在しない station_code）のデータは無視され、例外にもならない" do
      seed_seismic_intensity_levels!
      # station_codeに対応するStationを一切作成しない
      xml = seismic_report_xml(event_id: "unregistered-station-001", occurred_at: "2026-07-16T15:04:00+09:00", stations: { "0000000" => "5+" })

      expect {
        expect { JmaPoller.new(xml: xml).call }.not_to raise_error
      }.not_to change(Observation, :count)
    end
  end

  # ===========================================================================
  # QC10 / OWASP10 補足確認: エラーハンドリング（1件の失敗が他の取り込みを止めない）
  # ===========================================================================
  describe "QC10 エラーハンドリング: Atomフィードの1エントリの解析失敗が他のエントリの取り込みを止めない" do
    it "1件目のindividual XML取得が異常なコンテンツ（HTML等）でも、処理自体は例外にならず継続する" do
      find_or_create_seismic_station!(code: "seismic_pr53_partial_fail", jma_code: "1421220")
      seed_seismic_intensity_levels!

      feed_xml = File.read(fixtures_root.join("feed.xml"))
      html_error_body = "<html><body><h1>502 Bad Gateway</h1></body></html>"

      http_double = double("http")
      allow(Net::HTTP).to receive(:start).and_yield(http_double)

      feed_uri = URI("https://www.data.jma.go.jp/developer/xml/feed/eqvol.xml")
      feed_response = instance_double(Net::HTTPSuccess, body: feed_xml)
      allow(feed_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
      allow(http_double).to receive(:get).with(feed_uri.request_uri).and_return(feed_response)

      indiv_uri = URI("https://xml.data.jma.go.jp/data/seismic_sample.xml")
      html_response = instance_double(Net::HTTPSuccess, body: html_error_body)
      allow(html_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
      allow(http_double).to receive(:get).with(indiv_uri.request_uri).and_return(html_response)

      poller = JmaPoller.new(feed_url: feed_uri.to_s, rainfall_feed_url: nil)

      expect { poller.call }.not_to raise_error
      expect(Observation.count).to eq(0)
      expect(ProcessedJmaEntry.count).to eq(0)
    end
  end

  # ===========================================================================
  # ヘルパー
  # ===========================================================================

  def find_or_create_rainfall_station!
    Station.find_or_create_by!(code: "rainfall_tokyo_pr53") do |s|
      s.measurement_type = "rainfall"
      s.jma_code = "44132"
      %i[label_ja label_en label_fr label_zh label_ru label_es label_ar].each { |a| s.public_send("#{a}=", "東京雨量観測点") }
    end
  end

  def find_or_create_seismic_station!(code:, jma_code:)
    Station.find_or_create_by!(code: code) do |s|
      s.measurement_type = "seismic"
      s.jma_code = jma_code
      %i[label_ja label_en label_fr label_zh label_ru label_es label_ar].each { |a| s.public_send("#{a}=", "テスト震度観測点") }
    end
  end

  # 設計資料1.7の震度階級マスタ（0,1,2,3,4,5弱,5強,6弱,6強,7）と同じ並びで作成する
  def seed_seismic_intensity_levels!
    %w[0 1 2 3 4 5弱 5強 6弱 6強 7].each_with_index do |label, index|
      SeismicIntensityLevel.find_or_create_by!(code: "level_pr53_#{index}") do |l|
        l.sort_order = index
        %i[label_ja label_en label_fr label_zh label_ru label_es label_ar].each { |a| l.public_send("#{a}=", label) }
      end
    end
  end

  def create_active_seismic_policy!(station:, threshold_label:)
    plan = Plan.find_or_create_by!(code: "seismic_pr53") do |p|
      p.trigger_type = "seismic"
      %i[label_ja label_en label_fr label_zh label_ru label_es label_ar].each { |a| p.public_send("#{a}=", "震度連動") }
    end
    tier = PayoutTier.find_or_create_by!(code: "tier_pr53") do |t|
      t.amount_yen = 10_000
      %i[label_ja label_en label_fr label_zh label_ru label_es label_ar].each { |a| t.public_send("#{a}=", "1万円相当（模擬）") }
    end
    active_status = PolicyStatus.find_or_create_by!(code: "active") do |s|
      s.sort_order = 1
      %i[label_ja label_en label_fr label_zh label_ru label_es label_ar].each { |a| s.public_send("#{a}=", "有効") }
    end
    PolicyStatus.find_or_create_by!(code: "processing") do |s|
      s.sort_order = 2
      %i[label_ja label_en label_fr label_zh label_ru label_es label_ar].each { |a| s.public_send("#{a}=", "支払処理中") }
    end
    PayoutStatus.find_or_create_by!(code: "ordered") do |s|
      s.sort_order = 1
      %i[label_ja label_en label_fr label_zh label_ru label_es label_ar].each { |a| s.public_send("#{a}=", "指図済") }
    end

    user = User.create!(google_sub: "google-sub-pr53-#{SecureRandom.hex(4)}")
    policy = Policy.create!(
      user: user, plan: plan, station: station, payout_tier: tier,
      policy_status: active_status, threshold: threshold_label
    )
    # 固定日付ではなく実行時刻からの相対値で免責期間・有効期間を設定する
    policy.update_columns(waiting_until: 1.day.ago, expires_at: 1.year.from_now)
    policy
  end

  # 複数の観測点コード=>震度(内部表記可)を1つのReportにまとめたXMLを組み立てる
  def seismic_report_xml(event_id:, occurred_at:, stations:, status: "通常")
    intensity_stations = stations.map do |code, intensity|
      "<IntensityStation><Code>#{code}</Code><Int>#{intensity}</Int></IntensityStation>"
    end.join

    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <Report xmlns="http://xml.kishou.go.jp/jmaxml1/">
        <Control><Status>#{status}</Status></Control>
        <Head>
          <EventID>#{event_id}</EventID>
          <ReportDateTime>#{occurred_at}</ReportDateTime>
        </Head>
        <Body>
          <Earthquake><OriginTime>#{occurred_at}</OriginTime></Earthquake>
          <Intensity>
            <Observation>
              <Pref>
                <Area>
                  <City>
                    #{intensity_stations}
                  </City>
                </Area>
              </Pref>
            </Observation>
          </Intensity>
        </Body>
      </Report>
    XML
  end

  def rainfall_report_xml(observed_at:, rainfall_mm:, status: "通常")
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <Report xmlns="http://xml.kishou.go.jp/jmaxml1/">
        <Control><Status>#{status}</Status></Control>
        <Head><ReportDateTime>#{observed_at}</ReportDateTime></Head>
        <Body>
          <MeteorologicalInfo>
            <TimeSeriesInfo>
              <TimeDefines>
                <TimeDefine timeId="1"><DateTime>#{observed_at}</DateTime></TimeDefine>
              </TimeDefines>
              <Item>
                <Station><Code>44132</Code></Station>
                <Kind><Property>
                  <Type>降水量</Type>
                  <Precipitation type="前１時間降水量" refID="1">#{rainfall_mm}</Precipitation>
                </Property></Kind>
              </Item>
            </TimeSeriesInfo>
          </MeteorologicalInfo>
        </Body>
      </Report>
    XML
  end

  # 別プロセス（サブプロセスのbundle exec rspec）を起動する前に、接続先が想定どおりの
  # ローカルSQLiteテストDB（storage/test.sqlite3）であることを検証する。開発者のシェルに
  # 本番向けDATABASE_URL等が設定されたまま誤って別プロセスに引き継がれ、意図しない
  # 接続先に対してテストスイートが走ってしまう事故を防ぐための安全確認。
  def assert_local_sqlite_test_db!
    config = ActiveRecord::Base.configurations.configs_for(env_name: "test").first
    expected_path = Rails.root.join("storage", "test.sqlite3")
    actual_path = Rails.root.join(config.database.to_s)

    return if config.adapter == "sqlite3" && actual_path == expected_path

    raise "安全チェック失敗: test環境の接続先がローカルの#{expected_path}ではありません" \
          "（adapter=#{config.adapter}, database=#{actual_path}）。サブプロセスの起動を中止します。"
  end
end
