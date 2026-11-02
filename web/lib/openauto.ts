export type VehiclePowerState = "off" | "on" | "unknown";
export type VehicleCornerState = { frontLeft?: boolean; frontRight?: boolean; rearLeft?: boolean; rearRight?: boolean };

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
  speedKph?: number;
  signalStrength?: number;
  online?: boolean;
  securityState?: "normal" | "armed" | "alarm" | "unknown";
  driveMode?: "electric" | "hybrid" | "unknown";
  okIndicator?: boolean;
  engineCoolantC?: number;
  doorsOpen?: VehicleCornerState;
  doorsUnlocked?: VehicleCornerState;
  windowsOpen?: VehicleCornerState;
  hoodOpen?: boolean;
  skylightOpen?: boolean;
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
  const number = finite(value);
  return number === undefined ? undefined : number === active;
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
  return {
    id,
    name: text(raw.name) || text(raw.vehicleName) || text(raw.modelName) || "车辆",
    powerState: powerGear === 3 || ["1", "on", "running"].includes(power) ? "on" : powerGear === 1 || ["0", "off", "stopped"].includes(power) ? "off" : "unknown",
    estimatedRangeKm: finite(raw.enduranceMileage),
    electricRangeKm: nonnegative(raw.evEndurance),
    fuelRangeKm: nonnegative(raw.oilEndurance),
    tractionBatteryPercent: percent(raw.elecPercent),
    fuelPercent: percent(raw.oilPercent),
    chargingState: chargingState(raw.chargingState),
    chargingPowerKw: nonnegative(raw.chargingPower),
    remainingChargeMinutes,
    odometerKm: nonnegative(raw.totalMileage),
    speedKph: nonnegative(raw.speed),
    signalStrength: finite(raw.signalStrength),
    online: finite(raw.onlineStatus) === 1,
    securityState: vehicleState === 0 ? "normal" : vehicleState === 1 ? "armed" : vehicleState === 2 ? "alarm" : "unknown",
    driveMode: driveMode === 0 ? "hybrid" : driveMode === 1 ? "electric" : "unknown",
    okIndicator: flag(raw.okLight, 1),
    engineCoolantC: finite(raw.ect) === 0 ? finite(raw.ectValue) : undefined,
    doorsOpen: { frontLeft: flag(raw.leftFrontDoor, 1), frontRight: flag(raw.rightFrontDoor, 1), rearLeft: flag(raw.leftRearDoor, 1), rearRight: flag(raw.rightRearDoor, 1) },
    doorsUnlocked: { frontLeft: flag(raw.leftFrontDoorLock, 1), frontRight: flag(raw.rightFrontDoorLock, 1), rearLeft: flag(raw.leftRearDoorLock, 1), rearRight: flag(raw.rightRearDoorLock, 1) },
    windowsOpen: { frontLeft: flag(raw.leftFrontWindow, 2), frontRight: flag(raw.rightFrontWindow, 2), rearLeft: flag(raw.leftRearWindow, 2), rearRight: flag(raw.rightRearWindow, 2) },
    hoodOpen: flag(raw.forehold, 1),
    skylightOpen: flag(raw.skylight, 2),
    tirePressureKpa: {
      frontLeft: nonnegative(raw.leftFrontTirepressure), frontRight: nonnegative(raw.rightFrontTirepressure),
      rearLeft: nonnegative(raw.leftRearTirepressure), rearRight: nonnegative(raw.rightRearTirepressure),
    },
    updatedAt: timestamp(raw.updatedAt) || timestamp(raw.updateTime) || timestamp(raw.time),
  };
}

export function normalizeVehicleEnergy(raw: RawVehicle): VehicleEnergy {
  return {
    recentDistanceKm: finite(raw.recentDistanceKm) ?? finite(raw.recent50kmMileage) ?? (raw.recentlyFiftyAverageEle !== undefined || raw.recentlyFiftyAverageFuel !== undefined ? 50 : undefined),
    equivalentFuelLitresPer100Km: finite(raw.equivalentFuelLitresPer100Km) ?? finite(raw.recent50kmEnergy) ?? finite(raw.nearestEnergyConsumption) ?? finite(raw.energyConsumption),
    electricityKwhPer100Km: finite(raw.electricityKwhPer100Km) ?? finite(raw.recent50kmElecAverage) ?? finite(raw.recentlyFiftyAverageEle),
    fuelLitresPer100Km: finite(raw.fuelLitresPer100Km) ?? finite(raw.recent50kmOilAverage) ?? finite(raw.recentlyFiftyAverageFuel),
    electricityKwh: nonnegative(raw.totalPower),
    fuelLitres: nonnegative(raw.totalOil),
    totalDistanceKm: finite(raw.totalDistanceKm) ?? finite(raw.totalMileage),
    cumulativeEquivalentFuelLitresPer100Km: finite(raw.cumulativeEquivalentFuelLitresPer100Km) ?? finite(raw.totalEnergy) ?? finite(raw.totalConsumptionEn),
    cumulativeElectricityKwhPer100Km: finite(raw.cumulativeElectricityKwhPer100Km) ?? finite(raw.totalElecAverage) ?? finite(raw.totalAverageEle),
    cumulativeFuelLitresPer100Km: finite(raw.cumulativeFuelLitresPer100Km) ?? finite(raw.totalOilAverage) ?? finite(raw.totalAverageFuel),
    recentTrend: [],
    updatedAt: timestamp(raw.updatedAt) || timestamp(raw.updateTime) || timestamp(raw.time),
  };
}
