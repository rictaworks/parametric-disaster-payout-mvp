# PR #49「トリガー判定(F3)を追加し支払・通知・キューの信頼性を強化」
#
# 対象は EvaluateTrigger（F3 evaluateTrigger）本体、および PR #49 マージ後に追加された
# 管理画面の模擬イベント注入（PR #56, /admin/simulated_events）を経由したエンドツーエンド経路。
#
# PR #49 自体の本文（非エンジニア向けユーザーテスト手順・手順4）には、
# 「震度・雨量が基準に達したら自動的に支払指図と通知を作る、というロジックは
#  模擬イベント注入用の管理画面がまだ存在しないため、現時点では画面上から直接
#  テストすることができない。この部分は自動テストで網羅的に確認済み。管理画面が
#  実装され次第、別のPRで『模擬イベントを注入して支払指図が生成されることを確認する』
#  手順をご案内する」と明記されている。
#
# 現在の main HEAD には PR #56 で当該管理画面（/admin/simulated_events）が実装済みのため、
# 本ファイルの「手順G」でその約束されていたエンドツーエンド確認を行う。
# それ以外の手順（手順A〜F）は、設計資料 1.5 節 F3 evaluateTrigger の自然言語仕様
# （免責明け・有効期間内・未払い・年間上限未満・閾値到達の5条件、冪等キーは支払発生時のみ
#  確定、上方修正での追加支払なし、下方修正での取消なし、欠測時は支払なし）を、
# PR #49 の実装（src/backend/app/services/evaluate_trigger.rb）が既存のアプリ側テストとは
# 独立した形で満たしているかどうかを検証する。
#
# あわせて QC10（エラーハンドリング：不正入力・欠測データでも例外にならず、想定された
# 応答/挙動になること）と OWASP10（特に A04 Insecure Design：同一契約×同一イベントに
# 対する二重支払の防止＝冪等性、A07 Identification and Authentication Failures：管理画面の
# BASIC認証が必須であること）の該当観点を確認する。
#
# [重要] 固定の絶対日時（"2026-07-15" 等）はハードコードしない。トリガー判定は
# 「免責明け時刻」「契約有効期間」「観測発生時刻」の前後関係そのものがロジックの核心のため、
# 各exampleの冒頭で `travel_to(Time.zone.now)` により実行時刻を凍結し、そこからの相対値
# （`waiting_until: frozen_now - 1.hour` 等）でシナリオを組み立てる。これにより実行タイミングに
# 依存せず前後関係が崩れない。
#
# 実行方法（開発/テストDBのみを対象。本番サーバーへは一切接続しない）:
#   cd src/backend
#   RAILS_ENV=test bin/rails db:test:prepare
#   bundle exec rspec ../../test/pr49/pr49_evaluate_trigger_spec.rb

require "rails_helper"

