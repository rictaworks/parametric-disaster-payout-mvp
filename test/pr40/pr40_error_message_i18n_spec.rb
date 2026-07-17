# PR #40「モデル検証エラーをI18n化し、7言語のロケール定義を追加」
#
# 対象は Observation/Payout/Policy/SurveyResponse モデルのバリデーション
# （src/backend/app/models/）と、新設された7言語ロケールファイル
# （src/backend/config/locales/{en,ja,fr,zh,ru,es,ar}.yml）。
# 生文字列直書き（errors.add(:field, "...")）から I18n キー
# （errors.add(:field, :error_key)）への置き換えと、雨量観測点で event_id を
# 入力した際のメッセージが逆の意味になっていたバグ（P2）の修正
# （専用キー must_be_blank_for_rainfall_stations）を検証する。
#
# PR本文の「非エンジニア向けユーザーテスト手順」を、開発サーバーと同じ
# Rails環境（テストDB）上で自動テストとして再現する。
#   手順1: `cd src/backend`                                     -> "手順1"
#   手順2: 既存の関連spec（error_message_i18n_spec.rb /
#         domain_models_spec.rb）を実行し、0 failuresであること   -> "手順2"
#   手順3: ロケールを en/ja で切り替えて event_id の空欄メッセージが
#         変わることを確認する（rails runnerスクリプト相当）        -> "手順3"
#   手順4（任意）: 雨量観測点でevent_idを入力した際のP2バグ修正確認   -> "手順4"
#
# あわせて QC10（エラーハンドリング：モデルにハードコードされた生文字列が
# 残っていないこと／未知の入力でも例外にならないこと）と OWASP10
# （A03 Injection: ロケール値そのものはユーザー入力ではなく固定シンボルの
# ため注入リスクがないことの確認、A09 Security Logging and Monitoring
# Failures: バリデーションエラーの原因がキー単位でトレース可能なこと）の
# 該当観点も確認する。
#
# 実行方法（開発/テストDBのみを対象。本番サーバーへは一切接続しない。
# config/database.yml の test 環境は sqlite3 の storage/test.sqlite3 を使用する）:
#   cd src/backend
#   RAILS_ENV=test bin/rails db:test:prepare
#   bundle exec rspec ../../test/pr40/pr40_error_message_i18n_spec.rb --format documentation
#
# [重要] 「手順2」は実際に別プロセス（bundle exec rspec）をspawnして本文中の
# コマンドをそのまま再現する。SQLite3はプロセスをまたいだ同時書き込みに弱いため、
# 他のテストファイルのlet!/beforeフックでトランザクションが開いたままの状態と
# 干渉しないよう、本ファイルでは専用のトップレベル RSpec.describe に分離している
# （test/pr52/pr52_expire_policies_batch_spec.rb と同じ配慮）。
# 対象のspec自体はRSpecのトランザクショナルフィクスチャでロールバックされるため、
# 共有の storage/test.sqlite3 を汚染する心配はなく、TEST_DATABASE_PATHによる
# 隔離までは行っていない。

require "rails_helper"
require "open3"

RSpec.describe "PR40: 手順1 作業ディレクトリの前提確認(cd src/backend)" do
  it "Rails.root が src/backend を指しており、手順2で参照する2つのspecファイルがそこから見つかる" do
    expect(Rails.root.to_s).to end_with("src/backend")
    expect(File.exist?(Rails.root.join("spec/models/error_message_i18n_spec.rb"))).to be(true)
    expect(File.exist?(Rails.root.join("spec/models/domain_models_spec.rb"))).to be(true)
  end
end

# ---------------------------------------------------------------------
# 手順2（別プロセス）: 本文記載のコマンドをそのまま再現する
# ---------------------------------------------------------------------
RSpec.describe "PR40: 手順2 既存specの実行確認(別プロセス)" do
  it "`bundle exec rspec spec/models/error_message_i18n_spec.rb spec/models/domain_models_spec.rb` が0 failuresで完了する" do
    backend_root = Rails.root
    env = { "RAILS_ENV" => "test" }

    output, status = Open3.capture2e(
      env, "bundle", "exec", "rspec",
      "spec/models/error_message_i18n_spec.rb", "spec/models/domain_models_spec.rb",
      chdir: backend_root.to_s
    )

    expect(status).to be_success, "既存specの実行に失敗しました:\n#{output}"
    expect(output).to match(/(?:\A|\n)\d+ examples?, 0 failures/), "0 failuresの結果行が見つかりません:\n#{output}"
    expect(output).not_to match(/\d+ examples?, [1-9]\d* failures?/), "failuresが0件ではありません:\n#{output}"
  end
