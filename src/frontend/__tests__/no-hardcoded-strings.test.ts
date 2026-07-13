import fs from 'node:fs';
import path from 'node:path';

const roots = ['components', 'app'];
const projectRoot = process.cwd();

function collectTsxFiles(directory: string): string[] {
  const absolute = path.join(projectRoot, directory);
  if (!fs.existsSync(absolute)) {
    return [];
  }

  return fs.readdirSync(absolute, { withFileTypes: true }).flatMap((entry) => {
    const entryPath = path.join(absolute, entry.name);
    if (entry.isDirectory()) {
      return collectTsxFiles(path.join(directory, entry.name));
    }
    return entry.isFile() && entry.name.endsWith('.tsx') ? [entryPath] : [];
  });
}

describe('UI strings use locale files', () => {
  it('does not contain hardcoded JSX text nodes', () => {
    const files = roots.flatMap(collectTsxFiles);
    const violations: string[] = [];
    const jsxTextPattern = />\s*([^<{][^<>]*?)\s*</g;
    const japanesePattern = /[぀-ヿ㐀-鿿]/;
    const englishSentencePattern = /\b[A-Za-z]+(?:\s+[A-Za-z]+){2,}\b/;

    for (const file of files) {
      const source = fs.readFileSync(file, 'utf8');
      let match: RegExpExecArray | null;

      while ((match = jsxTextPattern.exec(source)) !== null) {
        const text = match[1].replace(/\s+/g, ' ').trim();
        if (!text) {
          continue;
        }
        if (/^[0-9]+$/.test(text)) {
          continue;
        }
        if (/^(ja|en|fr|zh|ru|es|ar)$/i.test(text)) {
          continue;
        }
        if (japanesePattern.test(text) || englishSentencePattern.test(text)) {
          violations.push(`${path.relative(projectRoot, file)} => ${text}`);
        }
      }
    }

    expect(violations).toEqual([]);
  });
});
