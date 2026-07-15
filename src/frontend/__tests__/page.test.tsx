import { render, screen } from "@testing-library/react";
import Home from "../app/page";

describe("Home page", () => {
  it("renders the localized home copy", () => {
    render(<Home />);

    expect(
      screen.getByRole("heading", {
        name: /ブラウザから Rails を隠したまま、模擬支払の流れを確認できます。/,
      })
    ).toBeInTheDocument();
    expect(screen.getByRole("link", { name: /ログイン画面へ/ })).toBeInTheDocument();
  });
});
