"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.tfCloudClient = void 0;
class tfCloudClient {
    constructor() {
        this.data = {};
    }
    refresh() {
        this.data = {
            "workspaces": [
                {
                    "name": "Workspace A",
                    "organization": "HashiCorp"
                },
                {
                    "name": "Workspace B",
                    "organization": "HashiCorp"
                }
            ],
            "runs": [
                {
                    "name": "Run 1",
                    "workspace": "Workspace A",
                    "status": "success"
                }
            ]
        };
    }
    workspaces() {
        return this.data["workspaces"];
    }
}
exports.tfCloudClient = tfCloudClient;
//# sourceMappingURL=tfCloudClient.js.map