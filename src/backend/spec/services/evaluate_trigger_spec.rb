require "rails_helper"

RSpec.describe EvaluateTrigger do
  include ActiveSupport::Testing::TimeHelpers

  def seismic_idempotency_key(policy, event_id)
    "policy_#{policy.id}_event_#{Digest::SHA256.hexdigest(event_id)}"
  end

  let(:user) { User.create!(google_sub: "google-sub-eval-spec") }

  let(:seismic_plan) do
    Plan.create!(
      code: "seismic_eval_spec",
      trigger_type: "seismic",
      label_ja: "震度連動",
      label_en: "Seismic-linked",
      label_fr: "Lié aux sismos",
      label_zh: "震度連動",
      label_ru: "Сейсмическая przywiazka",
      label_es: "Vinculado a sismos",
      label_ar: "مرتبط بالزلازل"
    )
  end

  let(:rainfall_plan) do
    Plan.create!(
      code: "rainfall_eval_spec",
      trigger_type: "rainfall",
      label_ja: "降雨連動",
      label_en: "Rainfall-linked",
      label_fr: "Lié aux pluies",
      label_zh: "降雨連動",
      label_ru: "Привязка к осадкам",
      label_es: "Vinculado a lluvias",
      label_ar: "مرتبط بالأمطار"
    )
  end

  let(:seismic_station) do
    Station.create!(
      code: "seismic_tokyo_eval_spec",
      measurement_type: "seismic",
      label_ja: "東京震度観測点",
      label_en: "Tokyo seismic station",
      label_fr: "Tokyo seismic station",
      label_zh: "Tokyo seismic station",
      label_ru: "Tokyo seismic station",
      label_es: "Tokyo seismic station",
      label_ar: "Tokyo seismic station"
    )
  end

  let(:rainfall_station) do
    Station.create!(
      code: "rainfall_tokyo_eval_spec",
      measurement_type: "rainfall",
      label_ja: "東京雨量観測点",
      label_en: "Tokyo rainfall station",
      label_fr: "Tokyo rainfall station",
      label_zh: "Tokyo rainfall station",
      label_ru: "Tokyo rainfall station",
      label_es: "Tokyo rainfall station",
      label_ar: "Tokyo rainfall station"
    )
  end

  let(:payout_tier) do
    PayoutTier.create!(
      code: "ten_thousand_eval_spec",
      amount_yen: 10_000,
      label_ja: "1万円相当（模擬）",
      label_en: "Equivalent to JPY 10,000",
      label_fr: "Equivalent to JPY 10,000",
      label_zh: "Equivalent to JPY 10,000",
      label_ru: "Equivalent to JPY 10,000",
      label_es: "Equivalent to JPY 10,000",
      label_ar: "Equivalent to JPY 10,000"
    )
  end

  let!(:pending_status) { PolicyStatus.find_or_create_by!(code: "pending", sort_order: 0, label_ja: "待機中", label_en: "Pending", label_fr: "Pending", label_zh: "Pending", label_ru: "Pending", label_es: "Pending", label_ar: "Pending") }
  let!(:active_status) { PolicyStatus.find_or_create_by!(code: "active", sort_order: 1, label_ja: "有効", label_en: "Active", label_fr: "Active", label_zh: "Active", label_ru: "Active", label_es: "Active", label_ar: "Active") }
  let!(:processing_status) { PolicyStatus.find_or_create_by!(code: "processing", sort_order: 2, label_ja: "支払処理中", label_en: "Processing", label_fr: "Processing", label_zh: "Processing", label_ru: "Processing", label_es: "Processing", label_ar: "Processing") }
  let!(:cap_reached_status) { PolicyStatus.find_or_create_by!(code: "cap_reached", sort_order: 3, label_ja: "上限到達", label_en: "Cap reached", label_fr: "Cap reached", label_zh: "Cap reached", label_ru: "Cap reached", label_es: "Cap reached", label_ar: "Cap reached") }
  let!(:cancelled_status) { PolicyStatus.find_or_create_by!(code: "cancelled", sort_order: 4, label_ja: "解約", label_en: "Cancelled", label_fr: "Cancelled", label_zh: "Cancelled", label_ru: "Cancelled", label_es: "Cancelled", label_ar: "Cancelled") }
  let!(:expired_status) { PolicyStatus.find_or_create_by!(code: "expired", sort_order: 5, label_ja: "失効", label_en: "Expired", label_fr: "Expired", label_zh: "Expired", label_ru: "Expired", label_es: "Expired", label_ar: "Expired") }

  let!(:ordered_payout_status) { PayoutStatus.find_or_create_by!(code: "ordered", sort_order: 0, label_ja: "指図済", label_en: "Ordered", label_fr: "Ordered", label_zh: "Ordered", label_ru: "Ordered", label_es: "Ordered", label_ar: "Ordered") }
  let!(:completed_payout_status) { PayoutStatus.find_or_create_by!(code: "completed_simulated", sort_order: 1, label_ja: "支払完了（模擬）", label_en: "Completed", label_fr: "Completed", label_zh: "Completed", label_ru: "Completed", label_es: "Completed", label_ar: "Completed") }
  let!(:invalid_payout_status) { PayoutStatus.find_or_create_by!(code: "invalid", sort_order: 2, label_ja: "無効", label_en: "Invalid", label_fr: "Invalid", label_zh: "Invalid", label_ru: "Invalid", label_es: "Invalid", label_ar: "Invalid") }

  let!(:seismic_level_4) { SeismicIntensityLevel.create!(code: "4_eval_spec", sort_order: 4, label_ja: "4", label_en: "4", label_fr: "4", label_zh: "4", label_ru: "4", label_es: "4", label_ar: "4") }
  let!(:seismic_level_5_weak) { SeismicIntensityLevel.create!(code: "5_weak_eval_spec", sort_order: 5, label_ja: "5弱", label_en: "5 weak", label_fr: "5 weak", label_zh: "5 weak", label_ru: "5 weak", label_es: "5 weak", label_ar: "5 weak") }
  let!(:seismic_level_5_strong) { SeismicIntensityLevel.create!(code: "5_strong_eval_spec", sort_order: 6, label_ja: "5強", label_en: "5 strong", label_fr: "5 strong", label_zh: "5 strong", label_ru: "5 strong", label_es: "5 strong", label_ar: "5 strong") }

  describe "#call" do
    let!(:policy) do
      Policy.create!(
        user: user,
        plan: seismic_plan,
        station: seismic_station,
        payout_tier: payout_tier,
        policy_status: active_status,
        threshold: "5強"
      ).tap do |p|
        # Use update_columns to bypass waiting_until on_create callbacks and validation restrictions
        p.update_columns(
          waiting_until: Time.zone.parse("2025-12-31 09:00:00"),
          expires_at: Time.zone.parse("2027-07-15 09:00:00")
        )
      end
    end

    context "when a valid observation meets threshold" do
      let(:observation) do
        Observation.create!(
          station: seismic_station,
          event_id: "event-001",
          observed_at: Time.zone.parse("2026-07-15 10:00:00"),
          seismic_intensity_level: seismic_level_5_strong,
          max_value: seismic_level_5_strong.sort_order,
          simulated: false
        )
      end

      it "creates a payout and transitions the policy to processing" do
        result = EvaluateTrigger.call(observation)
        expect(result.status).to eq(:success)
        expect(result.payouts.count).to eq(1)

        payout = result.payouts.first
        expect(payout.policy).to eq(policy)
        expect(payout.payout_status).to eq(ordered_payout_status)
        expect(payout.idempotency_key).to eq(seismic_idempotency_key(policy, "event-001"))

        expect(policy.reload.policy_status).to eq(processing_status)
      end

      it "creates an in-app notification for the policyholder at the same time as the payout" do
        expect {
          EvaluateTrigger.call(observation)
        }.to change(Notification, :count).by(1)

        payout = Payout.find_by!(idempotency_key: seismic_idempotency_key(policy, "event-001"))
        notification = Notification.last

        expect(notification.user).to eq(user)
        expect(notification.policy).to eq(policy)
        expect(notification.payout).to eq(payout)
        expect(notification.kind).to eq("payout_ordered")
        # user.localeの既定値(:ja)で通知本文が生成されること
        expect(notification.message).to eq(I18n.t("notifications.payout_ordered", locale: :ja))
      end

      it "generates the notification message in the policyholder's locale, regardless of the ambient I18n.locale (Issue #65)" do
        user.update!(locale: "en")

        I18n.with_locale(:ja) do
          EvaluateTrigger.call(observation)
        end

        expect(Notification.last.message).to eq(I18n.t("notifications.payout_ordered", locale: :en))
      end

      it "does not create a payout or a notification when the transaction is not going to commit due to an unrelated failure downstream" do
        allow(Notification).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(Notification.new))

        expect {
          expect { EvaluateTrigger.call(observation) }.to raise_error(ActiveRecord::RecordInvalid)
        }.not_to change(Payout, :count)

        expect(policy.reload.policy_status).to eq(active_status)
      end
    end

    context "when the event occurred during the waiting period" do
      let(:observation) do
        Observation.create!(
          station: seismic_station,
          event_id: "event-002",
          observed_at: Time.zone.parse("2025-12-31 08:59:59"), # waiting_until is 2025-12-31 09:00:00
          seismic_intensity_level: seismic_level_5_strong,
          max_value: seismic_level_5_strong.sort_order,
          simulated: false
        )
      end

      it "does not create a payout" do
        result = EvaluateTrigger.call(observation)
        expect(result.payouts).to be_empty
        expect(policy.reload.policy_status).to eq(active_status)
      end
    end

    context "when the event occurred after policy expiration" do
      let(:observation) do
        Observation.create!(
          station: seismic_station,
          event_id: "event-003",
          observed_at: Time.zone.parse("2027-07-15 09:00:01"), # expires_at is 2027-07-15 09:00:00
          seismic_intensity_level: seismic_level_5_strong,
          max_value: seismic_level_5_strong.sort_order,
          simulated: false
        )
      end

      it "does not create a payout" do
        result = EvaluateTrigger.call(observation)
        expect(result.payouts).to be_empty
      end
    end

    context "when the policy was cancelled before the event" do
      before do
        policy.update_columns(terminated_at: Time.zone.parse("2026-07-16 09:00:00"))
      end

      it "does not create a payout if the event is after termination" do
        observation = Observation.create!(
          station: seismic_station,
          event_id: "event-004",
          observed_at: Time.zone.parse("2026-07-16 09:00:01"),
          seismic_intensity_level: seismic_level_5_strong,
          max_value: seismic_level_5_strong.sort_order,
          simulated: false
        )
        result = EvaluateTrigger.call(observation)
        expect(result.payouts).to be_empty
      end

      it "creates a payout if the event is at the exact termination time" do
        observation = Observation.create!(
          station: seismic_station,
          event_id: "event-005",
          observed_at: Time.zone.parse("2026-07-16 09:00:00"),
          seismic_intensity_level: seismic_level_5_strong,
          max_value: seismic_level_5_strong.sort_order,
          simulated: false
        )
        result = EvaluateTrigger.call(observation)
        expect(result.payouts.count).to eq(1)
      end
    end

    context "when ingestion is delayed and the policy has already been administratively cancelled" do
      before do
        policy.update_columns(
          policy_status_id: cancelled_status.id,
          terminated_at: Time.zone.parse("2026-07-16 09:00:00")
        )
      end

      it "still creates a payout for an event that occurred before the cancellation took effect, and does not overwrite the cancelled status" do
        observation = Observation.create!(
          station: seismic_station,
          event_id: "event-delayed-001",
          observed_at: Time.zone.parse("2026-07-16 08:59:59"),
          seismic_intensity_level: seismic_level_5_strong,
          max_value: seismic_level_5_strong.sort_order,
          simulated: false
        )

        result = EvaluateTrigger.call(observation)

        expect(result.payouts.count).to eq(1)
        expect(policy.reload.policy_status).to eq(cancelled_status)
      end

      it "does not create a payout for an event that occurred after the cancellation took effect" do
        observation = Observation.create!(
          station: seismic_station,
          event_id: "event-delayed-002",
          observed_at: Time.zone.parse("2026-07-16 09:00:01"),
          seismic_intensity_level: seismic_level_5_strong,
          max_value: seismic_level_5_strong.sort_order,
          simulated: false
        )

        result = EvaluateTrigger.call(observation)

        expect(result.payouts).to be_empty
      end
    end

    context "when ingestion is delayed and the policy has already expired" do
      before do
        policy.update_columns(policy_status_id: expired_status.id, expires_at: Time.zone.parse("2026-07-16 09:00:00"))
      end

      it "still creates a payout for an event that occurred before expiration, and does not overwrite the expired status" do
        observation = Observation.create!(
          station: seismic_station,
          event_id: "event-delayed-003",
          observed_at: Time.zone.parse("2026-07-16 08:59:59"),
          seismic_intensity_level: seismic_level_5_strong,
          max_value: seismic_level_5_strong.sort_order,
          simulated: false
        )

        result = EvaluateTrigger.call(observation)

        expect(result.payouts.count).to eq(1)
        expect(policy.reload.policy_status).to eq(expired_status)
      end
    end

    context "when the observation is below the threshold" do
      let(:observation) do
        Observation.create!(
          station: seismic_station,
          event_id: "event-006",
          observed_at: Time.zone.parse("2026-07-15 10:00:00"),
          seismic_intensity_level: seismic_level_5_weak,
          max_value: seismic_level_5_weak.sort_order,
          simulated: false
        )
      end

      it "does not create a payout" do
        result = EvaluateTrigger.call(observation)
        expect(result.payouts).to be_empty
      end
    end

    context "when the policy has already reached the annual payout limit of 2" do
      let!(:obs_past1) do
        Observation.create!(
          station: seismic_station,
          event_id: "past-001",
          observed_at: Time.zone.parse("2026-01-15 10:00:00"),
          seismic_intensity_level: seismic_level_5_strong,
          max_value: seismic_level_5_strong.sort_order,
          simulated: false
        )
      end

      let!(:obs_past2) do
        Observation.create!(
          station: seismic_station,
          event_id: "past-002",
          observed_at: Time.zone.parse("2026-02-15 10:00:00"),
          seismic_intensity_level: seismic_level_5_strong,
          max_value: seismic_level_5_strong.sort_order,
          simulated: false
        )
      end

      let!(:payout1) do
        Payout.create!(
          policy: policy,
          payout_tier: payout_tier,
          payout_status: completed_payout_status,
          observation: obs_past1,
          idempotency_key: "policy_#{policy.id}_event_past-001",
          decided_at: Time.zone.parse("2026-01-15 10:00:00")
        )
      end

      let!(:payout2) do
        Payout.create!(
          policy: policy,
          payout_tier: payout_tier,
          payout_status: completed_payout_status,
          observation: obs_past2,
          idempotency_key: "policy_#{policy.id}_event_past-002",
          decided_at: Time.zone.parse("2026-02-15 10:00:00")
        )
      end

      let(:observation) do
        Observation.create!(
          station: seismic_station,
          event_id: "event-007",
          observed_at: Time.zone.parse("2026-07-15 10:00:00"),
          seismic_intensity_level: seismic_level_5_strong,
          max_value: seismic_level_5_strong.sort_order,
          simulated: false
        )
      end

      it "does not create a payout" do
        result = EvaluateTrigger.call(observation)
        expect(result.payouts).to be_empty
      end
    end

    context "when a payout for the exact same event already exists (idempotency)" do
      let(:observation) do
        Observation.create!(
          station: seismic_station,
          event_id: "event-008",
          observed_at: Time.zone.parse("2026-07-15 10:00:00"),
          seismic_intensity_level: seismic_level_5_strong,
          max_value: seismic_level_5_strong.sort_order,
          simulated: false
        )
      end

      before do
        Payout.create!(
          policy: policy,
          payout_tier: payout_tier,
          payout_status: ordered_payout_status,
          observation: observation,
          idempotency_key: seismic_idempotency_key(policy, "event-008"),
          decided_at: Time.current
        )
      end

      it "does not create another payout" do
        expect {
          result = EvaluateTrigger.call(observation)
          expect(result.payouts).to be_empty
        }.not_to change(Payout, :count)
      end
    end

    context "when observation maximum values are updated (follow-up reports)" do
      let!(:observation) do
        Observation.create!(
          station: seismic_station,
          event_id: "event-009",
          observed_at: Time.zone.parse("2026-07-15 10:00:00"),
          seismic_intensity_level: seismic_level_5_strong,
          max_value: seismic_level_5_strong.sort_order,
          simulated: false
        )
      end

      let!(:existing_payout) do
        Payout.create!(
          policy: policy,
          payout_tier: payout_tier,
          payout_status: ordered_payout_status,
          observation: observation,
          idempotency_key: seismic_idempotency_key(policy, "event-009"),
          decided_at: Time.current
        )
      end

      it "does not create an additional payout when maximum value increases further" do
        seismic_level_7 = SeismicIntensityLevel.create!(code: "7_eval_spec", sort_order: 9, label_ja: "7", label_en: "7", label_fr: "7", label_zh: "7", label_ru: "7", label_es: "7", label_ar: "7")
        observation.update!(seismic_intensity_level: seismic_level_7, max_value: 9)

        expect {
          result = EvaluateTrigger.call(observation)
          expect(result.payouts).to be_empty
        }.not_to change(Payout, :count)
      end

      it "does not cancel or remove payout when value decreases (downward revision)" do
        expect {
          EvaluateTrigger.call(observation)
        }.not_to change(Payout, :count)

        expect(Payout.exists?(idempotency_key: seismic_idempotency_key(policy, "event-009"))).to be true
      end
    end

    context "for rainfall plans" do
      let!(:policy_rainfall) do
        Policy.create!(
          user: user,
          plan: rainfall_plan,
          station: rainfall_station,
          payout_tier: payout_tier,
          policy_status: active_status,
          threshold: "50.0"
        ).tap do |p|
          p.update_columns(
            waiting_until: Time.zone.parse("2025-12-31 09:00:00"),
            expires_at: Time.zone.parse("2027-07-15 09:00:00")
          )
        end
      end

      it "creates payout if rainfall meets threshold" do
        observation = Observation.create!(
          station: rainfall_station,
          observed_at: Time.zone.parse("2026-07-15 10:00:00"),
          rainfall_mm: 50.0,
          max_value: 50.0,
          simulated: false
        )

        result = EvaluateTrigger.call(observation)
        expect(result.payouts.count).to eq(1)
        expect(result.payouts.first.policy).to eq(policy_rainfall)
        expect(result.payouts.first.idempotency_key).to eq("policy_#{policy_rainfall.id}_observed_#{observation.id}")
      end

      it "does not lose a payout when two distinct observations fall within the same second" do
        observation1 = Observation.create!(
          station: rainfall_station,
          observed_at: Time.zone.parse("2026-07-15 10:00:00.100"),
          rainfall_mm: 50.0,
          max_value: 50.0,
          simulated: false
        )
        observation2 = Observation.create!(
          station: rainfall_station,
          observed_at: Time.zone.parse("2026-07-15 10:00:00.900"),
          rainfall_mm: 60.0,
          max_value: 60.0,
          simulated: false
        )

        result1 = EvaluateTrigger.call(observation1)
        result2 = EvaluateTrigger.call(observation2)

        expect(result1.payouts.count).to eq(1)
        expect(result2.payouts.count).to eq(1)
        expect(result1.payouts.first.idempotency_key).not_to eq(result2.payouts.first.idempotency_key)
      end

      it "does not create payout if rainfall is below threshold" do
        observation = Observation.create!(
          station: rainfall_station,
          observed_at: Time.zone.parse("2026-07-15 10:00:00"),
          rainfall_mm: 49.9,
          max_value: 49.9,
          simulated: false
        )

        result = EvaluateTrigger.call(observation)
        expect(result.payouts).to be_empty
      end

      context "when a pre-existing policy stored a unit-suffixed legacy threshold (e.g. saved as-is by the application wizard before normalization at creation time was added)" do
        let!(:legacy_unit_suffixed_policy) do
          Policy.create!(
            user: User.create!(google_sub: "google-sub-eval-spec-legacy-unit"),
            plan: rainfall_plan,
            station: rainfall_station,
            payout_tier: payout_tier,
            policy_status: active_status,
            threshold: "50 mm"
          ).tap do |p|
            p.update_columns(
              waiting_until: Time.zone.parse("2025-12-31 09:00:00"),
              expires_at: Time.zone.parse("2027-07-15 09:00:00")
            )
          end
        end

        it "still evaluates it using the same lenient parsing rules as policy creation" do
          observation = Observation.create!(
            station: rainfall_station,
            observed_at: Time.zone.parse("2026-07-15 10:00:00"),
            rainfall_mm: 50.0,
            max_value: 50.0,
            simulated: false
          )

          result = EvaluateTrigger.call(observation)

          expect(result.payouts.map(&:policy)).to include(legacy_unit_suffixed_policy)
        end
      end

      context "when another policy at the same station has a corrupted (legacy) threshold" do
        let!(:corrupted_policy) do
          Policy.create!(
            user: User.create!(google_sub: "google-sub-eval-spec-corrupted"),
            plan: rainfall_plan,
            station: rainfall_station,
            payout_tier: payout_tier,
            policy_status: active_status,
            threshold: "not-a-number"
          ).tap do |p|
            p.update_columns(
              waiting_until: Time.zone.parse("2025-12-31 09:00:00"),
              expires_at: Time.zone.parse("2027-07-15 09:00:00")
            )
          end
        end

        it "skips only the corrupted policy and still evaluates other policies at the same station" do
          observation = Observation.create!(
            station: rainfall_station,
            observed_at: Time.zone.parse("2026-07-15 10:00:00"),
            rainfall_mm: 50.0,
            max_value: 50.0,
            simulated: false
          )

          result = EvaluateTrigger.call(observation)

          expect(result.status).to eq(:success)
          expect(result.payouts.map(&:policy)).to eq([ policy_rainfall ])
          expect(corrupted_policy.reload.policy_status).to eq(active_status)
        end
      end

      context "when another policy has a legacy non-positive threshold" do
        let!(:zero_threshold_policy) do
          Policy.create!(
            user: User.create!(google_sub: "google-sub-eval-spec-zero-threshold"),
            plan: rainfall_plan,
            station: rainfall_station,
            payout_tier: payout_tier,
            policy_status: active_status,
            threshold: "0"
          ).tap do |p|
            p.update_columns(
              waiting_until: Time.zone.parse("2025-12-31 09:00:00"),
              expires_at: Time.zone.parse("2027-07-15 09:00:00")
            )
          end
        end

        let!(:negative_threshold_policy) do
          Policy.create!(
            user: User.create!(google_sub: "google-sub-eval-spec-negative-threshold"),
            plan: rainfall_plan,
            station: rainfall_station,
            payout_tier: payout_tier,
            policy_status: active_status,
            threshold: "-10"
          ).tap do |p|
            p.update_columns(
              waiting_until: Time.zone.parse("2025-12-31 09:00:00"),
              expires_at: Time.zone.parse("2027-07-15 09:00:00")
            )
          end
        end

        it "does not create a payout for policies with a threshold of zero or below" do
          observation = Observation.create!(
            station: rainfall_station,
            observed_at: Time.zone.parse("2026-07-15 10:00:00"),
            rainfall_mm: 1.0,
            max_value: 1.0,
            simulated: false
          )

          result = EvaluateTrigger.call(observation)

          expect(result.payouts).to be_empty
          expect(zero_threshold_policy.reload.policy_status).to eq(active_status)
          expect(negative_threshold_policy.reload.policy_status).to eq(active_status)
        end
      end
    end

    context "when a policy reached the annual cap in a previous year" do
      let!(:policy) do
        Policy.create!(
          user: user,
          plan: seismic_plan,
          station: seismic_station,
          payout_tier: payout_tier,
          policy_status: cap_reached_status,
          threshold: "5強"
        ).tap do |p|
          p.update_columns(
            waiting_until: Time.zone.parse("2024-12-31 09:00:00"),
            expires_at: Time.zone.parse("2030-07-15 09:00:00")
          )
        end
      end

      let!(:obs_last_year_1) do
        Observation.create!(
          station: seismic_station,
          event_id: "cap-last-year-001",
          observed_at: Time.zone.parse("2025-02-01 10:00:00"),
          seismic_intensity_level: seismic_level_5_strong,
          max_value: seismic_level_5_strong.sort_order,
          simulated: false
        )
      end

      let!(:obs_last_year_2) do
        Observation.create!(
          station: seismic_station,
          event_id: "cap-last-year-002",
          observed_at: Time.zone.parse("2025-03-01 10:00:00"),
          seismic_intensity_level: seismic_level_5_strong,
          max_value: seismic_level_5_strong.sort_order,
          simulated: false
        )
      end

      let!(:payout1) do
        Payout.create!(
          policy: policy,
          payout_tier: payout_tier,
          payout_status: completed_payout_status,
          observation: obs_last_year_1,
          idempotency_key: "policy_#{policy.id}_event_cap-last-year-001",
          decided_at: obs_last_year_1.observed_at
        )
      end

      let!(:payout2) do
        Payout.create!(
          policy: policy,
          payout_tier: payout_tier,
          payout_status: completed_payout_status,
          observation: obs_last_year_2,
          idempotency_key: "policy_#{policy.id}_event_cap-last-year-002",
          decided_at: obs_last_year_2.observed_at
        )
      end

      it "creates a payout when the new observation falls in a new year with the count reset" do
        observation = Observation.create!(
          station: seismic_station,
          event_id: "cap-new-year-001",
          observed_at: Time.zone.parse("2026-02-01 10:00:00"),
          seismic_intensity_level: seismic_level_5_strong,
          max_value: seismic_level_5_strong.sort_order,
          simulated: false
        )

        result = EvaluateTrigger.call(observation)

        expect(result.payouts.count).to eq(1)
        expect(policy.reload.policy_status).to eq(processing_status)
      end
    end
  end
end
