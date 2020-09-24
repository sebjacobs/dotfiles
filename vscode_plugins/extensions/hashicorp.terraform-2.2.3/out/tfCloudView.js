"use strict";
var __awaiter = (this && this.__awaiter) || function (thisArg, _arguments, P, generator) {
    function adopt(value) { return value instanceof P ? value : new P(function (resolve) { resolve(value); }); }
    return new (P || (P = Promise))(function (resolve, reject) {
        function fulfilled(value) { try { step(generator.next(value)); } catch (e) { reject(e); } }
        function rejected(value) { try { step(generator["throw"](value)); } catch (e) { reject(e); } }
        function step(result) { result.done ? resolve(result.value) : adopt(result.value).then(fulfilled, rejected); }
        step((generator = generator.apply(thisArg, _arguments || [])).next());
    });
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.TFCloudView = void 0;
const vscode = require("vscode");
const tfCloudClient_1 = require("./tfCloudClient");
class TFProvider {
    constructor() {
        this.client = new tfCloudClient_1.tfCloudClient();
        this._onDidChangeTreeData = new vscode.EventEmitter();
        this.onDidChangeTreeData = this._onDidChangeTreeData.event;
    }
    getChildren(element) {
        if (!element) {
            return this.getWorkspaces();
        }
        // if (element.details) {
        // 	return [{label: element.details}]
        // }
        return [];
    }
    getTreeItem(element) {
        return {
            label: element.name,
            description: element.organization
        };
    }
    loadData() {
        this.client.refresh();
        this.status = "initialized";
        this.refresh();
    }
    getWorkspaces() {
        if (this.status === "initialized") {
            return this.client.workspaces();
        }
        return [];
    }
    refresh() {
        this._onDidChangeTreeData.fire();
    }
}
class TFCloudView {
    constructor(context) {
        const workspaceProvider = new TFProvider();
        vscode.window.registerTreeDataProvider("tfcWorkspaces", workspaceProvider);
        vscode.commands.registerCommand("tfc.connect", () => __awaiter(this, void 0, void 0, function* () {
            workspaceProvider.loadData();
        }));
    }
}
exports.TFCloudView = TFCloudView;
//# sourceMappingURL=tfCloudView.js.map