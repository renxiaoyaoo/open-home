export type VehiclePowerState = "off" | "on" | "unknown";
export type VehicleCornerState = { frontLeft?: boolean; frontRight?: boolean; rearLeft?: boolean; rearRight?: boolean };
export type VehicleHealthState = "normal" | "warning" | "unknown";

export type VehicleSummary = {
  id: string;
  name: string;
  powerState: VehiclePowerState;
  estimatedRangeKm?: number;
  electricRangeKm?: number;
  fuelRangeKm?: number;
  tractionBatteryPercent?: number;
  fuelPercent?: number;
  chargingState?: "charging" | "complete" | "stopped" | "unknown";
  chargingPowerKw?: number;
  remainingChargeMinutes?: number;
  odometerKm?: number;
  evMileageKm?: number;
  hevMileageKm?: number;
  speedKph?: number;
  signalStrength?: number;
  online?: boolean;
  securityState?: "normal" | "setting" | "active" | "unknown";
  driveMode?: "electric" | "hybrid" | "unknown";
  okIndicator?: boolean;
  powerOutputKw?: number;
  engineCoolantC?: number;
  health?: Record<string, VehicleHealthState>;
  doorsOpen?: VehicleCornerState;
  doorsUnlocked?: VehicleCornerState;
  windowsOpen?: VehicleCornerState;
  hoodOpen?: boolean;
  trunkOpen?: boolean;
  skylightOpen?: boolean;
  cabinTemperatureC?: number;
  locationName?: string;
  tirePressureKpa?: { frontLeft?: number; frontRight?: number; rearLeft?: number; rearRight?: number };
  updatedAt?: string;
};

export type EnergyBreakdown = {
  propulsionPercent?: number;
  climatePercent?: number;
  electricalPercent?: number;
  otherPercent?: number;
};

export type EnergyTrendPoint = {
  date: string;
  equivalentFuelLitresPer100Km?: number;
  electricityKwhPer100Km?: number;
  fuelLitresPer100Km?: number;
  peerAverageLitresPer100Km?: number;
};

export type VehicleEnergy = {
  rankPercent?: number;
  cumulativeRankPercent?: number;
  recentDistanceKm?: number;
  equivalentFuelLitresPer100Km?: number;
  electricityKwhPer100Km?: number;
  fuelLitresPer100Km?: number;
  electricityKwh?: number;
  fuelLitres?: number;
  costYuan?: number;
  breakdown?: EnergyBreakdown;
  recentTrend: EnergyTrendPoint[];
  totalDistanceKm?: number;
  cumulativeEquivalentFuelLitresPer100Km?: number;
  cumulativeElectricityKwhPer100Km?: number;
  cumulativeFuelLitresPer100Km?: number;
  costPerKmYuan?: number;
  updatedAt?: string;
};

export interface OpenAutoProvider {
  listVehicles(): Promise<VehicleSummary[]>;
  getVehicleSummary(vehicleId: string): Promise<VehicleSummary>;
  getVehicleEnergy(vehicleId: string): Promise<VehicleEnergy>;
}
type RawVehicle = Record<string, unknown>;

function finite(value: unknown) {
  const number = typeof value === "number" ? value : typeof value === "string" && value.trim() ? Number(value) : Number.NaN;
  return Number.isFinite(number) && ![-999, -9999, 65535].includes(number) ? number : undefined;
}

function nonnegative(value: unknown) {
  const number = finite(value);
  return number !== undefined && number >= 0 ? number : undefined;
}

function percent(value: unknown) {
  const number = finite(value);
  return number !== undefined && number >= 0 && number <= 100 ? number : undefined;
}

function leadingPercent(value: RawVehicle) {
  const direct = percent(value.rankPercent);
  if (direct !== undefined) return direct;
  const rank = finite(value.rank); const size = finite(value.size);
  if (rank === undefined || size === undefined || rank <= 0 || size <= 0 || rank > size) return undefined;
  return size === 1 ? 100 : Math.trunc(((size - rank) / (size - 1)) * 100);
}

