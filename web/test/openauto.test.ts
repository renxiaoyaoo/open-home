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
    chargingState: 1,
    chargingPower: "6.5",
    remainingHours: 1,
    remainingMinutes: 25,
    totalMileage: "12000.5",
  });
  assert.deepEqual(summary, {
    id: "TEST-VEHICLE",
    name: "测试车辆",
    powerState: "unknown",
    estimatedRangeKm: 515,
    tractionBatteryPercent: 63,
    fuelPercent: 42,
    chargingState: "charging",
    chargingPowerKw: 6.5,
    remainingChargeMinutes: 85,
    odometerKm: 12000.5,
    updatedAt: undefined,
  });
});

test("normalizes current and cumulative energy readings", () => {
  const energy = normalizeVehicleEnergy({
    recent50kmMileage: "50",
    recent50kmElecAverage: "14.8",
    recent50kmOilAverage: "3.2",
    totalMileage: "24000",
    totalElecAverage: "15.6",
    totalOilAverage: "4.1",
  });
  assert.equal(energy.recentDistanceKm, 50);
  assert.equal(energy.electricityKwhPer100Km, 14.8);
  assert.equal(energy.fuelLitresPer100Km, 3.2);
  assert.equal(energy.totalDistanceKm, 24000);
  assert.equal(energy.cumulativeElectricityKwhPer100Km, 15.6);
  assert.equal(energy.cumulativeFuelLitresPer100Km, 4.1);
  assert.deepEqual(energy.recentTrend, []);
});

test("rejects a response without a stable vehicle identity", () => {
  assert.throws(() => normalizeVehicleSummary({ elecPercent: 50 }), /identifier/i);
});
