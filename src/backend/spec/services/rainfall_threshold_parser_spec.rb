require "rails_helper"

RSpec.describe RainfallThresholdParser do
  describe ".parse" do
    it "parses a bare number" do
      expect(described_class.parse("50.0")).to eq(BigDecimal("50.0"))
    end

    it "parses a unit-suffixed value sent by the application wizard" do
      expect(described_class.parse("10 mm")).to eq(BigDecimal("10"))
    end

    it "parses a unit-suffixed value with no space before the unit" do
      expect(described_class.parse("50mm")).to eq(BigDecimal("50"))
    end

    it "returns nil for a non-numeric value" do
      expect(described_class.parse("not-a-number")).to be_nil
    end

    it "returns nil for zero" do
      expect(described_class.parse("0")).to be_nil
    end

    it "returns nil for a negative value" do
      expect(described_class.parse("-10")).to be_nil
    end

    it "returns nil for digits split across multiple fragments" do
      expect(described_class.parse("1abc2 mm")).to be_nil
    end

    it "returns nil for exponential notation" do
      expect(described_class.parse("10e3")).to be_nil
    end

    it "returns nil for a value exceeding the storable precision" do
      expect(described_class.parse("1" * 300)).to be_nil
    end

    it "parses a value at the maximum storable precision" do
      expect(described_class.parse("9999.99")).to eq(BigDecimal("9999.99"))
    end
  end
end