function text(value: unknown) {
  return typeof value === "string" && value.trim() ? value.trim() : undefined;
}

function chargingState(value: unknown): VehicleSummary["chargingState"] {
  const state = String(value ?? "").toLowerCase();
  if (["1", "charging", "charge"].includes(state)) return "charging";
  if (["2", "complete", "completed", "full"].includes(state)) return "complete";
  if (["0", "3", "stopped", "stop", "idle"].includes(state)) return "stopped";
  return "unknown";
}

function flag(value: unknown, active: number) {
  if (typeof value === "boolean") return value;
  const number = finite(value);
  return number === undefined ? undefined : number === active;
}

function healthState(value: unknown): VehicleHealthState {
  const number = finite(value);
  if (number === 0) return "normal";
  if (number !== undefined && number > 0) return "warning";
  const state = String(value ?? "").toLowerCase();
  return ["normal", "ok"].includes(state) ? "normal" : ["warning", "error", "fault"].includes(state) ? "warning" : "unknown";
}

function timestamp(value: unknown) {
  const stringValue = text(value);
  if (stringValue) return stringValue;
  const number = finite(value);
  if (number === undefined || number <= 0) return undefined;
  const date = new Date(number < 10_000_000_000 ? number * 1000 : number);
  return Number.isNaN(date.getTime()) ? undefined : date.toISOString();
}

