import "@xyflow/react/dist/style.css";
import { Suspense } from "react";
import { ActionCenter } from "@/components/runs/action-center";

export const metadata = { title: "Execution Trace — ByteOps" };

export default function RunsRoute() {
    return (
        <div
            className="h-screen flex flex-col overflow-hidden"
            style={{ background: "var(--background)" }}
        >
            <Suspense fallback={null}>
                <ActionCenter />
            </Suspense>
        </div>
    );
}
