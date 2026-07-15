import { render, screen } from "@testing-library/react";
import LoginPage from "../app/login/page";

describe("Login page", () => {
  it("renders the login form", () => {
    render(<LoginPage />);

    expect(
      screen.getByRole("heading", {
        name: /Google ID トークンを BFF に渡してセッションを開始します。/,
      })
    ).toBeInTheDocument();
    expect(screen.getByRole("button", { name: /セッションを作成/ })).toBeInTheDocument();
  });
});
