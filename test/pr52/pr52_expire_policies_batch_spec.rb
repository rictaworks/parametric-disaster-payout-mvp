# PR #52「契約期間満了バッチを追加」
#
# PR本文に書かれた「非エンジニア向けユーザーテスト手順」（テスト1〜3、および参考の
# rakeタスク単体実行）を自動再現するテスト。あわせて、PR本文の技術的な内容
# （「対象は active / cap_reached のみ」「べき等」）と、design document 1.5 F4 /
# 状態遷移図（有効→失効、上限到達→失効。pending・processing・cancelled は対象外）に
# 明記された仕様を、境界値・べき等性・データ整合性の観点から検証する。
#
# 対応する手順:
#   テスト1: 期限切れの「有効」な契約が、バッチ実行後に「失効」へ変わる
#            -> "テスト1" セクション（+ 技術的内容に明記された cap_reached も同様に確認）
#   テスト2: 期限切れでも「待機中（免責期間中）」の契約は変わらない
#            -> "テスト2" セクション
#   テスト3: 期限切れでも「解約済み」の契約は変わらない
#            -> "テスト3" セクション
#   （参考）: `bin/rails expire_policies` をターミナルから直接実行する
#            -> "（参考）rake expire_policies" セクション（別プロセスをspawnして検証）
#
# 過去のPR（pr55〜pr59）のレビュー指摘を踏まえ、以下を徹底する:
#   - 固定の絶対日付（例: "2027-07-15"）はバッチ判定に使う日付には使わず、
#     travel_to で固定した基準時刻からの相対値（1.day.ago 等）のみを用いる
#   - 「〜にならないこと」だけでなく、状態変化そのもの（肯定的な結果）も確認する
#   - 別プロセス（rake タスク）を spawn する箇所では、DATABASE_URL を子プロセスの
#     環境から明示的に除去し、接続先が意図した storage/test.sqlite3 であることを
#     実行前に検証してから実行する
#
# あわせて QC10（エラーハンドリング・データ整合性）、OWASP10（特に A01 Broken Access
# Control: このバッチを直接叩ける公開エンドポイントが存在しないこと、A08 Software
# and Data Integrity Failures: べき等性・排他制御・意図しない属性書き換えがないこと）
# の該当観点を確認する。
#
# 実行方法（開発/テストDBのみを対象。本番サーバーへは一切接続しない。
# config/database.yml の test 環境は sqlite3 の storage/test.sqlite3 を使用する）:
#   cd src/backend
#   RAILS_ENV=test bin/rails db:test:prepare
#   bundle exec rspec ../../test/pr52/pr52_expire_policies_batch_spec.rb

require "rails_helper"
require "open3"

