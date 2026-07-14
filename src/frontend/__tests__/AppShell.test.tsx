import { render, screen } from "@testing-library/react";
import { AppShell } from "../components/AppShell";

describe("AppShell", () => {
  it("always renders the demo notice banner regardless of page content", () => {
    render(
      <AppShell>
        <p>page content</p>
      </AppShell>
    );

    expect(screen.getByRole("note")).toHaveTextContent(/模擬デモ/);
  });
});
