import { render, screen } from "@testing-library/react";
import Home from "../app/page";

describe("Home page", () => {
  it("renders the localized home copy", () => {
    render(<Home />);

    expect(
      screen.getByRole("heading", {
        name: /震度・降雨量に連動する、次世代の即日模擬支払を体験/,
      })
    ).toBeInTheDocument();
    expect(screen.getByRole("link", { name: /ログインして模擬申込へ/ })).toBeInTheDocument();
  });
});
