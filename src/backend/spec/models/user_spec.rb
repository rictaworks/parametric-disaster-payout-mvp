require "rails_helper"

RSpec.describe User do
  describe "#locale" do
    it "defaults to :ja for a newly created user" do
      user = User.create!(google_sub: "google-sub-user-spec-default-locale")

      expect(user.locale).to eq("ja")
    end

    it "accepts any of the 7 supported locales" do
      User::SUPPORTED_LOCALES.each_with_index do |locale, index|
        user = User.create!(google_sub: "google-sub-user-spec-locale-#{index}", locale: locale)

        expect(user.reload.locale).to eq(locale)
      end
    end

    it "rejects a locale that has no corresponding config/locales/*.yml file" do
      user = User.new(google_sub: "google-sub-user-spec-invalid-locale", locale: "de")

      expect(user).not_to be_valid
      expect(user.errors[:locale]).to be_present
    end
  end
end
