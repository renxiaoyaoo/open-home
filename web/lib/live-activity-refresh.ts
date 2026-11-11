import { liveActivityResources, type LiveActivityProvider } from "./live-activities.ts";
import { apnsConfiguration, FetchLiveActivityPushTransport, publishLiveActivity, type APNsConfiguration, type LiveActivityPushTransport } from "./live-activity-push.ts";
import { autoLiveActivity, dryerLiveActivity, type LiveActivitySnapshot } from "./live-activity-state.ts";

export type LiveActivityStateReader = (provider: LiveActivityProvider, resourceId: string) => Promise<LiveActivitySnapshot>;

export async function readLiveActivityState(provider: LiveActivityProvider, resourceId: string) {
  if (provider === "living") {
    const { readDryerStatus } = await import("./dryer-adapter.ts");
    return dryerLiveActivity(await readDryerStatus(resourceId));
  }
  const { readOpenAutoStatus } = await import("./openauto-adapter.ts");
  return autoLiveActivity(await readOpenAutoStatus(resourceId));
}

export async function refreshLiveActivities(reader: LiveActivityStateReader = readLiveActivityState, configuration?: APNsConfiguration, transport: LiveActivityPushTransport = new FetchLiveActivityPushTransport()) {
  const resources = await liveActivityResources();
  if (resources.length === 0) return [];
  const pushConfiguration = configuration ?? apnsConfiguration();
  const results = [];
  for (const resource of resources) {
    try {
      const snapshot = await reader(resource.provider, resource.resourceId);
      results.push({ ...resource, ok: true, deliveries: await publishLiveActivity(resource.provider, resource.resourceId, snapshot.state, snapshot.event, pushConfiguration, transport) });
    } catch (error) {
      results.push({ ...resource, ok: false, message: error instanceof Error ? error.message : "Live Activity refresh failed" });
    }
  }
  return results;
}
