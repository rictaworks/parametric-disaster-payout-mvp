require "rails_helper"

RSpec.describe "PATCH /api/v1/locale", type: :request do
  let(:user) { User.create!(google_sub: "google-sub-locale-preferences") }
  let(:internal_api_secret) { "shared-secret" }
  let(:headers) do
    {
      "X-Internal-API-Secret" => internal_api_secret,
      "X-Internal-Session-Token" => user.internal_session_token
    }
  end

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("INTERNAL_API_SECRET").and_return(internal_api_secret)
  end

  it "updates the current user's locale to a supported locale" do
    patch "/api/v1/locale", params: { locale: "en" }, headers: headers

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body["user"]).to eq("id" => user.id, "locale" => "en")
    expect(user.reload.locale).to eq("en")
  end

  it "rejects a locale with no corresponding config/locales/*.yml file" do
    patch "/api/v1/locale", params: { locale: "de" }, headers: headers

    expect(response).to have_http_status(:unprocessable_entity)
    expect(user.reload.locale).to eq("ja")
  end

  it "returns 401 without a valid session token" do
    patch "/api/v1/locale", params: { locale: "en" }, headers: headers.merge("X-Internal-Session-Token" => "invalid")

    expect(response).to have_http_status(:unauthorized)
    expect(user.reload.locale).to eq("ja")
  end

  it "returns 403 when the internal API secret does not match" do
    patch "/api/v1/locale", params: { locale: "en" }, headers: headers.merge("X-Internal-API-Secret" => "wrong-secret")

    expect(response).to have_http_status(:forbidden)
    expect(user.reload.locale).to eq("ja")
  end
end
