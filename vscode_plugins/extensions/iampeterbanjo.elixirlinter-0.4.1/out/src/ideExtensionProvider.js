"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
class IdeExtensionProvider {
    constructor(diagnosticCollection, command) {
        this.dispose = () => {
            this.diagnosticCollection.clear();
            this.diagnosticCollection.dispose();
            this.command.dispose();
        };
        this.removeFromDiagnosticCollection = (uri) => {
            this.diagnosticCollection.delete(uri);
        };
        this.diagnosticCollection = diagnosticCollection;
        this.command = command;
    }
    activate(extension, subscriptions, vscode, linter) {
        subscriptions.push(extension);
        vscode.workspace.onDidOpenTextDocument(linter, extension, subscriptions);
        vscode.workspace.onDidSaveTextDocument(linter, extension);
        vscode.workspace.onDidCloseTextDocument(this.removeFromDiagnosticCollection, null, subscriptions);
    }
}
exports.default = IdeExtensionProvider;
//# sourceMappingURL=ideExtensionProvider.js.map