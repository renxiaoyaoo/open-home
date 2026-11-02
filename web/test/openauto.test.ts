import assert from "node:assert/strict";
import test from "node:test";
import { normalizeVehicleEnergy, normalizeVehicleSummary } from "../lib/openauto.ts";

test("normalizes a vehicle-condition response without retaining provider fields", () => {
  const summary = normalizeVehicleSummary({
    vin: "TEST-VEHICLE",
    modelName: "测试车辆",
    elecPercent: "63",
    oilPercent: 42,
    enduranceMileage: "515",
    evEndurance: 68,
    oilEndurance: 447,
    chargingState: 1,
    chargingPower: "6.5",
    remainingHours: 1,
    remainingMinutes: 25,
    totalMileage: "12000.5",
    speed: 0,
    signalStrength: 4,
    onlineStatus: 1,
    leftFrontTirepressure: 250,
    rightFrontTirepressure: 251,
    leftRearTirepressure: 248,
    rightRearTirepressure: 249,
  });
  assert.deepEqual(summary, {
    id: "TEST-VEHICLE",
    name: "测试车辆",
    powerState: "unknown",
    estimatedRangeKm: 515,
    electricRangeKm: 68,
    fuelRangeKm: 447,
    tractionBatteryPercent: 63,
    fuelPercent: 42,
    chargingState: "charging",
    chargingPowerKw: 6.5,
    remainingChargeMinutes: 85,
    odometerKm: 12000.5,
    speedKph: 0,
    signalStrength: 4,
    online: true,
    tirePressureKpa: { frontLeft: 250, frontRight: 251, rearLeft: 248, rearRight: 249 },
    updatedAt: undefined,
  });
});

test("normalizes current and cumulative energy readings", () => {
  const energy = normalizeVehicleEnergy({
    recentlyFiftyAverageEle: "14.8",
    recentlyFiftyAverageFuel: "3.2",
    totalPower: 1250,
    totalOil: 410,
    totalMileage: "24000",
    totalAverageEle: "15.6",
    totalAverageFuel: "4.1",
  });
  assert.equal(energy.recentDistanceKm, 50);
  assert.equal(energy.electricityKwhPer100Km, 14.8);
  assert.equal(energy.fuelLitresPer100Km, 3.2);
  assert.equal(energy.electricityKwh, 1250);
  assert.equal(energy.fuelLitres, 410);
  assert.equal(energy.totalDistanceKm, 24000);
  assert.equal(energy.cumulativeElectricityKwhPer100Km, 15.6);
  assert.equal(energy.cumulativeFuelLitresPer100Km, 4.1);
  assert.deepEqual(energy.recentTrend, []);
});

test("drops provider sentinel values from charging state", () => {
  const summary = normalizeVehicleSummary({ vin: "TEST-VEHICLE", chargingPower: "-999", remainingHours: -999, remainingMinutes: -999 });
  assert.equal(summary.chargingPowerKw, undefined);
  assert.equal(summary.remainingChargeMinutes, undefined);
});

test("rejects a response without a stable vehicle identity", () => {
  assert.throws(() => normalizeVehicleSummary({ elecPercent: 50 }), /identifier/i);
});
