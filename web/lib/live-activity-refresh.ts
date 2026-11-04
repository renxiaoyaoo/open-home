import { readDryerStatus } from "./dryer-adapter.ts";
import { liveActivityResources, type LiveActivityProvider } from "./live-activities.ts";
import { apnsConfiguration, FetchLiveActivityPushTransport, publishLiveActivity, type APNsConfiguration, type LiveActivityPushTransport } from "./live-activity-push.ts";
import { autoLiveActivity, dryerLiveActivity, type LiveActivitySnapshot } from "./live-activity-state.ts";
import { readOpenAutoStatus } from "./openauto-adapter.ts";

export type LiveActivityStateReader = (provider: LiveActivityProvider, resourceId: string) => Promise<LiveActivitySnapshot>;

export async function readLiveActivityState(provider: LiveActivityProvider, resourceId: string) {
  return provider === "living" ? dryerLiveActivity(await readDryerStatus(resourceId)) : autoLiveActivity(await readOpenAutoStatus(resourceId));
}

export async function refreshLiveActivities(reader: LiveActivityStateReader = readLiveActivityState, configuration: APNsConfiguration = apnsConfiguration(), transport: LiveActivityPushTransport = new FetchLiveActivityPushTransport()) {
  const resources = await liveActivityResources();
  const results = [];
  for (const resource of resources) {
    try {
      const snapshot = await reader(resource.provider, resource.resourceId);
      results.push({ ...resource, ok: true, deliveries: await publishLiveActivity(resource.provider, resource.resourceId, snapshot.state, snapshot.event, configuration, transport) });
    } catch (error) {
      results.push({ ...resource, ok: false, message: error instanceof Error ? error.message : "Live Activity refresh failed" });
    }
  }
  return results;
}
