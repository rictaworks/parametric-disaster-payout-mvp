require 'rails_helper'

RSpec.describe 'Policies', type: :request do
  before do
    PolicyStatus.find_or_create_by!(code: 'waiting') do |status|
      status.label_ja = '待機中'
      status.label_en = 'Waiting'
    end

    @plan = Plan.find_or_create_by!(code: 'seismic') do |plan|
      plan.plan_type = 'seismic'
      plan.label_ja = '震度連動プラン'
      plan.label_en = 'Seismic Intensity Plan'
    end

    @station = Station.find_or_create_by!(code: 'tokyo_seismic') do |station|
      station.plan_type = 'seismic'
      station.label_ja = '東京観測点'
      station.label_en = 'Tokyo Seismic Station'
      station.prefecture = 'Tokyo'
    end

    @tier = PayoutTier.find_or_create_by!(code: 'tier_10k') do |tier|
      tier.amount_jpy = 10_000
      tier.label_ja = '10,000円相当（模擬）'
      tier.label_en = 'JPY 10,000 equivalent (simulated)'
    end
  end

  it 'creates a policy and rejects duplicate active policies' do
    payload = {
      google_sub: 'opaque-google-sub',
      plan_id: @plan.id,
      station_id: @station.id,
      threshold: 'int_5_lower',
      payout_tier_id: @tier.id,
      recaptcha_token: 'test-token'
    }

    post '/api/v1/policies', params: payload
    expect(response).to have_http_status(:created)

    post '/api/v1/policies', params: payload
    expect(response).to have_http_status(:conflict)
  end
end
