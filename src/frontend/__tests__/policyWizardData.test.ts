import { findThresholdOption } from "../components/wizard/policyWizardData";

describe("findThresholdOption", () => {
  it("matches seismic thresholds by exact value", () => {
    expect(findThresholdOption("seismic", "5強")?.key).toBe("seismic_5_strong");
  });

  it("returns undefined for an unknown seismic threshold", () => {
    expect(findThresholdOption("seismic", "存在しない震度")).toBeUndefined();
  });

  it("matches a rainfall threshold sent as-is by the application wizard (\"10 mm\")", () => {
    expect(findThresholdOption("rainfall", "10 mm")?.key).toBe("rainfall_10");
  });

  it("matches a rainfall threshold normalized and stored by the backend (\"10.0\")", () => {
    expect(findThresholdOption("rainfall", "10.0")?.key).toBe("rainfall_10");
  });

  it("matches a bare-integer rainfall threshold (\"50\")", () => {
    expect(findThresholdOption("rainfall", "50")?.key).toBe("rainfall_50");
  });

  it("returns undefined for a rainfall threshold with no matching option", () => {
    expect(findThresholdOption("rainfall", "9999.99")).toBeUndefined();
  });

  it("returns undefined for a non-numeric rainfall threshold", () => {
    expect(findThresholdOption("rainfall", "not-a-number")).toBeUndefined();
  });
});
