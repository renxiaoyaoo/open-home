import { DRYER_PROGRAMS } from "./dryer-programs.ts";
import type { LiveActivityState } from "./live-activity-push.ts";
import type { VehicleSummary } from "./openauto.ts";

export type LiveActivitySnapshot = { event: "update" | "end"; state: LiveActivityState };

function expectedEnd(now: Date, remainingMinutes?: number) {
  return remainingMinutes && remainingMinutes > 0 ? new Date(Math.floor(now.getTime() / 60_000) * 60_000 + remainingMinutes * 60_000) : null;
}

function dryerProperties(raw: unknown) {
  const value = raw as { properties?: Array<{ code?: string; propertyCode?: string; value: unknown }>; data?: { properties?: Array<{ code?: string; propertyCode?: string; value: unknown }> } };
  const list = value?.properties || value?.data?.properties;
  return Array.isArray(list) ? Object.fromEntries(list.map((item) => [item.code || item.propertyCode || "", item.value])) : (raw || {}) as Record<string, unknown>;
}

export function dryerLiveActivity(raw: unknown, now = new Date()): LiveActivitySnapshot {
  const properties = dryerProperties(raw);
  const power = properties["dryer.power"] === true || properties["dryer.power"] === 1;
  const workStatus = String(properties["dryer.workStatus"] ?? "");
  const remaining = Math.max(0, Number(properties["dryer.remainingRunningTime"]) || 0);
  const program = DRYER_PROGRAMS.find((item) => item.value === Number(properties["dryer.currentDryingProgramId"]));
  const states: Record<string, string> = { "1": "待机", "2": "烘干中", "3": "已暂停", "4": "已预约", "5": "设备故障", "6": "烘干完成", "7": "待机", "8": "预约暂停", "9": "暂停锁定" };
  const terminal = !power || workStatus === "5" || workStatus === "6";
  return {
    event: terminal ? "end" : "update",
    state: {
      title: "干衣机",
      state: !power ? "已关机" : states[workStatus] || "已开机",
      detail: program?.name || null,
      expectedEnd: workStatus === "2" ? expectedEnd(now, remaining) : null,
    },
  };
}

export function autoLiveActivity(summary: VehicleSummary, now = new Date()): LiveActivitySnapshot {
  const warnings = Object.values(summary.health || {}).filter((value) => value === "warning").length;
  const charging = summary.chargingState === "charging";
  const moving = summary.powerState === "on" && (summary.speedKph || 0) > 0;
  const state = warnings ? `${warnings} 项异常` : charging ? "充电中" : moving ? "行驶中" : summary.powerState === "on" ? "已启动" : "已熄火";
  const detail = charging && summary.tractionBatteryPercent !== undefined ? `电量 ${summary.tractionBatteryPercent}%` : moving ? `${summary.speedKph} km/h` : summary.estimatedRangeKm !== undefined ? `续航 ${summary.estimatedRangeKm} km` : summary.locationName || null;
  return {
    event: charging || summary.powerState === "on" ? "update" : "end",
    state: {
      title: summary.name || "车辆",
      state,
      detail,
      progress: summary.tractionBatteryPercent !== undefined ? summary.tractionBatteryPercent / 100 : null,
      expectedEnd: charging ? expectedEnd(now, summary.remainingChargeMinutes) : null,
    },
  };
}