export function normalizeVehicleSummary(raw: RawVehicle, fallbackId = "") : VehicleSummary {
  const id = text(raw.id) || text(raw.vehicleId) || text(raw.vin) || fallbackId;
  if (!id) throw new Error("Vehicle identifier is missing");
  const hours = nonnegative(raw.remainingHours);
  const minutes = nonnegative(raw.remainingMinutes);
  const remainingChargeMinutes = hours !== undefined || minutes !== undefined
    ? Math.max(0, Math.round((hours || 0) * 60 + (minutes || 0)))
    : undefined;
  const power = String(raw.powerState ?? raw.vehiclePowerState ?? "").toLowerCase();
  const powerGear = finite(raw.powerGear);
  const vehicleState = finite(raw.vehicleState);
  const driveMode = finite(raw.pwr);
  const totalMileage = nonnegative(raw.totalMileage);
  const hevMileage = nonnegative(raw.hevMileage);
  const reportedEvMileage = nonnegative(raw.evMileage);
  const electricRangeKm = nonnegative(raw.evEndurance) ?? nonnegative(raw.batteryEnduranceMileage);
  const fuelRangeKm = nonnegative(raw.oilEndurance) ?? nonnegative(raw.oilEnduranceMileage);
  const health = {
    engine: healthState(raw.engineStatus), braking: healthState(raw.brakingSystem), abs: healthState(raw.abs), srs: healthState(raw.srs),
    tirePressure: healthState(raw.tirepressureSystem), stability: healthState(raw.esp), steering: healthState(raw.steeringSystem),
    coolant: healthState(raw.ect), oilPressure: healthState(raw.oilPressureSystem), lowVoltage: healthState(raw.chargingSystem),
    tractionBattery: healthState(raw.powerBattery), powertrain: healthState(raw.powerSystem),
  };
  return {
    id,
    name: text(raw.name) || text(raw.vehicleName) || text(raw.modelName) || "车辆",
    powerState: powerGear === 3 || ["1", "on", "running"].includes(power) ? "on" : powerGear === 1 || ["0", "off", "stopped"].includes(power) ? "off" : "unknown",
    estimatedRangeKm: electricRangeKm !== undefined && fuelRangeKm !== undefined ? electricRangeKm + fuelRangeKm : nonnegative(raw.totalEnduranceMileage) ?? nonnegative(raw.enduranceMileage),
    electricRangeKm,
    fuelRangeKm,
    tractionBatteryPercent: percent(raw.elecPercent),
    fuelPercent: percent(raw.oilPercent),
    chargingState: chargingState(raw.chargingState),
    chargingPowerKw: nonnegative(raw.chargingPower),
    remainingChargeMinutes,
    odometerKm: totalMileage,
    evMileageKm: reportedEvMileage ?? (totalMileage !== undefined && hevMileage !== undefined && hevMileage <= totalMileage ? totalMileage - hevMileage : undefined),
    hevMileageKm: hevMileage,
    speedKph: nonnegative(raw.speed),
    signalStrength: finite(raw.signalStrength),
    online: finite(raw.onlineStatus) === 1,
    securityState: vehicleState === 0 ? "normal" : vehicleState === 1 ? "setting" : vehicleState === 2 ? "active" : "unknown",
    driveMode: driveMode === 0 ? "hybrid" : driveMode === 1 ? "electric" : "unknown",
    okIndicator: flag(raw.okLight, 1),
    powerOutputKw: finite(raw.rate),
    engineCoolantC: finite(raw.ect) === 0 && finite(raw.ectValue) !== -1 ? finite(raw.ectValue) : undefined,
    ...(Object.values(health).some((value) => value !== "unknown") ? { health } : {}),
    doorsOpen: { frontLeft: flag(raw.leftFrontDoor, 1), frontRight: flag(raw.rightFrontDoor, 1), rearLeft: flag(raw.leftRearDoor, 1), rearRight: flag(raw.rightRearDoor, 1) },
    doorsUnlocked: { frontLeft: flag(raw.leftFrontDoorLock, 1), frontRight: flag(raw.rightFrontDoorLock, 1), rearLeft: flag(raw.leftRearDoorLock, 1), rearRight: flag(raw.rightRearDoorLock, 1) },
    windowsOpen: { frontLeft: flag(raw.leftFrontWindow, 2), frontRight: flag(raw.rightFrontWindow, 2), rearLeft: flag(raw.leftRearWindow, 2), rearRight: flag(raw.rightRearWindow, 2) },
    hoodOpen: flag(raw.forehold, 1),
    trunkOpen: flag(raw.trunkOpen ?? raw.trunkLid ?? raw.trunkStatus ?? raw.trunk, 1),
    skylightOpen: flag(raw.skylight, 2),
    cabinTemperatureC: finite(raw.tempInCar) ?? finite(raw.insideTemperature) ?? finite(raw.carInnerTemperature),
    locationName: text(raw.locationName) || text(raw.locationAddress) || text(raw.address) || text(raw.poiName),
    tirePressureKpa: {
      frontLeft: nonnegative(raw.leftFrontTirepressure), frontRight: nonnegative(raw.rightFrontTirepressure),
      rearLeft: nonnegative(raw.leftRearTirepressure), rearRight: nonnegative(raw.rightRearTirepressure),
    },
    updatedAt: timestamp(raw.updatedAt) || timestamp(raw.updateTime) || timestamp(raw.time),
  };
}

