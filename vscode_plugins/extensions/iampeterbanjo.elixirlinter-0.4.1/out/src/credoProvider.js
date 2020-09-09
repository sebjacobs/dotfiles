"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const cp = require("child_process");
const cmd = require("./command");
const parse = require("./parse");
const severity = require("../src/severity");
const ideExtensionProvider_1 = require("./ideExtensionProvider");
class ElixirLintingProvider {
    constructor(vscode) {
        this.makeZeroIndex = (value) => {
            if (value <= 0) {
                return 0;
            }
            return value - 1;
        };
        this.getDiagnosticInfo = (lineInfo) => {
            if (!lineInfo) {
                return;
            }
            const isNotAnumber = isNaN(parseInt(lineInfo.position, 10)) || isNaN(parseInt(lineInfo.column, 10));
            const isLessThanOrEqualToZero = lineInfo.position <= 0 || lineInfo.column <= 0;
            if (isNotAnumber || isLessThanOrEqualToZero) {
                return;
            }
            return {
                check: lineInfo.check,
                endColumn: this.makeZeroIndex(lineInfo.column),
                endLine: this.makeZeroIndex(lineInfo.position),
                message: lineInfo.message,
                startColumn: 0,
                startLine: this.makeZeroIndex(lineInfo.position),
            };
        };
        this.vscode = vscode;
        this.diagnosticCollection = vscode.languages.createDiagnosticCollection();
        this.extension = new ideExtensionProvider_1.default(this.diagnosticCollection, this.command);
    }
    /**
     * activate() and dispose() deal with set-up and tear-down in VS Code extensions.
     * The code below registers the command so that the CodeActionProvider can call it and
     *  sets up listeners to trigger the linting action.
     */
    activate(subscriptions, vscode = this.vscode) {
        this.extension.activate(this, subscriptions, vscode, this.linter);
        // Lint all open elixir documents
        vscode.workspace.textDocuments.forEach((item, index) => {
            this.linter(item, index, vscode);
        });
    }
    dispose() {
        this.extension.dispose();
    }
    // getDiagnosis for vscode.diagnostics
    getDiagnosis(item, vscode = this.vscode) {
        const range = new vscode.Range(item.startLine, item.startColumn, item.endLine, item.endColumn);
        const itemSeverity = severity.parse(item.check, vscode);
        const message = `${item.message} [${item.check}:${itemSeverity}]`;
        return new vscode.Diagnostic(range, message, itemSeverity);
    }
    parseOutput(output) {
        return parse.getLines(output).map((error) => {
            const lineInfo = parse.getLineInfo(error);
            return this.getDiagnosticInfo(lineInfo);
        });
    }
    /**
     * Using cp.spawn(), extensions can call any executable and process the results.
     * The code below uses cp.spawn() to call linter, parses the output into Diagnostic objects
     * and then adds them to a DiagnosticCollection with this.diagnosticCollection.set(textDocument.uri, diagnostics);
     * which add the chrome in the UI.
     */
    linter(textDocument, index, vscode = this.vscode) {
        if (textDocument.languageId !== "elixir") {
            return;
        }
        let decoded = "";
        const diagnostics = [];
        let args = ["credo", "list", "--format=oneline", "--read-from-stdin"];
        const settings = vscode.workspace.getConfiguration("elixirLinter");
        if (settings.useStrict === true) {
            args = args.concat("--strict");
        }
        // use stdin for credo to prevent running on entire project
        const childProcess = cp.spawn(ElixirLintingProvider.linterCommand, args, cmd.getOptions(vscode));
        childProcess.stdin.write(textDocument.getText());
        childProcess.stdin.end();
        if (childProcess.pid) {
            childProcess.stdout.on("data", (data) => {
                decoded += data;
            });
            childProcess.stdout.on("end", () => {
                this.parseOutput(decoded).forEach((item) => {
                    if (item) {
                        diagnostics.push(this.getDiagnosis(item, vscode));
                    }
                });
                this.diagnosticCollection.set(textDocument.uri, diagnostics);
            });
        }
    }
}
ElixirLintingProvider.linterCommand = "mix";
exports.default = ElixirLintingProvider;
//# sourceMappingURL=credoProvider.js.map