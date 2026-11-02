import assert from "node:assert/strict";
import test from "node:test";
import { normalizeDetailedVehicleEnergy, normalizeVehicleEnergy, normalizeVehicleSummary } from "../lib/openauto.ts";

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
    evMileageKm: undefined,
    hevMileageKm: undefined,
    speedKph: 0,
    signalStrength: 4,
    online: true,
    securityState: "unknown",
    driveMode: "unknown",
    okIndicator: undefined,
    engineCoolantC: undefined,
    doorsOpen: { frontLeft: undefined, frontRight: undefined, rearLeft: undefined, rearRight: undefined },
    doorsUnlocked: { frontLeft: undefined, frontRight: undefined, rearLeft: undefined, rearRight: undefined },
    windowsOpen: { frontLeft: undefined, frontRight: undefined, rearLeft: undefined, rearRight: undefined },
    hoodOpen: undefined,
    trunkOpen: undefined,
    skylightOpen: undefined,
    chargingPortLeftOpen: undefined,
    chargingPortRightOpen: undefined,
    cabinTemperatureC: undefined,
    tirePressureKpa: { frontLeft: 250, frontRight: 251, rearLeft: 248, rearRight: 249 },
    updatedAt: undefined,
  });
});

test("normalizes the official vehicle-state and opening codes", () => {
  const summary = normalizeVehicleSummary({
    vin: "TEST-VEHICLE", powerGear: 3, vehicleState: 1, pwr: 1, okLight: 1, ect: 0, ectValue: 82,
    leftFrontDoor: 1, rightFrontDoor: 0, leftRearDoor: 0, rightRearDoor: 1,
    leftFrontDoorLock: 1, rightFrontDoorLock: 0, leftRearDoorLock: 0, rightRearDoorLock: 0,
    leftFrontWindow: 2, rightFrontWindow: 0, leftRearWindow: 0, rightRearWindow: 2,
    forehold: 1, trunk: 1, skylight: 2, chargingCoverLeft: 1, chargingCoverRight: 0, carInnerTemperature: 17,
    totalMileage: 8445, hevMileage: 3809, time: 1_800_000_000,
  });
  assert.equal(summary.powerState, "on");
  assert.equal(summary.securityState, "setting");
  assert.equal(summary.driveMode, "electric");
  assert.equal(summary.okIndicator, true);
  assert.equal(summary.engineCoolantC, 82);
  assert.deepEqual(summary.doorsOpen, { frontLeft: true, frontRight: false, rearLeft: false, rearRight: true });
  assert.deepEqual(summary.doorsUnlocked, { frontLeft: true, frontRight: false, rearLeft: false, rearRight: false });
  assert.deepEqual(summary.windowsOpen, { frontLeft: true, frontRight: false, rearLeft: false, rearRight: true });
  assert.equal(summary.hoodOpen, true);
  assert.equal(summary.trunkOpen, true);
  assert.equal(summary.skylightOpen, true);
  assert.equal(summary.chargingPortLeftOpen, true);
  assert.equal(summary.chargingPortRightOpen, false);
  assert.equal(summary.cabinTemperatureC, 17);
  assert.equal(summary.evMileageKm, 4636);
  assert.equal(summary.hevMileageKm, 3809);
  assert.match(summary.updatedAt || "", /^2027-/);
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

test("normalizes the official detailed energy responses", () => {
  const energy = normalizeDetailedVehicleEnergy({
    dkm: "50", avgFullCon: "3.8", avgEvCon: "12.4", avgOilCon: "1.7", mxElect: "6.2", mxOil: "0.8", cost: "9.6",
    driveConP: 52, acConP: 18, elecConP: 11, restConP: 19, energyDate: "2026-11-02 20:10:00",
  }, {
    firstRecentList: [{ lastFee: "4.6" }], selfList: [{ date: "2026-11-01", lastFee: "4.1" }, { date: "2026-11-02", lastFee: "3.8" }],
    sumOilData: { fee: "4.3", elect: "13.2", fuel: "2.1", cost: "0.19" },
  }, 24000);
  assert.equal(energy.costYuan, 9.6);
  assert.deepEqual(energy.breakdown, { propulsionPercent: 52, climatePercent: 18, electricalPercent: 11, otherPercent: 19 });
  assert.deepEqual(energy.recentTrend, [
    { date: "2026-11-01", equivalentFuelLitresPer100Km: 4.1, peerAverageLitresPer100Km: 4.6 },
    { date: "2026-11-02", equivalentFuelLitresPer100Km: 3.8, peerAverageLitresPer100Km: 4.6 },
  ]);
  assert.equal(energy.cumulativeEquivalentFuelLitresPer100Km, 4.3);
  assert.equal(energy.costPerKmYuan, 0.19);
  assert.equal(energy.totalDistanceKm, 24000);
});

test("drops provider sentinel values from vehicle state", () => {
  const summary = normalizeVehicleSummary({ vin: "TEST-VEHICLE", enduranceMileage: -999, signalStrength: 65535, chargingPower: "-999", remainingHours: -999, remainingMinutes: -999, ect: 0, ectValue: -1 });
  assert.equal(summary.estimatedRangeKm, undefined);
  assert.equal(summary.signalStrength, undefined);
  assert.equal(summary.chargingPowerKw, undefined);
  assert.equal(summary.remainingChargeMinutes, undefined);
  assert.equal(summary.engineCoolantC, undefined);
});

test("derives combined range and omits empty energy readings", () => {
  const summary = normalizeVehicleSummary({ vin: "TEST-VEHICLE", evEndurance: 78, oilEndurance: 698 });
  assert.equal(summary.estimatedRangeKm, 776);
  const energy = normalizeDetailedVehicleEnergy({ avgFullCon: 0, avgEvCon: "0", avgOilCon: 0, mxElect: 0, mxOil: 0, cost: 0 }, { sumOilData: { fee: 0, elect: 0, fuel: 0, cost: 0 } }, 8445);
  assert.equal(energy.equivalentFuelLitresPer100Km, undefined);
  assert.equal(energy.electricityKwhPer100Km, undefined);
  assert.equal(energy.fuelLitresPer100Km, undefined);
  assert.equal(energy.costYuan, undefined);
  assert.equal(energy.totalDistanceKm, 8445);
});

test("rejects a response without a stable vehicle identity", () => {
  assert.throws(() => normalizeVehicleSummary({ elecPercent: 50 }), /identifier/i);
});
