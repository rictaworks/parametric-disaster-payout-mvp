import fs from "node:fs";
import path from "node:path";
import ts from "typescript";

const repoRoot = path.resolve(__dirname, "..");
const inspectedFiles = [
  "app/layout.tsx",
  "app/page.tsx",
  "app/login/page.tsx",
  "components/AppShell.tsx",
  "components/DemoBanner.tsx",
  "components/LanguageSwitcher.tsx",
  "components/LoginForm.tsx",
  "components/PageSection.tsx",
];

function read(filePath: string) {
  return fs.readFileSync(path.join(repoRoot, filePath), "utf8");
}

describe("hardcoded copy guard", () => {
  it("keeps user-facing text out of the UI source files", () => {
    const rawTextNodes = inspectedFiles.flatMap((filePath) => {
      const source = read(filePath);
      const sourceFile = ts.createSourceFile(filePath, source, ts.ScriptTarget.Latest, true, ts.ScriptKind.TSX);
      const nodes: string[] = [];

      function visit(node: ts.Node) {
        if (ts.isJsxText(node) && node.getText(sourceFile).trim().length > 0) {
          nodes.push(`${filePath}: ${node.getText(sourceFile).trim()}`);
        }

        node.forEachChild(visit);
      }

      visit(sourceFile);
      return nodes;
    });

    expect(rawTextNodes).toEqual([]);
  });

  it("does not rely on browser alert dialogs", () => {
    const source = inspectedFiles.map(read).join("\n");

    expect(source).not.toMatch(/\balert\s*\(/);
    expect(source).not.toMatch(/\bconfirm\s*\(/);
    expect(source).not.toMatch(/\bprompt\s*\(/);
  });
});