export function normalizeVehicleEnergy(raw: RawVehicle): VehicleEnergy {
  return {
    rankPercent: leadingPercent(raw),
    recentDistanceKm: finite(raw.recentDistanceKm) ?? finite(raw.recent50kmMileage) ?? (raw.recentlyFiftyAverageEle !== undefined || raw.recentlyFiftyAverageFuel !== undefined ? 50 : undefined),
    equivalentFuelLitresPer100Km: nonnegative(raw.equivalentFuelLitresPer100Km) ?? nonnegative(raw.recent50kmEnergy) ?? nonnegative(raw.nearestEnergyConsumption) ?? nonnegative(raw.energyConsumption),
    electricityKwhPer100Km: nonnegative(raw.electricityKwhPer100Km) ?? nonnegative(raw.recent50kmElecAverage) ?? nonnegative(raw.recentlyFiftyAverageEle),
    fuelLitresPer100Km: nonnegative(raw.fuelLitresPer100Km) ?? nonnegative(raw.recent50kmOilAverage) ?? nonnegative(raw.recentlyFiftyAverageFuel),
    electricityKwh: nonnegative(raw.totalPower),
    fuelLitres: nonnegative(raw.totalOil),
    totalDistanceKm: finite(raw.totalDistanceKm) ?? finite(raw.totalMileage),
    cumulativeEquivalentFuelLitresPer100Km: nonnegative(raw.cumulativeEquivalentFuelLitresPer100Km) ?? nonnegative(raw.totalEnergy) ?? nonnegative(raw.totalConsumptionEn),
    cumulativeElectricityKwhPer100Km: nonnegative(raw.cumulativeElectricityKwhPer100Km) ?? nonnegative(raw.totalElecAverage) ?? nonnegative(raw.totalAverageEle),
    cumulativeFuelLitresPer100Km: nonnegative(raw.cumulativeFuelLitresPer100Km) ?? nonnegative(raw.totalOilAverage) ?? nonnegative(raw.totalAverageFuel),
    recentTrend: [],
    updatedAt: timestamp(raw.updatedAt) || timestamp(raw.updateTime) || timestamp(raw.time),
  };
}

export function normalizeDetailedVehicleEnergy(recentInput: RawVehicle, historicalInput: RawVehicle = recentInput, totalDistanceKm?: number): VehicleEnergy {
  const recent = recentInput.recentOilData && typeof recentInput.recentOilData === "object" ? recentInput.recentOilData as RawVehicle : recentInput;
  const historical = historicalInput;
  const sum = historical.sumOilData && typeof historical.sumOilData === "object" ? historical.sumOilData as RawVehicle : {};
  const trend = Array.isArray(historical.selfList) ? historical.selfList : [];
  const peers = Array.isArray(historical.firstRecentList) ? historical.firstRecentList as RawVehicle[] : [];
  const breakdown = {
    propulsionPercent: percent(recent.driveConP), climatePercent: percent(recent.acConP),
    electricalPercent: percent(recent.elecConP), otherPercent: percent(recent.restConP),
  };
  return {
    rankPercent: leadingPercent(recent),
    recentDistanceKm: finite(recent.dkm) ?? 50,
    equivalentFuelLitresPer100Km: nonnegative(recent.avgFullCon) ?? nonnegative(recent.fee), electricityKwhPer100Km: nonnegative(recent.avgEvCon) ?? nonnegative(recent.elect), fuelLitresPer100Km: nonnegative(recent.avgOilCon) ?? nonnegative(recent.fuel),
    electricityKwh: nonnegative(recent.mxElect), fuelLitres: nonnegative(recent.mxOil), costYuan: nonnegative(recent.cost),
    breakdown: Object.values(breakdown).some((value) => value !== undefined && value > 0) ? breakdown : undefined,
    recentTrend: trend.map((item, index) => item && typeof item === "object" ? {
      date: text((item as RawVehicle).date) || text((item as RawVehicle).energyDate) || "", equivalentFuelLitresPer100Km: nonnegative((item as RawVehicle).lastFee) ?? nonnegative((item as RawVehicle).fee), peerAverageLitresPer100Km: nonnegative(peers[index]?.lastFee) ?? nonnegative(peers[index]?.fee) ?? nonnegative(peers[0]?.lastFee) ?? nonnegative(peers[0]?.fee),
    } : { date: "" }).filter((item) => item.date),
    totalDistanceKm,
    cumulativeRankPercent: leadingPercent(sum),
    cumulativeEquivalentFuelLitresPer100Km: nonnegative(sum.fee), cumulativeElectricityKwhPer100Km: nonnegative(sum.elect), cumulativeFuelLitresPer100Km: nonnegative(sum.fuel),
    costPerKmYuan: nonnegative(sum.cost), updatedAt: timestamp(recent.energyDate),
  };
}
