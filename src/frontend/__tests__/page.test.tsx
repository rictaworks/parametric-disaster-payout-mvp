import { render, screen } from "@testing-library/react";
import Home from "../app/page";

describe("Home page", () => {
  it("renders the demo disclaimer", () => {
    render(<Home />);
    expect(
      screen.getByText(/模擬デモ/)
    ).toBeInTheDocument();
  });
});
