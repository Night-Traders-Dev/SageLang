# Sage Language for VS Code

This extension provides editor support for `.sage` files.

Included features:
- Syntax highlighting for keywords, control flow, declarations, imports, module/member access, built-ins, operators, strings, numbers, and comments.
- Language configuration for comment toggling (`#`), bracket pairs, auto-close pairs, and off-side indentation/folding behavior.

## Run In Extension Dev Host

1. Open `editors/vscode/` in VS Code.
2. Press `F5` to launch an Extension Development Host.
3. Open any `.sage` file and select `Sage` language mode if needed.

### Package a VSIX

From `editors/vscode/` run:

```bash
npm install
npm run package
```

This produces a `.vsix` file installable via `Extensions: Install from VSIX...`.

## Files

- `package.json`: extension manifest
- `language-configuration.json`: comments, brackets, indentation
- `syntaxes/sage.tmLanguage.json`: TextMate grammar
