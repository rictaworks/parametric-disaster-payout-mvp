# PR #35「Stage 1: DBスキーマ・モデル・マスタデータを実装」
# PR本文に書かれた「非エンジニア向けユーザーテスト手順」（手順1〜4）を自動再現するテスト。
#
# 対応する手順:
#   手順1: cd src/backend && bundle install                         -> "bundle install が完了していること" セクション
#   手順2: bin/rails db:create db:migrate                            -> "マイグレーションでテーブル生成" セクション
#   手順3: bin/rails db:seed                                         -> "マスタデータ投入" セクション
#   手順4: bin/rails runner "...map(&:count).sum" が 26 になること   -> "マスタ合計26件" セクション
#
# 実行方法（開発/テストDBのみを対象。本番サーバーへは一切接続しない）:
#   cd src/backend
#   RAILS_ENV=test bin/rails db:test:prepare
#   bundle exec rspec ../../test/pr35/pr35_stage1_schema_and_seed_spec.rb
#
# 併せて QC10 / OWASP10 の該当観点（アクセス制御・データ整合性・個人情報の非保持）も確認する。

require "rails_helper"

RSpec.describe "PR35: Stage1 DBスキーマ・モデル・マスタデータ", type: :model do
  # -----------------------------------------------------------------
  # 手順1: bundle install が正常に完了していること
  #   （非エンジニアの「Bundle complete! と表示されること」を、依存関係の整合性チェックで代替検証する）
  # -----------------------------------------------------------------
  describe "手順1: bundle install（依存関係の整合性）" do
    it "Gemfile.lock が存在し、Bundler の依存解決に矛盾がない（bundle check相当）" do
      lockfile = Rails.root.join("Gemfile.lock")
      expect(File.exist?(lockfile)).to be(true)

      expect { Bundler.definition.specs }.not_to raise_error
    end

    it "本PRが前提とする主要gemがロック済みである" do
      locked_gem_names = Bundler.locked_gems.specs.map(&:name)

      %w[rails sqlite3 pg rspec-rails shoulda-matchers].each do |gem_name|
        expect(locked_gem_names).to include(gem_name)
      end
    end
  end

  # -----------------------------------------------------------------
  # 手順2: bin/rails db:create db:migrate によりテーブルが作られていること
  #   設計資料 ER図（1.7 マスタデータ件数 / 2. ER図）に定義された全エンティティを確認する
  # -----------------------------------------------------------------
  describe "手順2: db:create db:migrate（テーブル生成）" do
    let(:connection) { ActiveRecord::Base.connection }

    it "保留中のマイグレーションがない（db:migrateが最後まで完了している）" do
      expect { ActiveRecord::Migration.check_all_pending! }.not_to raise_error
    end

    it "設計資料ER図に定義された全テーブルが作成されている" do
      expected_tables = %w[
        users plans seismic_intensity_levels stations payout_tiers
        policy_statuses payout_statuses policies observations payouts
        notifications survey_responses
      ]

      expected_tables.each do |table_name|
        expect(connection.table_exists?(table_name)).to be(true), "テーブル #{table_name} が存在しません"
      end
    end

    it "users テーブルは google_sub のみを一意キーとして保持し、個人情報カラムを持たない（設計資料1.4 / OWASP A01 データ最小化）" do
      columns = connection.columns(:users).map(&:name)
      expect(columns).to include("google_sub")

      forbidden_pii_columns = %w[email name first_name last_name given_name family_name avatar_url phone_number address]
      expect(columns & forbidden_pii_columns).to be_empty
    end

    it "users.google_sub にDBレベルの一意インデックスがある（OWASP A08: アプリ層バリデーションだけに頼らない整合性担保）" do
      index = connection.indexes(:users).find { |i| i.columns == [ "google_sub" ] }
      expect(index).not_to be_nil
      expect(index.unique).to be(true)
    end

    it "payouts.idempotency_key にDBレベルの一意インデックスがある（同一契約×同一イベントの二重支払を防止）" do
      index = connection.indexes(:payouts).find { |i| i.columns == [ "idempotency_key" ] }
      expect(index).not_to be_nil
      expect(index.unique).to be(true)
    end

    it "policies が threshold / waiting_until（免責明け） / expires_at を保持する" do
      columns = connection.columns(:policies).map(&:name)
      expect(columns).to include("threshold", "waiting_until", "expires_at", "station_id")
    end

    it "主要な外部キー制約がDBレベルで定義されている（整合性のアプリ層依存を回避）" do
      fk_targets = connection.foreign_keys(:policies).map(&:to_table)
      expect(fk_targets).to include("users", "plans", "stations")

      payout_fk_targets = connection.foreign_keys(:payouts).map(&:to_table)
      expect(payout_fk_targets).to include("policies", "observations")
    end
  end

  # -----------------------------------------------------------------
  # 手順3・手順4: bin/rails db:seed を実行し、マスタ合計が26件になること
  #   「もう一度 db:seed を実行しても数値が変わらない」というPR本文の期待も検証する（べき等性）
  # -----------------------------------------------------------------
  describe "手順3・4: db:seed とマスタ合計26件" do
    let(:master_models) { [ Plan, SeismicIntensityLevel, Station, PayoutTier, PolicyStatus, PayoutStatus ] }
    let(:seed_path) { Rails.root.join("db/seeds.rb") }

    def total_master_count
      # PR本文の手順4のコマンドをそのまま再現する
      # bin/rails runner "puts [Plan, SeismicIntensityLevel, Station, PayoutTier, PolicyStatus, PayoutStatus].map(&:count).sum"
      [ Plan, SeismicIntensityLevel, Station, PayoutTier, PolicyStatus, PayoutStatus ].map(&:count).sum
    end

    it "初回の db:seed 実行でマスタ合計がちょうど26件になる" do
      expect(total_master_count).to eq(0)

      load seed_path

      expect(total_master_count).to eq(26)
    end

    it "設計資料1.7の内訳（プラン2・震度階級10・観測点3・支払額区分2・契約状態6・支払状態3）と一致する" do
      load seed_path

      expect(Plan.count).to eq(2)
      expect(SeismicIntensityLevel.count).to eq(10)
      expect(Station.count).to eq(3)
      expect(PayoutTier.count).to eq(2)
      expect(PolicyStatus.count).to eq(6)
      expect(PayoutStatus.count).to eq(3)
    end

    it "db:seed を複数回実行しても件数が増えない（べき等・重複投入防止）" do
      3.times { load seed_path }

      expect(total_master_count).to eq(26)
    end

    it "2回目以降の db:seed でも既存レコードの code は変化しない（find_or_initialize_by codeでの安全な再投入）" do
      load seed_path
      seismic_plan_id_before = Plan.find_by(code: "seismic").id

      load seed_path
      seismic_plan_id_after = Plan.find_by(code: "seismic").id

      expect(seismic_plan_id_after).to eq(seismic_plan_id_before)
    end
  end

  # -----------------------------------------------------------------
  # QC10 / OWASP10 観点の追加確認（DBスキーマ・モデル層に限定）
  # -----------------------------------------------------------------
  describe "QC10 / OWASP10 該当観点" do
    it "QC10-エラーハンドリング: 未登録コードでのマスタ検索は例外にならずnilを返す（想定内の失敗を握りつぶさず判定可能にする）" do
      load Rails.root.join("db/seeds.rb")
      expect(Plan.find_by(code: "not_a_real_plan_code")).to be_nil
    end

    it "OWASP A03 インジェクション対策: 各マイグレーションファイルが生SQL文字列補間を含まない" do
      migration_dir = Rails.root.join("db/migrate")
      offending_files = Dir.glob(migration_dir.join("*.rb")).select do |path|
        File.read(path) =~ /execute\s*\(?\s*["'].*#\{/m
      end

      expect(offending_files).to be_empty, "生SQL文字列補間の疑いがあるマイグレーション: #{offending_files.join(', ')}"
    end

    it "OWASP A08 データ整合性: legacy_survey_responses はユーザー削除時にカスケード削除され孤児レコードを残さない" do
      connection = ActiveRecord::Base.connection
      user_fk = connection.foreign_keys(:legacy_survey_responses).find { |fk| fk.to_table == "users" }

      expect(user_fk).not_to be_nil
      expect(user_fk.on_delete).to eq(:cascade)
    end

    it "OWASP A01 アクセス制御の前提: マスタ系テーブルのラベルは全7言語（設計資料1.4）に対応した必須カラムを持つ（未翻訳データの露出防止）" do
      load Rails.root.join("db/seeds.rb")

      %w[label_ja label_en label_fr label_zh label_ru label_es label_ar].each do |label_column|
        expect(Plan.where(label_column => [ nil, "" ]).count).to eq(0), "#{label_column} が未設定のPlanが存在します"
      end
    end
  end
end
