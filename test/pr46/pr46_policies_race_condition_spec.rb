# PR #46「契約登録API（POST /api/v1/policies）を追加：reCAPTCHA・マスタ検証・二重契約防止」
#
# PR本文は次のように述べている：
#   「1. 同時申込による二重契約のすり抜け：ほぼ同時に同じ人が同じ種類のプランへ2回申込
#      リクエストを送ると、重複チェックをすり抜けて契約が2件作成されてしまう可能性が
#      ありました。ユーザーの行をロックしてから重複チェック・作成を行うよう修正し、
#      同時に来ても必ず1件しか作成されないようにしました」
#
# 既存の spec/services/validate_and_create_policy_spec.rb には、この修正を検証する
# テストが既にあるが、`expect(user).to receive(:lock!).ordered` のように「呼び出し順序」を
# モックで確認するのみで、実際に2つのスレッドから本物の同時リクエストを送って
# 「本当に1件しか作られず、かつ両リクエストとも制御されたレスポンス（201 or 409）に
# 収束するか」までは検証していない。
#
# 本ファイルは、実スレッドで擬似的に同時リクエストを発生させ、上記の主張を実証的に
# 検証する。調査の結果、次の事実が判明した（本番サーバーには一切接続せず、開発/テスト
# 環境のSQLiteのみで検証・再現している）：
#
#   1. Rails(Arel)のSQLiteビジタは `SELECT ... FOR UPDATE` のロック句を黙って無視する
#      （Arel::Visitors::SQLite#visit_Arel_Nodes_Lock、ActiveRecord 7.2 で確認済み）。
#      つまり `user.lock!` はPostgreSQL（本番）では行ロックとして機能するが、
#      SQLite（本プロジェクトの開発/テスト環境）では実質的に何もロックしない。
#   2. その結果、duplicate_policy_exists? のチェックのタイミングが重なる本物の同時
#      リクエストを送ると、契約の作成（policy.save）を同時に試みた側の一方が
#      `ActiveRecord::StatementInvalid`（SQLite3::BusyException: database is locked）を
#      送出する。この例外は ValidateAndCreatePolicy#call のどこにもrescueされておらず、
#      呼び出し元（PoliciesController#create）にもrescueが無いため、そのまま
#      未処理例外としてコントローラの外まで伝播する。HTTP経由であれば、409 duplicate_policy
#      という制御された応答ではなく、素の500 Internal Server Error（開発環境なら
#      スタックトレース付きのエラーページ）になる。
#
# したがって「同時に来ても必ず1件しか作成されない」という主張は、契約の重複防止という
# 観点では概ね成立する（実際、2件同時に作成されてしまうことはなく、常に片方は失敗する）
# 一方で、「失敗する側が409という想定内のエラーで終わる」という前提は成立しておらず、
# 未処理の例外という形で漏れる。これは OWASP A04（Insecure Design：想定した防御機構が
# 環境によっては異なる失敗モードになる設計）・A09（Security Logging and Monitoring
# Failures：制御されない例外はエラーハンドリング・ログ設計の対象外になりやすい）に
# 該当し、QC10（エラーハンドリング）の観点でも「500ではなく422/409で拒否する」という
# 本プロジェクトの他のエンドポイントの方針と一貫していない。よって「重大」として報告し、
# 意図的に pending（既知バグとして記録するが赤のまま放置しない）とする。
#
# 実行方法（開発/テストDBのみを対象。本番サーバーへは一切接続しない）:
#   cd src/backend
#   RAILS_ENV=test bin/rails db:test:prepare
#   bundle exec rspec ../../test/pr46/pr46_policies_race_condition_spec.rb

require "rails_helper"