RSpec.describe "PR52: 契約期間満了バッチ（ExpirePolicies）", type: :model do
  include ActiveSupport::Testing::TimeHelpers

  let(:plan) { find_or_create_plan("seismic_pr52") }
  let(:station) { find_or_create_station("seismic_tokyo_pr52") }
  let(:payout_tier) { find_or_create_payout_tier("ten_thousand_pr52") }

  # ExpirePolicies は内部で PolicyStatus.find_by!(code: "expired") を直接参照するため、
  # 各exampleがどのステータスを明示的に使うかに関わらず、6つのステータス（design document
  # 1.7 契約状態マスタ）を毎回 let! で確実に投入しておく（test:prepareはスキーマのみで
  # db:seedのマスタ投入は行わないため）。
  let!(:pending_status)     { find_or_create_policy_status("pending", 0, "待機中") }
  let!(:active_status)      { find_or_create_policy_status("active", 1, "有効") }
  let!(:processing_status)  { find_or_create_policy_status("processing", 2, "支払処理中") }
  let!(:cap_reached_status) { find_or_create_policy_status("cap_reached", 3, "上限到達") }
  let!(:cancelled_status)   { find_or_create_policy_status("cancelled", 4, "解約") }
  let!(:expired_status)     { find_or_create_policy_status("expired", 5, "失効") }

  # PR本文のコンソール手順（policy.update_columns(expires_at: 1.day.ago)）を再現するヘルパー。
  # expires_at は必ず呼び出し元が渡す相対値（1.day.ago 等）を使うこと。
  def build_policy(status:, expires_at:, terminated_at: nil)
    user = User.create!(google_sub: "google-sub-pr52-#{SecureRandom.hex(6)}")
    policy = Policy.create!(
      user: user, plan: plan, station: station, payout_tier: payout_tier,
      policy_status: status, threshold: "5強"
    )
    policy.update_columns(waiting_until: 100.days.ago, expires_at: expires_at, terminated_at: terminated_at)
    policy
  end

  # ---------------------------------------------------------------------
  # テスト1: 期限切れの「有効」な契約が、バッチ実行後に「失効」へ変わる
  # ---------------------------------------------------------------------
  describe "テスト1: 期限切れの「有効」な契約がバッチ実行後に「失効」へ変わる" do
    it "バッチ実行前は「有効」のままである（PR本文の1.の期待結果）" do
      policy = build_policy(status: active_status, expires_at: 1.day.ago)

      expect(policy.reload.policy_status.code).to eq("active")
    end

    it "ExpirePolicies.call の結果は status=:ok・updated_countを含み、対象契約が「失効」に変わる（PR本文の2.〜3.）" do
      policy = build_policy(status: active_status, expires_at: 1.day.ago)

      result = ExpirePolicies.call

      expect(result.status).to eq(:ok)
      expect(result).to be_success
      expect(result.updated_count).to be >= 1

      expect(policy.reload.policy_status.code).to eq("expired")
    end

    it "技術的内容に明記された「上限到達（cap_reached）」も期限切れなら同様に「失効」へ変わる" do
      policy = build_policy(status: cap_reached_status, expires_at: 1.day.ago)

      result = ExpirePolicies.call

      expect(result).to be_success
      expect(policy.reload.policy_status.code).to eq("expired")
    end
  end

  # ---------------------------------------------------------------------
  # テスト2: 期限切れでも「待機中（免責期間中）」の契約は変わらない
  # ---------------------------------------------------------------------
  describe "テスト2: 期限切れでも「待機中（免責期間中）」の契約は変わらない" do
    it "バッチ実行前は「待機中」のままである" do
      policy = build_policy(status: pending_status, expires_at: 1.day.ago)

      expect(policy.reload.policy_status.code).to eq("pending")
    end

    it "バッチ実行後もエラーなく完了し、「待機中」のまま変化しない（重大な不具合になり得るためPR本文が明記）" do
      policy = build_policy(status: pending_status, expires_at: 1.day.ago)

      expect { ExpirePolicies.call }.not_to raise_error

      expect(policy.reload.policy_status.code).to eq("pending")
      # 「変わらないこと」だけでなく、明示的にexpiredでないことも二重に確認する
      expect(policy.policy_status.code).not_to eq("expired")
    end
  end

  # ---------------------------------------------------------------------
  # テスト3: 期限切れでも「解約済み」の契約は変わらない
  # ---------------------------------------------------------------------
  describe "テスト3: 期限切れでも「解約済み」の契約は変わらない" do
    it "バッチ実行前は「解約」のままである" do
      policy = build_policy(status: cancelled_status, expires_at: 1.day.ago, terminated_at: 2.days.ago)

      expect(policy.reload.policy_status.code).to eq("cancelled")
    end

    it "バッチ実行後もエラーなく完了し、「解約」のまま変化しない。terminated_at等の属性も書き換わらない（OWASP A08）" do
      terminated_at = 2.days.ago
      policy = build_policy(status: cancelled_status, expires_at: 1.day.ago, terminated_at: terminated_at)

      expect { ExpirePolicies.call }.not_to raise_error

      policy.reload
      expect(policy.policy_status.code).to eq("cancelled")
      expect(policy.terminated_at).to be_within(1.second).of(terminated_at)
    end
  end

  # ---------------------------------------------------------------------
  # 追加観点: 状態遷移図に定義のない「支払処理中（processing）」は対象外
  # ---------------------------------------------------------------------
  describe "追加観点: 「支払処理中（processing）」は期限切れでも対象外（状態遷移図に定義なし）" do
    it "processingのまま変化しない" do
      policy = build_policy(status: processing_status, expires_at: 1.day.ago)

      ExpirePolicies.call

      expect(policy.reload.policy_status.code).to eq("processing")
    end
  end

  # ---------------------------------------------------------------------
  # 追加観点: 境界値（expires_at がちょうど基準時刻の場合を含む／含まない）
  # ---------------------------------------------------------------------
  describe "追加観点: 境界値（QC10 エラーハンドリング・仕様どおりの境界判定）" do
    it "expires_atがバッチ実行時刻とちょうど同時刻の契約も「期限超過」として対象になる（PR本文『期限が過ぎた』を<=で判定）" do
      travel_to(Time.current) do
        boundary_time = Time.current
        policy = build_policy(status: active_status, expires_at: boundary_time)

        result = ExpirePolicies.call(now: boundary_time)

        expect(result.updated_count).to be >= 1
        expect(policy.reload.policy_status.code).to eq("expired")
      end
    end

    it "expires_atがバッチ実行時刻よりわずかに未来の契約は対象外のまま「有効」を維持する" do
      travel_to(Time.current) do
        now = Time.current
        policy = build_policy(status: active_status, expires_at: now + 1.second)

        ExpirePolicies.call(now: now)

        expect(policy.reload.policy_status.code).to eq("active")
      end
    end
  end

  # ---------------------------------------------------------------------
  # 追加観点: べき等性（PR本文の技術的な内容「同じ契約に対して何度実行しても
  # 二重に処理されない」／テスト2手順の「件数の多少は問題ではない」という注記の裏付け）
  # ---------------------------------------------------------------------
  describe "追加観点: べき等性（OWASP A08 Software and Data Integrity Failures）" do
    it "同一契約に対して2回続けて実行しても、2回目は更新件数0件で状態も「失効」のまま変わらない" do
      policy = build_policy(status: active_status, expires_at: 1.day.ago)

      first_result = ExpirePolicies.call
      expect(policy.reload.policy_status.code).to eq("expired")
      expect(first_result.updated_count).to be >= 1

      second_result = ExpirePolicies.call

      expect(second_result).to be_success
      expect(second_result.updated_count).to eq(0)
      expect(policy.reload.policy_status.code).to eq("expired")
    end
  end

  # ---------------------------------------------------------------------
  # 追加観点: OWASP A01 Broken Access Control
  # このバッチをWebから直接呼び出せる公開エンドポイントが存在しないこと
  # ---------------------------------------------------------------------
  describe "追加観点: OWASP A01 Broken Access Control（公開エンドポイントの不在確認）" do
    it "routes.rb にExpirePoliciesを直接起動するHTTPエンドポイントが定義されていない" do
      all_routes = Rails.application.routes.routes.map do |r|
        "#{r.verb} #{r.path.spec}"
      end.join("\n")

      expect(all_routes.downcase).not_to include("expire")
    end

    it "コントローラ配下にExpirePoliciesを呼び出すコードが存在しない（Rakeタスク経由のみが正規の実行経路）" do
      controllers_dir = Rails.root.join("app", "controllers")
      matches = Dir.glob(controllers_dir.join("**", "*.rb")).select do |path|
        File.read(path).include?("ExpirePolicies")
      end

      expect(matches).to be_empty
    end
  end

  # =======================================================================
  # フィクスチャ生成ヘルパー
  # =======================================================================

  def find_or_create_plan(code)
    Plan.find_or_create_by!(code: code) do |p|
      p.trigger_type = "seismic"
      %i[label_ja label_en label_fr label_zh label_ru label_es label_ar].each { |attr| p.public_send("#{attr}=", "震度連動") }
    end
  end

  def find_or_create_station(code)
    Station.find_or_create_by!(code: code) do |s|
      s.measurement_type = "seismic"
      %i[label_ja label_en label_fr label_zh label_ru label_es label_ar].each { |attr| s.public_send("#{attr}=", "東京震度観測点") }
    end
  end

  def find_or_create_payout_tier(code)
    PayoutTier.find_or_create_by!(code: code) do |t|
      t.amount_yen = 10_000
      %i[label_ja label_en label_fr label_zh label_ru label_es label_ar].each { |attr| t.public_send("#{attr}=", "1万円相当（模擬）") }
    end
  end

  def find_or_create_policy_status(code, sort_order, label_ja)
    PolicyStatus.find_or_create_by!(code: code) do |s|
      s.sort_order = sort_order
      %i[label_ja label_en label_fr label_zh label_ru label_es label_ar].each { |attr| s.public_send("#{attr}=", label_ja) }
    end
  end
