# Akashi の色分け（VS Code）

`.ak` のファイルを色分けし、`#` のコメント・かっこの対応・字下げを VS Code に教えます。依存はありません。

## 入れ方（手元で）

1. このフォルダ（`editors/vscode`）を、VS Code の拡張機能のフォルダに写します。
   - Windows：`%USERPROFILE%\.vscode\extensions\akashi-language`
   - macOS・Linux：`~/.vscode/extensions/akashi-language`
2. VS Code を開き直します。`.ak` のファイルが色分けされます。

Marketplace には出していません。

## 中身

| ファイル | 役目 |
| --- | --- |
| `package.json` | 拡張機能の名札（言語 `akashi`、拡張子 `.ak`） |
| `language-configuration.json` | コメント・かっこ・字下げ |
| `syntaxes/akashi.tmLanguage.json` | 色分けの決まり（TextMate の文法） |

言葉（キーワード・型の名前）を処理系に足したら、ここも直します。`test/editor.test.js` が、処理系の言葉と色分けの言葉がそろっているかを確かめます。
