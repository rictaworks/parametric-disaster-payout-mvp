import '@testing-library/jest-dom';
import React from 'react';

jest.mock('react-google-recaptcha', () => {
  return function MockReCAPTCHA(props: { onChange?: (token: string | null) => void }) {
    return React.createElement(
      'button',
      {
        type: 'button',
        onClick: () => props.onChange?.('test-token')
      },
      'mock-recaptcha'
    );
  };
});
