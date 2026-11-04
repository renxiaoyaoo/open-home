import assert from "node:assert/strict";
import test from "node:test";
import { autoLiveActivity, dryerLiveActivity } from "../lib/live-activity-state.ts";

test("maps a running dryer to an expected completion without retaining provider fields", () => {
  const snapshot = dryerLiveActivity({ properties: [
    { code: "dryer.power", value: 1 },
    { code: "dryer.workStatus", value: 2 },
    { code: "dryer.currentDryingProgramId", value: 43 },
    { code: "dryer.remainingRunningTime", value: 127 },
  ] }, new Date("2026-11-04T10:00:00Z"));
  assert.deepEqual(snapshot, { event: "update", state: { title: "干衣机", state: "烘干中", detail: "大件烘", expectedEnd: new Date("2026-11-04T12:07:00Z") } });
});

test("ends a dryer activity at a terminal device state", () => {
  assert.equal(dryerLiveActivity({ "dryer.power": 0, "dryer.workStatus": 6 }).event, "end");
});

test("maps the real-time vehicle status to a compact activity", () => {
  const snapshot = autoLiveActivity({ id: "vehicle", name: "车辆", powerState: "off", chargingState: "charging", tractionBatteryPercent: 64, remainingChargeMinutes: 35 }, new Date("2026-11-04T10:00:00Z"));
  assert.deepEqual(snapshot, { event: "update", state: { title: "车辆", state: "充电中", detail: "电量 64%", progress: 0.64, expectedEnd: new Date("2026-11-04T10:35:00Z") } });
});