# 2つのスレッドの実行タイミングを揃えるための単純なランデブーバリア。
# ValidateAndCreatePolicy#duplicate_policy_exists? の「読み取り」が両方完了してから
# 双方が「書き込み（INSERT）」に進むよう、意図的にタイミングを揃える。
# armed? が false のときは何もしない（他のテストファイルに影響を与えないためのガード）。
class Pr46RaceRendezvous
  class << self
    def arm!(participants:)
      @mutex = Mutex.new
      @cond = ConditionVariable.new
      @participants = participants
      @ready = 0
      @armed = true
    end

    def disarm!
      @armed = false
    end

    def armed?
      !!@armed
    end

    def rendezvous!
      return unless armed?

      @mutex.synchronize do
        @ready += 1
        if @ready >= @participants
          @cond.broadcast
        else
          @cond.wait(@mutex, 5)
        end
      end
    end
  end
end

module Pr46RaceInstrumentation
  def duplicate_policy_exists?(*args)
    result = super
    Pr46RaceRendezvous.rendezvous!
    result
  end
end

ValidateAndCreatePolicy.prepend(Pr46RaceInstrumentation) unless ValidateAndCreatePolicy.ancestors.include?(Pr46RaceInstrumentation)

RSpec.describe "PR46（補足）: 同時申込に対する二重契約防止の実スレッド検証", type: :model do
  # 実スレッドで別コネクションから読み書きするため、外側のトランザクションによる
  # ロールバックには頼らず実際にコミットされる。共有の storage/test.sqlite3 を
  # 対象にすると、他のテストファイルが期待するマスタデータ（PolicyStatus等）と
  # 衝突しうる（test/pr52 で同種の問題が実際に発生し、専用DBへ隔離して解消した
  # 前例がある）。そのため、このdescribeブロックの間だけ ActiveRecord の接続先を
  # 使い捨ての専用SQLiteファイルへ切り替える。
  self.use_transactional_tests = false

  around do |example|
    run_against_isolated_database { example.run }
  end

  def run_against_isolated_database
    original_config = ActiveRecord::Base.connection_db_config.configuration_hash
    isolated_db_path = File.join(Dir.tmpdir, "pr46-race-condition-#{SecureRandom.hex(8)}.sqlite3")

    ActiveRecord::Base.connection_handler.clear_all_connections!
    ActiveRecord::Base.establish_connection(original_config.merge(database: isolated_db_path))
    load Rails.root.join("db/schema.rb")
    reset_model_column_information

    yield
  ensure
    ActiveRecord::Base.remove_connection
    ActiveRecord::Base.establish_connection(original_config)
    reset_model_column_information
  end

  def reset_model_column_information
    [ User, Plan, Station, PayoutTier, PolicyStatus, SeismicIntensityLevel, Policy ].each(&:reset_column_information)
  end

  def label(suffix)
    { label_ja: suffix, label_en: suffix, label_fr: suffix, label_zh: suffix, label_ru: suffix, label_es: suffix, label_ar: suffix }
  end

  let(:user) { User.create!(google_sub: "google-sub-pr46-race-#{SecureRandom.hex(4)}") }
  let(:plan) { Plan.create!(code: "seismic_pr46_race", trigger_type: "seismic", **label("震度連動")) }
  let(:station) { Station.create!(code: "seismic_tokyo_pr46_race", measurement_type: "seismic", **label("東京震度観測点")) }
  let(:payout_tier) { PayoutTier.create!(code: "ten_thousand_pr46_race", amount_yen: 10_000, **label("1万円相当（模擬）")) }
  let!(:pending_status) { PolicyStatus.create!(code: "pending", sort_order: 0, **label("待機中")) }
  let!(:active_status) { PolicyStatus.create!(code: "active", sort_order: 1, **label("有効")) }
  let!(:processing_status) { PolicyStatus.create!(code: "processing", sort_order: 2, **label("支払処理中")) }
  let!(:seismic_level_5_weak) { SeismicIntensityLevel.create!(code: "5_weak", sort_order: 5, **label("5弱")) }

  after do
    Pr46RaceRendezvous.disarm!
  end

  def build_service
    ValidateAndCreatePolicy.new(
      user: User.find(user.id),
      plan_id: plan.id,
      station_id: station.id,
      payout_tier_id: payout_tier.id,
      threshold: "5弱",
      recaptcha_token: "token-pr46-race"
    )
  end

  # 2つの結果は Result（成功/409失敗）か、rescueした例外オブジェクトのいずれか
  def run_two_concurrent_requests
    Pr46RaceRendezvous.arm!(participants: 2)

    outcomes = Array.new(2)
    threads = Array.new(2) do |i|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          recaptcha_double = instance_double(RecaptchaVerifier, valid?: true)
          allow(RecaptchaVerifier).to receive(:new).and_return(recaptcha_double)
          outcomes[i] = begin
            build_service.call
          rescue StandardError => e
            e
          end
        end
      end
    end
    threads.each(&:join)
    outcomes
  end

  it "重大（既知のギャップ・意図的red）: ほぼ同時の2リクエストのうち、重複と判定される側は" \
     "制御された409 duplicate_policy相当の結果になるべきだが、実際にはSQLite環境で" \
     "未処理のDB例外（ActiveRecord::StatementInvalid）を送出してしまう",
    pending: "SQLite(開発/テスト環境)ではArel::Visitors::SQLite#visit_Arel_Nodes_Lockが" \
             "FOR UPDATE句を無視するため、user.lock!は行ロックとして機能しない。その結果、" \
             "duplicate_policy_exists?のタイミングが重なる本物の同時リクエストでは、" \
             "後からINSERTを試みた側がActiveRecord::StatementInvalid" \
             "（SQLite3::BusyException: database is locked）を送出し、ValidateAndCreatePolicy#call" \
             "内でrescueされずそのまま伝播する（HTTP経由なら409ではなく素の500になる）。" \
             "本番相当の『同時申込は必ずどちらかが制御された409で終わる』という安全性は" \
             "現状のSQLite開発環境では再現できない。修正案としては、(a) policies に" \
             "user_id×プラン種別の一意制約を追加しRecordNotUniqueを409にマップする、" \
             "または (b) ActiveRecord::StatementInvalid/Deadlockedをrescueして409に" \
             "変換する、のいずれかの対応を検討する必要がある" do
    outcomes = run_two_concurrent_requests

    expect(outcomes).to all(be_a(ValidateAndCreatePolicy::Result))
    expect(outcomes.count(&:success?)).to eq(1)
    expect(outcomes.reject(&:success?).map(&:status)).to eq([ :conflict ])
    expect(Policy.where(user_id: user.id).count).to eq(1)
  end

  it "参考（現状の実挙動の記録）: 実際には片方が201相当で成功し、もう片方は409ではなく" \
     "未処理のActiveRecord::StatementInvalidを送出する。契約が2件作成されることはないが、" \
     "失敗側のエラーハンドリングが本番想定（409）とは異なる形で漏れている" do
    outcomes = run_two_concurrent_requests

    successes = outcomes.select { |o| o.is_a?(ValidateAndCreatePolicy::Result) && o.success? }
    raised_errors = outcomes.select { |o| o.is_a?(StandardError) }

    # 2件同時に作成されてしまう（真の二重契約）ことは無い
    expect(Policy.where(user_id: user.id).count).to eq(successes.length)
    expect(Policy.where(user_id: user.id).count).to be <= 1

    # ちょうど1件が成功し、残りは（現状のSQLite環境では）制御された409ではなく
    # 未処理のDB例外として観測される
    expect(successes.length).to eq(1)
    expect(raised_errors.length).to eq(1)
    expect(raised_errors.first).to be_a(ActiveRecord::StatementInvalid)
  end

  it "参照用: Policyモデルには user_id×プラン種別 の一意制約（DBレベル）が存在せず、" \
     "重複防止がアプリケーション層のロック（user.lock!）のみに依存していることを確認する" do
    # duplicate_policy_exists? はその時点のスナップショットを見るだけであり、
    # 一意制約のようなDBレベルの保証を伴わない限り、真の同時実行に対して万能ではない。
    # user_idを含む一意インデックスが存在しないことを確認し、アプリ層のみでの防止の
    # 限界（=真の安全網が無い）を明示する
    connection = ActiveRecord::Base.connection
    indexes = connection.indexes(:policies)

    unique_user_scoped_index = indexes.find { |i| i.unique && i.columns.include?("user_id") }

    expect(unique_user_scoped_index).to be_nil
  end
end
