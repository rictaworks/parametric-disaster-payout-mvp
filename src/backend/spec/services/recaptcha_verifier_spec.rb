require "rails_helper"

RSpec.describe RecaptchaVerifier do
  subject(:verifier) { described_class.new }

  let(:token) { "client-token" }

  around do |example|
    original_secret = ENV["RECAPTCHA_SECRET_KEY"]
    ENV["RECAPTCHA_SECRET_KEY"] = "server-secret"
    example.run
    ENV["RECAPTCHA_SECRET_KEY"] = original_secret
  end

  def stub_google_response(body)
    fake_http = instance_double(Net::HTTP)
    allow(fake_http).to receive(:post).and_return(instance_double(Net::HTTPResponse, body: body))
    allow(Net::HTTP).to receive(:start) { |*_args, &block| block.call(fake_http) }
  end

  it "returns false without contacting Google when the secret key is not configured" do
    ENV["RECAPTCHA_SECRET_KEY"] = nil
    expect(Net::HTTP).not_to receive(:start)

    expect(verifier.valid?(token)).to be false
  end

  it "returns false without contacting Google when the token is blank" do
    expect(Net::HTTP).not_to receive(:start)

    expect(verifier.valid?("")).to be false
  end

  it "returns true when Google reports success" do
    stub_google_response({ "success" => true }.to_json)

    expect(verifier.valid?(token)).to be true
  end

  it "returns false and logs the rejection reason when Google reports failure" do
    stub_google_response({ "success" => false, "error-codes" => [ "timeout-or-duplicate" ] }.to_json)

    expect(Rails.logger).to receive(:warn).with(/timeout-or-duplicate/)
    expect(verifier.valid?(token)).to be false
  end

  it "returns false and logs the exception when the request times out" do
    allow(Net::HTTP).to receive(:start).and_raise(Net::OpenTimeout, "execution expired")

    expect(Rails.logger).to receive(:error).with(/Net::OpenTimeout/)
    expect(verifier.valid?(token)).to be false
  end

  it "returns false and logs the exception when the response body is not valid JSON" do
    stub_google_response("not json")

    expect(Rails.logger).to receive(:error).with(/JSON/)
    expect(verifier.valid?(token)).to be false
  end

  it "configures explicit open and read timeouts for the outbound request" do
    expect(Net::HTTP).to receive(:start).with(
      "www.google.com",
      443,
      hash_including(
        use_ssl: true,
        open_timeout: RecaptchaVerifier::OPEN_TIMEOUT,
        read_timeout: RecaptchaVerifier::READ_TIMEOUT
      )
    )

    verifier.valid?(token)
  end
end
