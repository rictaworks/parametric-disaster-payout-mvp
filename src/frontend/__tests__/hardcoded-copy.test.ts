import fs from "node:fs";
import path from "node:path";
import ts from "typescript";

const repoRoot = path.resolve(__dirname, "..");

function collectTsxFiles(dir: string): string[] {
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      return collectTsxFiles(fullPath);
    }
    return entry.name.endsWith(".tsx") ? [path.relative(repoRoot, fullPath)] : [];
  });
}

const inspectedFiles = [
  ...collectTsxFiles(path.join(repoRoot, "app")),
  ...collectTsxFiles(path.join(repoRoot, "components")),
].sort();

function read(filePath: string) {
  return fs.readFileSync(path.join(repoRoot, filePath), "utf8");
}

describe("hardcoded copy guard", () => {
  it("scans at least the known app/ and components/ .tsx files", () => {
    expect(inspectedFiles.length).toBeGreaterThanOrEqual(8);
  });

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
