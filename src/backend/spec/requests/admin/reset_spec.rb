require "rails_helper"

RSpec.describe "Admin reset", type: :request do
  let(:admin_user) { "admin" }
  let(:admin_password) { "changeme" }
  let(:auth_headers) do
    {
      "Authorization" => "Basic #{Base64.strict_encode64("#{admin_user}:#{admin_password}")}"
    }
  end

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("ADMIN_BASIC_USER").and_return(admin_user)
    allow(ENV).to receive(:[]).with("ADMIN_BASIC_PASSWORD").and_return(admin_password)
    load Rails.root.join("db/seeds.rb")
  end

  let(:user) { User.create!(google_sub: "google-sub-admin-reset") }
  let(:plan) { Plan.find_by!(code: "seismic") }
  let(:station) { Station.find_by!(code: "seismic_tokyo") }
  let(:payout_tier) { PayoutTier.find_by!(code: "ten_thousand") }
  let!(:policy_status) { PolicyStatus.find_by!(code: "processing") }
  let!(:active_status) { PolicyStatus.find_by!(code: "active") }
  let!(:cap_reached_status) { PolicyStatus.find_by!(code: "cap_reached") }
  let!(:completed_status) { PayoutStatus.find_by!(code: "completed_simulated") }
  let!(:seismic_level) { SeismicIntensityLevel.find_by!(code: "5_strong") }

  let!(:policy) do
    Policy.create!(
      user: user,
      plan: plan,
      station: station,
      payout_tier: payout_tier,
      policy_status: policy_status,
      threshold: "5強"
    ).tap do |record|
      record.update_columns(waiting_until: Time.zone.parse("2025-12-31 09:00:00"), expires_at: Time.zone.parse("2027-07-15 09:00:00"))
    end
  end

  let!(:observation) do
    Observation.create!(
      station: station,
      event_id: "event-admin-reset-001",
      observed_at: Time.zone.parse("2026-07-15 10:00:00"),
      seismic_intensity_level: seismic_level,
      max_value: seismic_level.sort_order,
      simulated: true
    )
  end

  let!(:payout) do
    Payout.create!(
      policy: policy,
      payout_tier: payout_tier,
      payout_status: completed_status,
      observation: observation,
      idempotency_key: "policy_#{policy.id}_event_event-admin-reset-001",
      decided_at: Time.current
    )
  end

  let!(:notification) do
    Notification.create!(
      user: user,
      policy: policy,
      payout: payout,
      kind: Notification::KIND_PAYOUT_ORDERED,
      message: "ordered"
    )
  end

  let!(:survey_response) do
    SurveyResponse.create!(
      user: user,
      payout: payout,
      response_data: { "satisfaction" => 5, "answer" => "yes" }
    )
  end

  let!(:processed_jma_entry) do
    ProcessedJmaEntry.create!(
      entry_id: "urn:uuid:eq-entry-reset-spec"
    )
  end

  it "requires BASIC auth" do
    get "/admin/reset"

    expect(response).to have_http_status(:unauthorized)
  end

  it "renders the reset tab with a custom confirmation modal" do
    get "/admin/reset", headers: auth_headers

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("リセット")
    expect(response.body).to include("reset-modal")
    expect(response.body).to include(ResetDemoData::CONFIRMATION_TEXT)
  end

  it "resets transactional data while preserving users and master records" do
    expect do
      post "/admin/reset",
        headers: auth_headers,
        params: { confirmation_text: ResetDemoData::CONFIRMATION_TEXT }
    end.to change { [ Policy.count, Observation.count, Payout.count, Notification.count, SurveyResponse.count, ProcessedJmaEntry.count ] }.from([ 1, 1, 1, 1, 1, 1 ]).to([ 0, 0, 0, 0, 0, 0 ])

    expect(response).to redirect_to("/admin/reset")
    get "/admin/reset", headers: auth_headers

    expect(response.body).to include("デモデータを初期化しました。")
    expect(User.count).to eq(1)
    expect([ Plan.count, Station.count, PayoutTier.count, PolicyStatus.count, PayoutStatus.count, SeismicIntensityLevel.count ].sum).to eq(26)
  end

  it "rejects requests in production" do
    allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))

    get "/admin/reset", headers: auth_headers

    expect(response).to have_http_status(:not_found)
  end

  it "rejects missing confirmation text" do
    post "/admin/reset", headers: auth_headers

    expect(response).to have_http_status(:unprocessable_entity)
    expect(Policy.count).to eq(1)
    expect(ProcessedJmaEntry.count).to eq(1)
  end
end
