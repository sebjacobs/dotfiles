"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.getOptions = (vscode) => {
    const options = {};
    if (vscode.workspace.rootPath) {
        options.cwd = vscode.workspace.rootPath;
    }
    return options;
};
//# sourceMappingURL=command.js.map