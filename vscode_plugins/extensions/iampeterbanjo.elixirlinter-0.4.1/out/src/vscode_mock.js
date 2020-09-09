"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.commands = {
    registerCommand: (name, callback) => {
        return {
            dispose: () => {
                return 0;
            },
        };
    },
};
exports.languages = {
    createDiagnosticCollection: (name) => {
        return {
            clear: () => {
                return 0;
            },
            delete: () => {
                return 0;
            },
            dispose: () => {
                return 0;
            },
        };
    },
};
exports.workspace = {
    getConfiguration: () => {
        return 0;
    },
    onDidCloseTextDocument: () => {
        return 0;
    },
    onDidOpenTextDocument: () => {
        return 0;
    },
    onDidSaveTextDocument: () => {
        return 0;
    },
};
exports.Diagnostic = (range, message, severity) => {
    return {
        message,
        range,
        severity,
    };
};
exports.textDocument = {
    getText: () => {
        return "hello world!";
    },
    languageId: "elixir",
    uri: "/path/to/file",
};
//# sourceMappingURL=vscode_mock.js.map