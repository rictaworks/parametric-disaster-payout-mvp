import { render, screen } from "@testing-library/react";
import LoginPage from "../app/login/page";

function mockGoogleIdentityServices() {
  const renderButton = jest.fn((container: HTMLElement) => {
    container.replaceChildren();

    const button = document.createElement("button");
    button.type = "button";
    button.textContent = "Googleでログイン";
    container.appendChild(button);
  });
  const initialize = jest.fn();

  (window as typeof window & {
    google?: {
      accounts?: {
        id?: {
          initialize: typeof initialize;
          renderButton: typeof renderButton;
        };
      };
    };
  }).google = {
    accounts: {
      id: {
        initialize,
        renderButton,
      },
    },
  };
}

describe("Login page", () => {
  afterEach(() => {
    delete (window as typeof window & { google?: unknown }).google;
  });

  it("renders the Google login button and does not show the token paste field", () => {
    mockGoogleIdentityServices();

    render(<LoginPage />);

    expect(
      screen.getByRole("heading", {
        name: /Googleアカウントでログインします/,
      })
    ).toBeInTheDocument();
    expect(screen.getByRole("button", { name: /Googleでログイン/ })).toBeInTheDocument();
    expect(screen.queryByRole("textbox")).not.toBeInTheDocument();
  });
});
