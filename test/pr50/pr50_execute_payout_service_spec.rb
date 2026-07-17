# PR #50「F4 支払完了（模擬）とアプリ内通知を追加」（サービス層ホワイトボックステスト）
#
# pr50_admin_payout_complete_spec.rb がHTTP経由（curl相当）でF4フローの
# 非エンジニア向け手順を再現するのに対し、本ファイルは設計資料1.5「F4 支払実行
# executePayout」に明記された下記の振る舞いを、ExecutePayoutサービスを直接
# 呼び出すホワイトボックステストとして検証する。
#
#   支払指図の生成と同時に契約者へアプリ内通知を送る（ここまで自動）。
#   管理者が管理画面で確認操作を行うと「支払完了（模擬）」に遷移し、
#   完了通知とアンケート依頼を送る。年間支払回数が上限に達した契約は
#   「上限到達」状態とする。
#
# 併せて、支払指図後に契約が解約・失効していた場合や、他の支払がまだ指図済のまま
# 残っている場合に、支払確定処理が契約状態を誤って上書きしないこと
# （payout.rb の update_policy_status_on_state_change のコメントに明記された仕様）を確認する。
#
# 対象は開発環境のRailsアプリケーション（storage/test.sqlite3）であり、本番サーバー・
# 本番DBへは一切接続しない。
#
# 実行方法:
#   cd src/backend
#   RAILS_ENV=test bin/rails db:test:prepare
#   bundle exec rspec ../../test/pr50/pr50_execute_payout_service_spec.rb

require "rails_helper"