end

# ---------------------------------------------------------------------
# （参考）rake expire_policies をターミナルから直接実行
# ---------------------------------------------------------------------
# 上のRSpec.describeブロックはトップレベルの let!（マスタデータ投入）を
# 各exampleの前に実行するため、そのexample中はRSpecプロセス側のトランザクションが
# 開いたままになる。SQLite3はプロセスをまたいだ書き込み同時アクセスに弱く、その状態で
# 別プロセス（本セクションのrakeタスク）が同じDBファイルへ書き込もうとすると
# `SQLite3::BusyException: database is locked` になる。そのため、別プロセスをspawnする
# 本セクションは独立したトップレベルの RSpec.describe に分離し、上のブロックの
# let!/before フックの影響（開いたままのトランザクション）を受けないようにしている。
#
# さらに、別プロセスの書き込みはRSpec本体のトランザクションロールバックの対象外で
# 実際にコミットされてしまう。共有の storage/test.sqlite3 を対象にすると、他の
# テストファイル（同一 bundle exec rspec プロセス内で後から実行されるもの）が
# 期待するマスタデータと衝突しうるため、以下ではこのテスト専用の使い捨てSQLite
# ファイルへ隔離している（database.yml の TEST_DATABASE_PATH 参照）。
RSpec.describe "PR52: 契約期間満了バッチ（参考: rake expire_policiesの直接実行）", type: :model do
  # DATABASE_URL のような本番向け環境変数を継承したまま、実サーバー用プロセスとは
  # 別のRailsプロセス（rakeタスク）をspawnすると、開発者のシェル環境によっては
  # 意図せず本番/共有DBを操作しかねない。そのため、子プロセスのenvから明示的に
  # DATABASE_URL を除去する（nilを指定するとProcess.spawn/Open3はそのキーを子の
  # 環境変数から削除する仕様）。
  #
  # さらに、このテストは別プロセスとして実際にDBへコミットする（RSpec本体の
  # トランザクションロールバックが効かない）ため、共有の storage/test.sqlite3 を
  # 対象にすると、同一プロセス内で後から実行される他のテストファイルが
  # find_or_create_by! で参照するマスタ行（例: PolicyStatus code="active"）と
  # ラベル値の食い違いによる一意制約違反を起こしうる。そのため
  # config/database.yml の TEST_DATABASE_PATH 上書きを使い、このテスト専用の
  # 使い捨てSQLiteファイル（tmp/配下）へ隔離する。
  def sanitized_test_env(database_path)
    { "RAILS_ENV" => "test", "DATABASE_URL" => nil, "TEST_DATABASE_PATH" => database_path.to_s }
  end

  def assert_local_sqlite_test_db!(env, backend_root, expected_path)
    check_script = "config = ActiveRecord::Base.configurations.configs_for(env_name: 'test').first; " \
                    "puts [ config.adapter, config.database ].join('|')"

    output, status = Open3.capture2(env, "bundle", "exec", "rails", "runner", check_script, chdir: backend_root.to_s)
    raise "test環境の接続先確認に失敗しました: #{output}" unless status.success?

    adapter, database = output.strip.split("|")
    actual_path = backend_root.join(database.to_s)

    return if adapter == "sqlite3" && actual_path == backend_root.join(expected_path.to_s)

    raise "安全チェック失敗: test環境の接続先が想定の#{expected_path}ではありません" \
          "（adapter=#{adapter}, database=#{actual_path}）。DATABASE_URL等の環境変数が" \
          "接続先を上書きしていないか確認してください。rakeタスクの実行は中止します。"
  end

  it "エラーなく正常終了し、『Expired N policies』のように処理件数が表示され、実際にDBの状態が変わる" do
    backend_root = Rails.root
    isolated_db_path = backend_root.join("tmp", "pr52_expire_policies_rake_#{SecureRandom.hex(8)}.sqlite3")
    env = sanitized_test_env(isolated_db_path)
    assert_local_sqlite_test_db!(env, backend_root, isolated_db_path)

    schema_output, schema_status = Open3.capture2(env, "bundle", "exec", "rails", "db:schema:load", chdir: backend_root.to_s)
    expect(schema_status).to be_success, "隔離DBへのスキーマ投入に失敗しました: #{schema_output}"

    google_sub = "google-sub-pr52-rake-#{SecureRandom.hex(6)}"

    # RSpecプロセス側は use_transactional_fixtures によりexample終了時にロールバック
    # されるため、別プロセス（rakeタスク）からは見えない。そこで、rakeタスクが対象と
    # すべきデータ（および ExpirePolicies が内部で参照する「expired」ステータス）の
    # 作成そのものを、rakeタスクと同じ「別プロセス」内で committed な状態として行う
    # （rails runner による1回のセットアップ）。
    setup_script = <<~RUBY
      plan = Plan.find_or_create_by!(code: "seismic_pr52_rake") do |p|
        p.trigger_type = "seismic"
        %i[label_ja label_en label_fr label_zh label_ru label_es label_ar].each { |a| p.public_send("\#{a}=", "震度連動") }
      end
      station = Station.find_or_create_by!(code: "seismic_tokyo_pr52_rake") do |s|
        s.measurement_type = "seismic"
        %i[label_ja label_en label_fr label_zh label_ru label_es label_ar].each { |a| s.public_send("\#{a}=", "東京震度観測点") }
      end
      tier = PayoutTier.find_or_create_by!(code: "ten_thousand_pr52_rake") do |t|
        t.amount_yen = 10_000
        %i[label_ja label_en label_fr label_zh label_ru label_es label_ar].each { |a| t.public_send("\#{a}=", "1万円相当（模擬）") }
      end
      # PolicyStatus は db/seeds.rb の正規値（code・sort_order・7言語ラベル）で
      # 投入する（隔離DBなので他ファイルとの衝突リスクはないが、実装が実際に
      # 参照するのと同じ正規のマスタ値を使うことで再現性を高める）。
      load Rails.root.join("db/seeds.rb")
      status_active = PolicyStatus.find_by!(code: "active")
      user = User.create!(google_sub: "#{google_sub}")
      policy = Policy.create!(user: user, plan: plan, station: station, payout_tier: tier, policy_status: status_active, threshold: "5強")
      policy.update_columns(waiting_until: 100.days.ago, expires_at: 1.day.ago)
      puts policy.id
    RUBY

    setup_output, setup_status = Open3.capture2(env, "bundle", "exec", "rails", "runner", setup_script, chdir: backend_root.to_s)
    expect(setup_status).to be_success, "セットアップ用rails runnerの実行に失敗しました: #{setup_output}"
    policy_id = setup_output.strip.to_i
    expect(policy_id).to be > 0

    task_output, task_status = Open3.capture2(env, "bundle", "exec", "rails", "expire_policies", chdir: backend_root.to_s)

    expect(task_status).to be_success, "rake expire_policies の実行に失敗しました（赤字エラーなし、が失敗パターンの逆）: #{task_output}"
    expect(task_output).to match(/Expired \d+ polic(?:y|ies)/)

    verify_script = "puts Policy.find(#{policy_id}).policy_status.code"
    verify_output, verify_status = Open3.capture2(env, "bundle", "exec", "rails", "runner", verify_script, chdir: backend_root.to_s)
    expect(verify_status).to be_success, "検証用rails runnerの実行に失敗しました: #{verify_output}"
    expect(verify_output.strip).to eq("expired")

    # 後片付け: このテストのために別プロセスでcommitした1件のみを、通常の
    # ActiveRecordの破棄操作で削除する（テストデータの後始末であり、
    # ファイル・ディレクトリの削除コマンドではない）
    cleanup_script = "policy = Policy.find(#{policy_id}); user = policy.user; policy.destroy!; user.destroy!"
    Open3.capture2(env, "bundle", "exec", "rails", "runner", cleanup_script, chdir: backend_root.to_s)
  end
end