end

# ---------------------------------------------------------------------
# 手順3・4: rails runnerスクリプト相当をモデルへ直接RSpec化したもの
# （トランザクション内で完結するため、他のspecへの副作用はない）
# ---------------------------------------------------------------------
RSpec.describe "PR40: 手順3/4 ロケール切替によるバリデーションメッセージの確認", type: :model do
  let(:suffix) { "pr40_#{SecureRandom.hex(4)}" }

  def create_station(code:, measurement_type:, label:)
    Station.create!(
      code: code,
      measurement_type: measurement_type,
      label_ja: label, label_en: label, label_fr: label,
      label_zh: label, label_ru: label, label_es: label, label_ar: label
    )
  end

  let!(:seismic_station) do
    create_station(code: "demo_seismic_#{suffix}", measurement_type: "seismic", label: "テスト観測点")
  end

  let!(:rainfall_station) do
    create_station(code: "demo_rainfall_#{suffix}", measurement_type: "rainfall", label: "テスト雨量観測点")
  end

  # -----------------------------------------------------------------
  # 手順3: PR本文のrails runnerスクリプトそのままの再現
  #   [:en, :ja].each do |loc|
  #     I18n.locale = loc
  #     o = Observation.new(event_id: nil)
  #     o.station = <seismicなStation>
  #     o.valid?
  #     puts "#{loc}: #{o.errors[:event_id].inspect}"
  #   end
  # -----------------------------------------------------------------
  describe "手順3: ロケール切替でevent_idの空欄メッセージが変わる" do
    it "en: [\"can't be blank\"] になる" do
      I18n.with_locale(:en) do
        observation = Observation.new(event_id: nil, station: seismic_station)
        observation.valid?
        expect(observation.errors[:event_id]).to eq([ "can't be blank" ])
      end
    end

    it "ja: [\"を入力してください\"] になる" do
      I18n.with_locale(:ja) do
        observation = Observation.new(event_id: nil, station: seismic_station)
        observation.valid?
        expect(observation.errors[:event_id]).to eq([ "を入力してください" ])
      end
    end

    it "同一のObservationインスタンスでロケールを切り替えても、都度メッセージが変わる（キー固定・文言はI18n側の責務）" do
      observation = Observation.new(event_id: nil, station: seismic_station)

      I18n.with_locale(:en) do
        observation.valid?
        expect(observation.errors[:event_id]).to eq([ "can't be blank" ])
      end

      observation.errors.clear
      I18n.with_locale(:ja) do
        observation.valid?
        expect(observation.errors[:event_id]).to eq([ "を入力してください" ])
      end
    end

    # 設計資料 1.4「多言語対応：日本語・英語・フランス語・中国語・ロシア語・
    # スペイン語・アラビア語に対応する」を踏まえ、PR本文のen/ja 2言語だけでなく
    # 新設された7言語すべてでメッセージが空でなく、かつ実際のロケールファイルの
    # 値と一致することを確認する
    ALL_LOCALES = %i[ja en fr zh ru es ar].freeze

    it "7言語すべてでevent_idの空欄メッセージが設定され、config/locales/*.ymlの値と一致する" do
      ALL_LOCALES.each do |locale|
        expected = I18n.t("errors.messages.blank", locale: locale)
        expect(expected).not_to be_blank, "#{locale} の errors.messages.blank が空です"

        observation = Observation.new(event_id: nil, station: seismic_station)
        I18n.with_locale(locale) do
          observation.valid?
          expect(observation.errors[:event_id]).to eq([ expected ]), "#{locale} のメッセージが一致しません"
        end
      end
    end

    it "7言語のメッセージがすべて異なる文言になっている（コピー漏れで同一文言のまま、という不具合を検出する）" do
      messages = ALL_LOCALES.index_with { |locale| I18n.t("errors.messages.blank", locale: locale) }
      expect(messages.values.uniq.size).to eq(ALL_LOCALES.size), "文言が重複しているロケールがあります: #{messages}"
    end
  end

  # -----------------------------------------------------------------
  # 手順4（任意）: 雨量観測点バグ修正の確認
  #   I18n.locale = :ja
  #   station = <雨量のStation>
  #   o = Observation.new(station:, rainfall_mm: 50.0, event_id: "event-123", observed_at: Time.current)
  #   o.valid?
  #   puts o.errors[:event_id].inspect
  #   => ["雨量観測点では空欄にしてください"]
  # -----------------------------------------------------------------
  describe "手順4: 雨量観測点でevent_idを入力した場合のメッセージ(P2バグ修正)" do
    it "ja: [\"雨量観測点では空欄にしてください\"] が返る（修正前は逆の意味の文言だった）" do
      I18n.with_locale(:ja) do
        observation = Observation.new(
          station: rainfall_station,
          rainfall_mm: 50.0,
          event_id: "event-123",
          observed_at: Time.current
        )
        observation.valid?
        expect(observation.errors[:event_id]).to eq([ "雨量観測点では空欄にしてください" ])
      end
    end

    it "en: [\"must be blank for rainfall stations\"] が返る（他言語でも専用キーが使われている）" do
      I18n.with_locale(:en) do
        observation = Observation.new(
          station: rainfall_station,
          rainfall_mm: 50.0,
          event_id: "event-123",
          observed_at: Time.current
        )
        observation.valid?
        expect(observation.errors[:event_id]).to eq([ "must be blank for rainfall stations" ])
      end
    end

    it "震度観測点で同じevent_id入力は正常（バリデーションエラーにならない）であり、雨量観測点との意味の違いが取り違えられていない" do
      I18n.with_locale(:ja) do
        observation = Observation.new(
          station: seismic_station,
          seismic_intensity_level: SeismicIntensityLevel.create!(
            code: "level5weak_#{suffix}", sort_order: 5,
            label_ja: "5弱", label_en: "5w", label_fr: "5w", label_zh: "5w", label_ru: "5w", label_es: "5w", label_ar: "5w"
          ),
          event_id: "event-123",
          observed_at: Time.current
        )
        observation.valid?
        expect(observation.errors[:event_id]).to be_empty
      end
    end
  end

  # -----------------------------------------------------------------
  # QC10: モデルにハードコードされた生文字列のバリデーションメッセージが
  # 残っていないこと（errors.add(:field, "文字列") 形式ではなく
  # errors.add(:field, :key) 形式になっていること）
  # -----------------------------------------------------------------
  describe "QC10: バリデーションメッセージがハードコードされていない" do
    MODEL_FILES = %w[
      app/models/observation.rb
      app/models/payout.rb
      app/models/policy.rb
      app/models/survey_response.rb
    ].freeze

    it "対象4モデルのerrors.add呼び出しに生文字列(ダブル/シングルクォート)が直書きされていない" do
      hardcoded_lines = MODEL_FILES.flat_map do |path|
        full_path = Rails.root.join(path)
        expect(File.exist?(full_path)).to be(true), "#{path} が見つかりません"
        File.read(full_path).lines.select { |line| line.match?(/errors\.add\([^,]+,\s*["']/) }
      end

      expect(hardcoded_lines).to be_empty, "生文字列が直書きされた行があります:\n#{hardcoded_lines.join}"
    end
  end

  # -----------------------------------------------------------------
  # OWASP10 該当観点
  #   A03 Injection: ロケール切替に使う値は固定シンボルの集合(I18n.available_locales)
  #     に限定され、任意の外部文字列をI18n.locale=へ渡しても未対応ロケールとして
  #     拒否される（アプリ内で任意ロケール文字列をそのまま解釈しない）ことを確認する
  #   A09 Security Logging and Monitoring Failures: どのバリデーション規則に違反したか
  #     がエラーキー単位(:blank, :must_be_blank_for_rainfall_stations等)で機械可読に
  #     判別できること（＝生文字列の突き合わせに頼らず原因追跡できること）を確認する
  # -----------------------------------------------------------------
  describe "OWASP10: A03/A09 関連の確認" do
    it "A03: I18n.available_locales に無い任意の文字列をロケールとして設定しようとするとRailsの標準防御(InvalidLocale)が働く" do
      expect(I18n.available_locales).to match_array(%i[ja en fr zh ru es ar])

      expect do
        I18n.with_locale(:"'; DROP TABLE observations; --") { }
      end.to raise_error(I18n::InvalidLocale)
    end

    it "A09: event_idの空欄エラーはメッセージ文字列に関わらず:blankキーで機械的に検出できる（監査・監視上の追跡可能性）" do
      I18n.with_locale(:ja) do
        observation = Observation.new(event_id: nil, station: seismic_station)
        observation.valid?
        expect(observation.errors.of_kind?(:event_id, :blank)).to be(true)
      end

      I18n.with_locale(:ja) do
        observation = Observation.new(
          station: rainfall_station, rainfall_mm: 50.0, event_id: "event-123", observed_at: Time.current
        )
        observation.valid?
        expect(observation.errors.of_kind?(:event_id, :must_be_blank_for_rainfall_stations)).to be(true)
      end
    end
  end
end
