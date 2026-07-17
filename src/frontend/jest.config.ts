import type { Config } from "jest";
import nextJest from "next/jest.js";

const createJestConfig = nextJest({
  dir: "./",
});

const config: Config = {
  coverageProvider: "v8",
  testEnvironment: "jsdom",
  setupFilesAfterEnv: ["<rootDir>/jest.setup.ts"],
  roots: ["<rootDir>", "<rootDir>/../../test"],
  // "spec" 命名はPlaywright（*.e2e.spec.js等、test/pr**配下）が使うため、
  // Jestは "test" 命名のみを対象にして誤って拾わないようにする。
  testMatch: ["**/__tests__/**/*.[jt]s?(x)", "**/?(*.)+(test).[tj]s?(x)"],
  // test/pr** はrootDir（src/frontend）の外にあるため、モジュール解決の
  // 起点をrootDirのnode_modulesに固定しないと next/react 等が解決できない。
  modulePaths: ["<rootDir>/node_modules"],
};

export default createJestConfig(config);