RSpec.describe "PR49: トリガー判定(F3)の5条件・冪等性・支払/通知の一体性", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  # 各exampleの実行時刻を凍結し、以降はすべて相対値でシナリオを組み立てる
  around do |example|
    travel_to(Time.zone.now) { example.run }
  end

  let(:user) { User.create!(google_sub: "google-sub-pr49-#{SecureRandom.hex(6)}") }

  let(:seismic_plan) do
    Plan.create!(
      code: "seismic_pr49_#{SecureRandom.hex(4)}",
      trigger_type: "seismic",
      label_ja: "震度連動", label_en: "Seismic-linked", label_fr: "Seismic-linked",
      label_zh: "Seismic-linked", label_ru: "Seismic-linked", label_es: "Seismic-linked", label_ar: "Seismic-linked"
    )
  end

  let(:rainfall_plan) do
    Plan.create!(
      code: "rainfall_pr49_#{SecureRandom.hex(4)}",
      trigger_type: "rainfall",
      label_ja: "降雨連動", label_en: "Rainfall-linked", label_fr: "Rainfall-linked",
      label_zh: "Rainfall-linked", label_ru: "Rainfall-linked", label_es: "Rainfall-linked", label_ar: "Rainfall-linked"
    )
  end

  let(:seismic_station) do
    Station.create!(
      code: "seismic_tokyo_pr49_#{SecureRandom.hex(4)}",
      measurement_type: "seismic",
      label_ja: "東京震度観測点", label_en: "Tokyo", label_fr: "Tokyo", label_zh: "Tokyo",
      label_ru: "Tokyo", label_es: "Tokyo", label_ar: "Tokyo"
    )
  end

  let(:rainfall_station) do
    Station.create!(
      code: "rainfall_tokyo_pr49_#{SecureRandom.hex(4)}",
      measurement_type: "rainfall",
      label_ja: "東京雨量観測点", label_en: "Tokyo rainfall", label_fr: "Tokyo rainfall", label_zh: "Tokyo rainfall",
      label_ru: "Tokyo rainfall", label_es: "Tokyo rainfall", label_ar: "Tokyo rainfall"
    )
  end

  let(:payout_tier) do
    PayoutTier.create!(
      code: "tier_pr49_#{SecureRandom.hex(4)}",
      amount_yen: 10_000,
      label_ja: "1万円相当（模擬）", label_en: "10000", label_fr: "10000", label_zh: "10000",
      label_ru: "10000", label_es: "10000", label_ar: "10000"
    )
  end

  # PolicyStatus/PayoutStatus の code は、EvaluateTrigger/Payout/ExecutePayout の内部実装が
  # "active" "cancelled" "expired" "processing" "cap_reached" "ordered" "completed_simulated"
  # "invalid" という固定のコード文字列で PolicyStatus.find_by!(code: ...) / TERMINAL_POLICY_STATUS_CODES
  # 定数照合を行っているため、他のマスタ（Plan/Station/PayoutTier等）とは異なりランダムな
  # サフィックスを付けてはならない（付けると「解約状態を上書きしない」等のロジックが
  # 正しく機能しているように見えて実際には一致せず誤判定になる）。既存のアプリ側テスト
  # （spec/services/evaluate_trigger_spec.rb, spec/requests/admin/simulated_events_spec.rb）も
  # 同じ理由で固定コードを使っている
  let(:pending_status)    { PolicyStatus.find_or_create_by!(code: "pending", sort_order: 0, label_ja: "待機中", label_en: "Pending", label_fr: "Pending", label_zh: "Pending", label_ru: "Pending", label_es: "Pending", label_ar: "Pending") }
  let(:active_status)     { PolicyStatus.find_or_create_by!(code: "active", sort_order: 1, label_ja: "有効", label_en: "Active", label_fr: "Active", label_zh: "Active", label_ru: "Active", label_es: "Active", label_ar: "Active") }
  let(:processing_status) { PolicyStatus.find_or_create_by!(code: "processing", sort_order: 2, label_ja: "支払処理中", label_en: "Processing", label_fr: "Processing", label_zh: "Processing", label_ru: "Processing", label_es: "Processing", label_ar: "Processing") }
  let(:cap_reached_status) { PolicyStatus.find_or_create_by!(code: "cap_reached", sort_order: 3, label_ja: "上限到達", label_en: "Cap reached", label_fr: "Cap reached", label_zh: "Cap reached", label_ru: "Cap reached", label_es: "Cap reached", label_ar: "Cap reached") }
  let(:cancelled_status)  { PolicyStatus.find_or_create_by!(code: "cancelled", sort_order: 4, label_ja: "解約", label_en: "Cancelled", label_fr: "Cancelled", label_zh: "Cancelled", label_ru: "Cancelled", label_es: "Cancelled", label_ar: "Cancelled") }
  let(:expired_status)    { PolicyStatus.find_or_create_by!(code: "expired", sort_order: 5, label_ja: "失効", label_en: "Expired", label_fr: "Expired", label_zh: "Expired", label_ru: "Expired", label_es: "Expired", label_ar: "Expired") }

  let(:ordered_status)   { PayoutStatus.find_or_create_by!(code: "ordered", sort_order: 0, label_ja: "指図済", label_en: "Ordered", label_fr: "Ordered", label_zh: "Ordered", label_ru: "Ordered", label_es: "Ordered", label_ar: "Ordered") }
  let(:completed_status) { PayoutStatus.find_or_create_by!(code: "completed_simulated", sort_order: 1, label_ja: "支払完了（模擬）", label_en: "Completed", label_fr: "Completed", label_zh: "Completed", label_ru: "Completed", label_es: "Completed", label_ar: "Completed") }
  let(:invalid_status)   { PayoutStatus.find_or_create_by!(code: "invalid", sort_order: 2, label_ja: "無効", label_en: "Invalid", label_fr: "Invalid", label_zh: "Invalid", label_ru: "Invalid", label_es: "Invalid", label_ar: "Invalid") }

  let(:level_4)        { SeismicIntensityLevel.create!(code: "4_pr49_#{SecureRandom.hex(4)}", sort_order: 4, label_ja: "4", label_en: "4", label_fr: "4", label_zh: "4", label_ru: "4", label_es: "4", label_ar: "4") }
  let(:level_5_weak)   { SeismicIntensityLevel.create!(code: "5w_pr49_#{SecureRandom.hex(4)}", sort_order: 5, label_ja: "5弱", label_en: "5w", label_fr: "5w", label_zh: "5w", label_ru: "5w", label_es: "5w", label_ar: "5w") }
  let(:level_5_strong) { SeismicIntensityLevel.create!(code: "5s_pr49_#{SecureRandom.hex(4)}", sort_order: 6, label_ja: "5強", label_en: "5s", label_fr: "5s", label_zh: "5s", label_ru: "5s", label_es: "5s", label_ar: "5s") }

  # ordered_status/pending_status/active_status/processing_status を必ず先に評価しておく
  # （PolicyStatus/PayoutStatus は sort_order/code の一意制約があるため、テストごとに
  # 独立したインスタンスを都度生成する）
  # 同様に、SeismicIntensityLevel も policy.threshold（"5弱" など）が参照する
  # ラベルに対応するマスタ行が存在しないと threshold_reached? が静かに false を
  # 返してしまう（未登録閾値は当該契約のみスキップする安全設計のため、テスト側の
  # マスタ不足も例外にならず単に「支払われない」結果に見えてしまう）。let は遅延評価の
  # ため、observation側でしか参照しない level（例: level_5_weak を policy.threshold の
  # 文字列としてしか使わない場合）は生成されないままになる。そのため全レベルをここで
  # 確実に生成しておく
  before do
    pending_status
    active_status
    processing_status
    cap_reached_status
    cancelled_status
    expired_status
    ordered_status
    completed_status
    invalid_status
    level_4
    level_5_weak
    level_5_strong
  end

  # waiting_until / expires_at / terminated_at は Policy の before_validation コールバックで
  # 上書きされてしまうため、create! 後に update_columns（バリデーション・コールバックを
  # 経由しない）で直接設定する。これは既存のアプリ側テスト（spec/services/evaluate_trigger_spec.rb,
  # spec/requests/admin/simulated_events_spec.rb）でも採用されている確立した手法
  def build_seismic_policy(threshold: "5弱", waiting_until:, expires_at:, terminated_at: nil, status: active_status)
    Policy.create!(
      user: user, plan: seismic_plan, station: seismic_station,
      payout_tier: payout_tier, policy_status: status, threshold: threshold
    ).tap do |policy|
      policy.update_columns(waiting_until: waiting_until, expires_at: expires_at, terminated_at: terminated_at)
    end
  end

  def build_rainfall_policy(threshold: "10 mm", waiting_until:, expires_at:, terminated_at: nil, status: active_status)
    Policy.create!(
      user: user, plan: rainfall_plan, station: rainfall_station,
      payout_tier: payout_tier, policy_status: status, threshold: threshold
    ).tap do |policy|
      policy.update_columns(waiting_until: waiting_until, expires_at: expires_at, terminated_at: terminated_at)
    end
  end

  # ここでの observation は「震度・雨量観測イベントが届いた」という一般的な状況を
  # 表すためのものであり、免責明け・有効期間・冪等性・年間上限といったF3の条件判定
  # そのものを検証する目的なので simulated: false（通常の実観測）とする。
  # 「気象庁の訓練報・試験報が判定から除外されること」自体は手順3側
  # （test/pr53）で simulated: true, admin_injected: false として別途検証している
  def seismic_observation(station:, event_id:, observed_at:, level:)
    Observation.create!(
      station: station, event_id: event_id, observed_at: observed_at,
      seismic_intensity_level: level, max_value: level.sort_order, simulated: false
    )
  end

  def rainfall_observation(station:, observed_at:, rainfall_mm:)
    Observation.create!(
      station: station, observed_at: observed_at,
      rainfall_mm: rainfall_mm, max_value: rainfall_mm, simulated: false
    )
  end

  # ---------------------------------------------------------------------
  # 手順A: 条件(1) 免責明け時刻の境界（免責期間中は支払われない）
  # 設計資料 1.5 F3: 「イベント発生時刻が契約の免責明け時刻以降か」
  # ---------------------------------------------------------------------
  describe "手順A: 免責期間中は支払われない" do
    it "免責明けの直前（1秒前）に発生したイベントでは支払指図を生成しない" do
      policy = build_seismic_policy(waiting_until: Time.current + 1.hour, expires_at: Time.current + 1.year)
      observation = seismic_observation(
        station: seismic_station, event_id: "pr49-waiting-before",
        observed_at: policy.waiting_until - 1.second, level: level_5_strong
      )

      result = EvaluateTrigger.call(observation)

      expect(result.payouts).to be_empty
      expect(Payout.count).to eq(0)
      expect(policy.reload.policy_status).to eq(active_status)
    end

    it "免責明け時刻ちょうどに発生したイベントは支払対象になる（以降=境界含む）" do
      policy = build_seismic_policy(waiting_until: Time.current + 1.hour, expires_at: Time.current + 1.year)
      observation = seismic_observation(
        station: seismic_station, event_id: "pr49-waiting-exact",
        observed_at: policy.waiting_until, level: level_5_strong
      )

      result = EvaluateTrigger.call(observation)

      expect(result.payouts.count).to eq(1)
      expect(Payout.count).to eq(1)
      expect(policy.reload.policy_status).to eq(processing_status)
    end
  end

  # ---------------------------------------------------------------------
  # 手順B: 条件(2) 契約有効期間内（解約・失効前）か
  # ---------------------------------------------------------------------
  describe "手順B: 契約有効期間外では支払われない／取込遅延時の扱い" do
    it "契約満了時刻より後に発生したイベントでは支払指図を生成しない" do
      policy = build_seismic_policy(
        waiting_until: Time.current - 1.day, expires_at: Time.current + 1.hour
      )
      observation = seismic_observation(
        station: seismic_station, event_id: "pr49-after-expiry",
        observed_at: policy.expires_at + 1.second, level: level_5_strong
      )

      result = EvaluateTrigger.call(observation)

      expect(result.payouts).to be_empty
      expect(Payout.count).to eq(0)
    end

    it "契約満了時刻ちょうどに発生したイベントは支払対象になる（以前=境界含む）" do
      policy = build_seismic_policy(
        waiting_until: Time.current - 1.day, expires_at: Time.current + 1.hour
      )
      observation = seismic_observation(
        station: seismic_station, event_id: "pr49-at-expiry",
        observed_at: policy.expires_at, level: level_5_strong
      )

      result = EvaluateTrigger.call(observation)

      expect(result.payouts.count).to eq(1)
    end

    it "解約時刻より後に発生したイベントでは支払われず、解約状態も上書きしない" do
      policy = build_seismic_policy(
        waiting_until: Time.current - 1.day, expires_at: Time.current + 1.year,
        terminated_at: Time.current - 1.hour, status: cancelled_status
      )
      observation = seismic_observation(
        station: seismic_station, event_id: "pr49-after-cancel",
        observed_at: policy.terminated_at + 1.second, level: level_5_strong
      )

      result = EvaluateTrigger.call(observation)

      expect(result.payouts).to be_empty
      expect(Payout.count).to eq(0)
      expect(policy.reload.policy_status).to eq(cancelled_status)
    end

    it "取込遅延により、解約前に実際には発生していたイベントが後から届いた場合は支払指図を生成し、解約状態は上書きしない" do
      # F2/F3仕様: 観測取込の遅延（気象庁配信遅延・管理画面注入の遅れ等）が起きても、
      # 「イベント発生時刻」基準で有効期間内かどうかを判定する。契約が既に解約されていても
      # 発生時刻自体が解約前であれば正当な支払対象であり、それを見逃してはならない
      policy = build_seismic_policy(
        waiting_until: Time.current - 1.day, expires_at: Time.current + 1.year,
        terminated_at: Time.current - 1.hour, status: cancelled_status
      )
      observation = seismic_observation(
        station: seismic_station, event_id: "pr49-before-cancel-delayed",
        observed_at: policy.terminated_at - 1.second, level: level_5_strong
      )

      result = EvaluateTrigger.call(observation)

      expect(result.payouts.count).to eq(1)
      # 支払指図が生成されても、既に確定している「解約」という終端状態を
      # 「支払処理中」で上書きしてはならない
      expect(policy.reload.policy_status).to eq(cancelled_status)
    end
  end

  # ---------------------------------------------------------------------
  # 手順C: 条件(3) 未払い＝冪等性（OWASP A04: 二重支払の防止）
  # ---------------------------------------------------------------------
  describe "手順C: 同一契約×同一イベントに対する二重支払の防止（冪等性）" do
    it "同一の観測を2回評価しても、既に支払済みキーが存在するため2件目の支払指図は生成されない" do
      policy = build_seismic_policy(waiting_until: Time.current - 1.day, expires_at: Time.current + 1.year)
      observation = seismic_observation(
        station: seismic_station, event_id: "pr49-idempotent",
        observed_at: Time.current, level: level_5_strong
      )

      first_result = EvaluateTrigger.call(observation)
      second_result = EvaluateTrigger.call(observation)

      expect(first_result.payouts.count).to eq(1)
      expect(second_result.payouts).to be_empty
      expect(Payout.count).to eq(1)
    end

    it "他プロセスが同一のidempotency_keyで既にPayoutを作成済みだった場合（レース想定）も追加の支払を作らない" do
      policy = build_seismic_policy(waiting_until: Time.current - 1.day, expires_at: Time.current + 1.year)
      observation = seismic_observation(
        station: seismic_station, event_id: "pr49-race-preexisting",
        observed_at: Time.current, level: level_5_strong
      )
      preexisting_key = "policy_#{policy.id}_event_#{Digest::SHA256.hexdigest(observation.event_id)}"
      Payout.create!(
        policy: policy, payout_tier: policy.payout_tier, payout_status: ordered_status,
        observation: observation, idempotency_key: preexisting_key, decided_at: Time.current
      )

      result = EvaluateTrigger.call(observation)

      expect(result.payouts).to be_empty
      expect(Payout.count).to eq(1)
    end

    it "DBレベルの一意制約により、同一idempotency_keyのPayoutは2件目の作成が拒否される（多重防御）" do
      policy = build_seismic_policy(waiting_until: Time.current - 1.day, expires_at: Time.current + 1.year)
      observation = seismic_observation(
        station: seismic_station, event_id: "pr49-unique-index",
        observed_at: Time.current, level: level_5_strong
      )
      key = "policy_#{policy.id}_event_#{Digest::SHA256.hexdigest(observation.event_id)}"
      Payout.create!(
        policy: policy, payout_tier: policy.payout_tier, payout_status: ordered_status,
        observation: observation, idempotency_key: key, decided_at: Time.current
      )

      expect do
        Payout.create!(
          policy: policy, payout_tier: policy.payout_tier, payout_status: ordered_status,
          observation: observation, idempotency_key: key, decided_at: Time.current
        )
      end.to raise_error(ActiveRecord::RecordInvalid)
    end

    it "並行挿入によるActiveRecord::RecordNotUniqueが1契約分で発生しても、例外を伝播させずに他の契約の判定を継続する", pending: false do
      # 実際のDBレベルのレース（2スレッド同時挿入）はSQLiteのロック挙動に依存し
      # 不安定になりやすいため、EvaluateTrigger内のrescue節そのものを
      # Payout.create!のスタブで意図的に発火させることで、レース時のフォールバック
      # 挙動（他契約への影響を残さないこと）を決定的に検証する
      losing_policy = build_seismic_policy(waiting_until: Time.current - 1.day, expires_at: Time.current + 1.year)
      other_user = User.create!(google_sub: "google-sub-pr49-race-other-#{SecureRandom.hex(6)}")
      winning_policy = Policy.create!(
        user: other_user, plan: seismic_plan, station: seismic_station,
        payout_tier: payout_tier, policy_status: active_status, threshold: "5弱"
      ).tap { |p| p.update_columns(waiting_until: Time.current - 1.day, expires_at: Time.current + 1.year) }

      observation = seismic_observation(
        station: seismic_station, event_id: "pr49-race-stubbed",
        observed_at: Time.current, level: level_5_strong
      )

      call_count = 0
      allow(Payout).to receive(:create!).and_wrap_original do |original_method, *args, **kwargs|
        call_count += 1
        raise ActiveRecord::RecordNotUnique, "duplicate key (simulated race)" if kwargs[:policy] == losing_policy

        original_method.call(*args, **kwargs)
      end

      result = EvaluateTrigger.call(observation)

      expect(call_count).to eq(2)
      expect(result.status).to eq(:success)
      expect(result.payouts.map(&:policy_id)).to contain_exactly(winning_policy.id)
      expect(Payout.where(policy: losing_policy).count).to eq(0)
      expect(Payout.where(policy: winning_policy).count).to eq(1)
    end
  end

  # ---------------------------------------------------------------------
  # 手順D: 条件(4) 年間支払回数が上限（2回）未満か／状態遷移「上限到達」
  # ---------------------------------------------------------------------
  describe "手順D: 年間支払上限（2回）と上限到達への状態遷移" do
    it "同一年内で3件目の閾値到達イベントには支払指図を生成しない" do
      policy = build_seismic_policy(waiting_until: Time.current - 1.day, expires_at: Time.current + 1.year)

      obs1 = seismic_observation(station: seismic_station, event_id: "pr49-cap-1", observed_at: Time.current, level: level_5_strong)
      obs2 = seismic_observation(station: seismic_station, event_id: "pr49-cap-2", observed_at: Time.current + 1.hour, level: level_5_strong)
      obs3 = seismic_observation(station: seismic_station, event_id: "pr49-cap-3", observed_at: Time.current + 2.hours, level: level_5_strong)

      EvaluateTrigger.call(obs1)
      EvaluateTrigger.call(obs2)
      result3 = EvaluateTrigger.call(obs3)

      expect(Payout.count).to eq(2)
      expect(result3.payouts).to be_empty
    end

    it "年をまたぐと年間支払回数はリセットされ、新しい年の1件目として支払対象になる" do
      policy = build_seismic_policy(waiting_until: Time.current - 1.day, expires_at: Time.current + 2.years)

      obs1 = seismic_observation(station: seismic_station, event_id: "pr49-cap-year-1", observed_at: Time.current, level: level_5_strong)
      obs2 = seismic_observation(station: seismic_station, event_id: "pr49-cap-year-2", observed_at: Time.current + 1.hour, level: level_5_strong)
      EvaluateTrigger.call(obs1)
      EvaluateTrigger.call(obs2)
      expect(Payout.count).to eq(2)

      # このexample自体が around フックの travel_to(ブロック形式)で既に時刻凍結済みのため、
      # ここでブロック付きの travel_to/travel を呼ぶと ActiveSupport::Testing::TimeHelpers が
      # 「travel_toの二重ネスト」として例外を送出する。ブロックなし（裸呼び出し）の travel_to は
      # 単純にスタブを上書きするだけでこの制限に掛からず、outerのaround側ensureで最終的に
      # 元の時刻へ復元されるため、ここでは裸の travel_to で1年後へ進める
      travel_to(1.year.since(Time.current))

      obs3 = seismic_observation(station: seismic_station, event_id: "pr49-cap-year-3", observed_at: Time.current, level: level_5_strong)
      result3 = EvaluateTrigger.call(obs3)
      expect(result3.payouts.count).to eq(1)
      expect(Payout.count).to eq(3)
    end

    it "2回分の支払を管理者が確定すると契約状態が「上限到達」へ遷移し、3件目はブロックされたまま" do
      policy = build_seismic_policy(waiting_until: Time.current - 1.day, expires_at: Time.current + 1.year)

      obs1 = seismic_observation(station: seismic_station, event_id: "pr49-cap-state-1", observed_at: Time.current, level: level_5_strong)
      obs2 = seismic_observation(station: seismic_station, event_id: "pr49-cap-state-2", observed_at: Time.current + 1.hour, level: level_5_strong)

      result1 = EvaluateTrigger.call(obs1)
      expect(policy.reload.policy_status).to eq(processing_status)

      # 1件目を管理者が模擬支払完了として確定する。まだ1件しか完了していないため active に戻る
      ExecutePayout.new(payout: result1.payouts.first).call
      expect(policy.reload.policy_status).to eq(active_status)

      result2 = EvaluateTrigger.call(obs2)
      expect(result2.payouts.count).to eq(1)
      ExecutePayout.new(payout: result2.payouts.first).call

      # 2件確定した時点で年間上限に達し「上限到達」へ遷移する
      expect(policy.reload.policy_status).to eq(cap_reached_status)

      obs3 = seismic_observation(station: seismic_station, event_id: "pr49-cap-state-3", observed_at: Time.current + 2.hours, level: level_5_strong)
      result3 = EvaluateTrigger.call(obs3)
      expect(result3.payouts).to be_empty
      expect(Payout.count).to eq(2)
      expect(policy.reload.policy_status).to eq(cap_reached_status)
    end
  end

  # ---------------------------------------------------------------------
  # 手順E: 続報による上方修正・下方修正の扱い
  # ---------------------------------------------------------------------
  describe "手順E: 続報（同一イベントの観測値更新）に対する挙動" do
    it "支払確定後に観測値がさらに上方修正されても追加の支払は発生しない" do
      policy = build_seismic_policy(waiting_until: Time.current - 1.day, expires_at: Time.current + 1.year)
      observation = seismic_observation(
        station: seismic_station, event_id: "pr49-upward",
        observed_at: Time.current, level: level_5_weak
      )

      first_result = EvaluateTrigger.call(observation)
      expect(first_result.payouts.count).to eq(1)

      # 続報で震度が5強に上方修正されたことを模す（IngestObservationEventが行う更新を模擬）
      observation.update_columns(seismic_intensity_level_id: level_5_strong.id, max_value: level_5_strong.sort_order)

      second_result = EvaluateTrigger.call(observation)

      expect(second_result.payouts).to be_empty
      expect(Payout.count).to eq(1)
    end

    it "支払確定後に観測値が下方修正されても、既に生成された支払は取り消されない" do
      policy = build_seismic_policy(waiting_until: Time.current - 1.day, expires_at: Time.current + 1.year)
      observation = seismic_observation(
        station: seismic_station, event_id: "pr49-downward",
        observed_at: Time.current, level: level_5_strong
      )

      first_result = EvaluateTrigger.call(observation)
      expect(first_result.payouts.count).to eq(1)
      payout = first_result.payouts.first

      # 何らかの事後訂正で観測値が閾値未満に下方修正されたことを模す
      observation.update_columns(seismic_intensity_level_id: level_4.id, max_value: level_4.sort_order)

      EvaluateTrigger.call(observation)

      expect(Payout.count).to eq(1)
      expect(payout.reload.payout_status).to eq(ordered_status)
    end
  end

  # ---------------------------------------------------------------------
  # 手順F: 欠測・不正入力時の挙動（QC10: エラーハンドリング）
  # ---------------------------------------------------------------------
  describe "手順F: 観測欠測・不正データでも例外にならず支払は発生しない" do
    it "observationがnilの場合はステータスignoredで安全に終了し、例外は発生しない（観測欠測時は支払なし）" do
      expect { EvaluateTrigger.call(nil) }.not_to raise_error
      result = EvaluateTrigger.call(nil)
      expect(result.status).to eq(:ignored)
      expect(result.payouts).to be_empty
    end

    it "max_valueを持たない（欠測相当の）observationはステータスignoredで安全に終了する" do
      blank_observation = Observation.new
      expect(blank_observation.max_value).to be_nil

      result = EvaluateTrigger.call(blank_observation)

      expect(result.status).to eq(:ignored)
      expect(result.payouts).to be_empty
    end

    it "観測値が閾値未満の場合は支払指図を生成しない" do
      policy = build_seismic_policy(waiting_until: Time.current - 1.day, expires_at: Time.current + 1.year)
      observation = seismic_observation(
        station: seismic_station, event_id: "pr49-below-threshold",
        observed_at: Time.current, level: level_4
      )

      result = EvaluateTrigger.call(observation)

      expect(result.payouts).to be_empty
      expect(Payout.count).to eq(0)
    end

    it "契約の降雨閾値が不正（数値化できない旧データ）でも、当該契約のみスキップし例外は発生しない", pending: false do
      policy = build_rainfall_policy(threshold: "10 mm", waiting_until: Time.current - 1.day, expires_at: Time.current + 1.year)
      policy.update_column(:threshold, "not-a-number")

      observation = rainfall_observation(station: rainfall_station, observed_at: Time.current, rainfall_mm: 50)

      expect { EvaluateTrigger.call(observation) }.not_to raise_error
      result = EvaluateTrigger.call(observation)
      expect(result.status).to eq(:success)
      expect(result.payouts).to be_empty
      expect(Payout.count).to eq(0)
    end
  end

  # ---------------------------------------------------------------------
  # 手順G: 管理画面の模擬イベント注入によるエンドツーエンド確認
  # （PR #49本文が「別のPRで案内する」としていた確認手順を、PR #56で実装された
  #  管理画面を使って本ファイルで実施する）
  # OWASP10 A07（管理画面はBASIC認証必須）も併せて確認する。
  # ---------------------------------------------------------------------
  describe "手順G: 管理画面から模擬イベントを注入し、支払指図・通知が自動生成されることを確認する" do
    include ActiveJob::TestHelper

    let(:admin_user) { "admin" }
    let(:admin_password) { "changeme-pr49" }
    let(:auth_headers) do
      { "Authorization" => "Basic #{Base64.strict_encode64("#{admin_user}:#{admin_password}")}" }
    end

    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("ADMIN_BASIC_USER").and_return(admin_user)
      allow(ENV).to receive(:[]).with("ADMIN_BASIC_PASSWORD").and_return(admin_password)
      ActiveJob::Base.queue_adapter = :test
    end

    after do
      clear_enqueued_jobs
      clear_performed_jobs
      ActiveJob::Base.queue_adapter = :test
    end

    it "BASIC認証なしでは401となり、模擬イベント注入画面にアクセスできない（OWASP A07）" do
      get "/admin/simulated_events"

      expect(response).to have_http_status(:unauthorized)
    end

    it "管理者が新規の震度イベントを注入すると観測が保存され、続報で閾値到達すると支払指図とアプリ内通知が生成される" do
      policy = build_seismic_policy(waiting_until: Time.current - 1.day, expires_at: Time.current + 1.year)

      post "/admin/simulated_events",
        headers: auth_headers,
        params: { station_id: seismic_station.id, event_mode: "new", seismic_intensity_level_id: level_4.id }
      expect(response).to redirect_to(admin_simulated_events_path)

      observation = Observation.find_by!(station: seismic_station, simulated: true)
      ObservationReevaluationJob.perform_now(observation.id)
      expect(Payout.count).to eq(0)

      post "/admin/simulated_events",
        headers: auth_headers,
        params: {
          station_id: seismic_station.id, event_mode: "follow_up",
          observation_id: observation.id, seismic_intensity_level_id: level_5_strong.id
        }
      expect(response).to redirect_to(admin_simulated_events_path)

      ObservationReevaluationJob.perform_now(observation.id)

      expect(Payout.count).to eq(1)
      payout = Payout.last
      expect(payout.payout_status).to eq(ordered_status)
      expect(policy.reload.policy_status).to eq(processing_status)

      notification = Notification.find_by(policy: policy, kind: Notification::KIND_PAYOUT_ORDERED)
      expect(notification).to be_present
      expect(notification.message).to eq(I18n.t("notifications.payout_ordered"))

      # 管理者が模擬支払完了操作を行うと、支払完了通知とアンケート依頼通知が生成される
      patch "/admin/api/payouts/#{payout.id}/complete", headers: auth_headers
      expect(response).to have_http_status(:ok)
      expect(payout.reload.payout_status).to eq(completed_status)
      expect(Notification.where(policy: policy, kind: Notification::KIND_PAYOUT_COMPLETED)).to exist
      expect(Notification.where(policy: policy, kind: Notification::KIND_SURVEY_REQUEST)).to exist
    end

    it "免責期間中の契約に対して模擬イベントを注入しても支払指図は生成されない（画面から直接確認できる範囲）" do
      build_seismic_policy(waiting_until: Time.current + 1.hour, expires_at: Time.current + 1.year)

      post "/admin/simulated_events",
        headers: auth_headers,
        params: { station_id: seismic_station.id, event_mode: "new", seismic_intensity_level_id: level_5_strong.id }

      observation = Observation.find_by!(station: seismic_station, simulated: true)
      ObservationReevaluationJob.perform_now(observation.id)

      expect(Payout.count).to eq(0)
    end
  end
end