RSpec.describe ExecutePayout do
  include ActiveSupport::Testing::TimeHelpers

  before do
    find_or_create_policy_status("waiting", "待機中")
    find_or_create_policy_status("active", "有効")
    find_or_create_policy_status("processing", "支払処理中")
    find_or_create_policy_status("cap_reached", "上限到達")
    find_or_create_policy_status("cancelled", "解約")
    find_or_create_policy_status("expired", "失効")
    find_or_create_payout_status("ordered", "指図済")
    find_or_create_payout_status("completed_simulated", "支払完了（模擬）")
    find_or_create_payout_status("invalid", "無効")
  end

  describe "#call" do
    it "支払を「支払完了（模擬）」にし、契約者へ「完了通知」「アンケート依頼」の2件を作成する（設計資料F4）" do
      user = User.create!(google_sub: "google-sub-pr50-service-basic")
      payout = build_ordered_payout_for(user, suffix: "service-basic")

      result = described_class.new(payout: payout).call

      expect(result).to be_success
      expect(payout.reload.payout_status.code).to eq("completed_simulated")
      expect(payout.policy.reload.policy_status.code).to eq("active")

      notifications = Notification.where(payout: payout)
      expect(notifications.pluck(:kind)).to contain_exactly(
        Notification::KIND_PAYOUT_COMPLETED,
        Notification::KIND_SURVEY_REQUEST
      )
    end

    it "支払指図後に契約が解約されていた場合、確定処理で「解約」状態を「有効」へ上書きしない" do
      user = User.create!(google_sub: "google-sub-pr50-service-cancelled")
      payout = build_ordered_payout_for(user, suffix: "service-cancelled")
      payout.policy.update_columns(policy_status_id: PolicyStatus.find_by!(code: "cancelled").id)

      result = described_class.new(payout: payout).call

      expect(result).to be_success
      expect(payout.reload.payout_status.code).to eq("completed_simulated")
      expect(payout.policy.reload.policy_status.code).to eq("cancelled")
    end

    it "契約期間（expires_at）を過ぎている場合、確定処理は「有効」ではなく「失効」へ遷移させる" do
      user = User.create!(google_sub: "google-sub-pr50-service-expired")
      payout = build_ordered_payout_for(user, suffix: "service-expired")
      payout.policy.update_columns(expires_at: 1.minute.ago)

      result = described_class.new(payout: payout).call

      expect(result).to be_success
      expect(payout.policy.reload.policy_status.code).to eq("expired")
    end

    it "同一契約に他の「指図済」支払が残っている間は「支払処理中」のまま維持する" do
      user = User.create!(google_sub: "google-sub-pr50-service-processing")
      plan = find_or_create_plan("seismic_pr50_service_processing")
      station = find_or_create_station("seismic_tokyo_pr50_service_processing")
      payout_tier = find_or_create_payout_tier("ten_thousand_pr50_service_processing")
      level = find_or_create_level("pr50_service_processing", 6)

      policy = Policy.create!(
        user: user, plan: plan, station: station, payout_tier: payout_tier,
        policy_status: PolicyStatus.find_by!(code: "processing"), threshold: "5強"
      )
      policy.update_columns(waiting_until: 1.day.ago, expires_at: 1.year.from_now)

      first_observation = Observation.create!(
        station: station, event_id: "event-pr50-service-processing-1", observed_at: 2.hours.ago,
        seismic_intensity_level: level, max_value: level.sort_order, simulated: true
      )
      second_observation = Observation.create!(
        station: station, event_id: "event-pr50-service-processing-2", observed_at: 1.hour.ago,
        seismic_intensity_level: level, max_value: level.sort_order, simulated: true
      )

      first_payout = Payout.create!(
        policy: policy, payout_tier: payout_tier, payout_status: PayoutStatus.find_by!(code: "ordered"),
        observation: first_observation, idempotency_key: "policy_pr50_service_processing_1", decided_at: Time.current
      )
      second_payout = Payout.create!(
        policy: policy, payout_tier: payout_tier, payout_status: PayoutStatus.find_by!(code: "ordered"),
        observation: second_observation, idempotency_key: "policy_pr50_service_processing_2", decided_at: Time.current
      )

      described_class.new(payout: first_payout).call

      expect(first_payout.reload.payout_status.code).to eq("completed_simulated")
      # second_payout がまだ ordered のまま残っているため、契約は active に戻らない
      expect(policy.reload.policy_status.code).to eq("processing")
      expect(second_payout.reload.payout_status.code).to eq("ordered")
    end

    it "既に「支払完了（模擬）」の支払を再実行しても成功を返し、通知は増えない（冪等性）" do
      user = User.create!(google_sub: "google-sub-pr50-service-idempotent")
      payout = build_ordered_payout_for(user, suffix: "service-idempotent")

      first_result = described_class.new(payout: payout).call
      expect(first_result).to be_success

      expect {
        second_result = described_class.new(payout: payout).call
        expect(second_result).to be_success
      }.not_to change { Notification.count }
    end

    it "「無効」な支払は完了させず unprocessable_entity を返し、通知も作らない" do
      user = User.create!(google_sub: "google-sub-pr50-service-invalid")
      payout = build_payout_for(user, suffix: "service-invalid", payout_status_code: "invalid")

      result = nil
      expect {
        result = described_class.new(payout: payout).call
      }.not_to change { Notification.count }

      expect(result).not_to be_success
      expect(result.status).to eq(:unprocessable_entity)
      expect(payout.reload.payout_status.code).to eq("invalid")
    end

    it "2回目の完了で年間支払上限（2回）に達すると契約が「上限到達」に遷移する（設計資料F4）" do
      user = User.create!(google_sub: "google-sub-pr50-service-cap")
      plan = find_or_create_plan("seismic_pr50_service_cap")
      station = find_or_create_station("seismic_tokyo_pr50_service_cap")
      payout_tier = find_or_create_payout_tier("ten_thousand_pr50_service_cap")
      level = find_or_create_level("pr50_service_cap", 6)

      policy = Policy.create!(
        user: user, plan: plan, station: station, payout_tier: payout_tier,
        policy_status: PolicyStatus.find_by!(code: "processing"), threshold: "5強"
      )
      policy.update_columns(waiting_until: 1.day.ago, expires_at: 1.year.from_now)

      first_observation = Observation.create!(
        station: station, event_id: "event-pr50-service-cap-1", observed_at: 2.hours.ago,
        seismic_intensity_level: level, max_value: level.sort_order, simulated: true
      )
      first_payout = Payout.create!(
        policy: policy, payout_tier: payout_tier, payout_status: PayoutStatus.find_by!(code: "ordered"),
        observation: first_observation, idempotency_key: "policy_pr50_service_cap_1", decided_at: Time.current
      )
      described_class.new(payout: first_payout).call
      expect(policy.reload.policy_status.code).to eq("active")

      policy.update_columns(policy_status_id: PolicyStatus.find_by!(code: "processing").id)
      second_observation = Observation.create!(
        station: station, event_id: "event-pr50-service-cap-2", observed_at: 1.hour.ago,
        seismic_intensity_level: level, max_value: level.sort_order, simulated: true
      )
      second_payout = Payout.create!(
        policy: policy, payout_tier: payout_tier, payout_status: PayoutStatus.find_by!(code: "ordered"),
        observation: second_observation, idempotency_key: "policy_pr50_service_cap_2", decided_at: Time.current
      )

      result = described_class.new(payout: second_payout).call

      expect(result).to be_success
      expect(policy.reload.policy_status.code).to eq("cap_reached")
    end
  end

  # =======================================================================
  # フィクスチャ生成ヘルパー
  # =======================================================================

  def build_ordered_payout_for(user, suffix:)
    build_payout_for(user, suffix: suffix, payout_status_code: "ordered")
  end

  def build_payout_for(user, suffix:, payout_status_code:)
    plan = find_or_create_plan("seismic_pr50_#{suffix}")
    station = find_or_create_station("seismic_tokyo_pr50_#{suffix}")
    payout_tier = find_or_create_payout_tier("ten_thousand_pr50_#{suffix}")
    processing_status = PolicyStatus.find_by!(code: "processing")
    payout_status = PayoutStatus.find_by!(code: payout_status_code)
    level = find_or_create_level("pr50_shared_#{suffix}", 6)

    policy = Policy.create!(
      user: user, plan: plan, station: station, payout_tier: payout_tier,
      policy_status: processing_status, threshold: "5強"
    )
    policy.update_columns(waiting_until: 1.day.ago, expires_at: 1.year.from_now)

    observation = Observation.create!(
      station: station, event_id: "event-pr50-#{suffix}", observed_at: Time.current,
      seismic_intensity_level: level, max_value: level.sort_order, simulated: true
    )

    Payout.create!(
      policy: policy, payout_tier: payout_tier, payout_status: payout_status, observation: observation,
      idempotency_key: "policy_pr50_#{suffix}", decided_at: Time.current
    )
  end

  def next_sort_order(klass)
    (klass.maximum(:sort_order) || -1) + 1
  end

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

  def find_or_create_policy_status(code, label_ja)
    PolicyStatus.find_by(code: code) || PolicyStatus.create!(
      code: code, sort_order: next_sort_order(PolicyStatus),
      **%i[label_ja label_en label_fr label_zh label_ru label_es label_ar].index_with { label_ja }
    )
  end

  def find_or_create_payout_status(code, label_ja)
    PayoutStatus.find_by(code: code) || PayoutStatus.create!(
      code: code, sort_order: next_sort_order(PayoutStatus),
      **%i[label_ja label_en label_fr label_zh label_ru label_es label_ar].index_with { label_ja }
    )
  end

  def find_or_create_level(code, sort_order)
    SeismicIntensityLevel.find_by(code: code) || SeismicIntensityLevel.create!(
      code: code, sort_order: sort_order.to_i.zero? ? next_sort_order(SeismicIntensityLevel) : sort_order,
      **%i[label_ja label_en label_fr label_zh label_ru label_es label_ar].index_with { "5強" }
    )
  end
end
