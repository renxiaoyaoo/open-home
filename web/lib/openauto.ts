export type VehiclePowerState = "off" | "on" | "unknown";

export type VehicleSummary = {
  id: string;
  name: string;
  powerState: VehiclePowerState;
  estimatedRangeKm?: number;
  tractionBatteryPercent?: number;
  fuelPercent?: number;
  chargingState?: "charging" | "complete" | "stopped" | "unknown";
  chargingPowerKw?: number;
  remainingChargeMinutes?: number;
  odometerKm?: number;
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
  return Number.isFinite(number) ? number : undefined;
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

export function normalizeVehicleSummary(raw: RawVehicle, fallbackId = "") : VehicleSummary {
  const id = text(raw.id) || text(raw.vehicleId) || text(raw.vin) || fallbackId;
  if (!id) throw new Error("Vehicle identifier is missing");
  const hours = finite(raw.remainingHours);
  const minutes = finite(raw.remainingMinutes);
  const remainingChargeMinutes = hours !== undefined || minutes !== undefined
    ? Math.max(0, Math.round((hours || 0) * 60 + (minutes || 0)))
    : undefined;
  const power = String(raw.powerState ?? raw.vehiclePowerState ?? "").toLowerCase();
  return {
    id,
    name: text(raw.name) || text(raw.vehicleName) || text(raw.modelName) || "车辆",
    powerState: ["1", "on", "running"].includes(power) ? "on" : ["0", "off", "stopped"].includes(power) ? "off" : "unknown",
    estimatedRangeKm: finite(raw.enduranceMileage),
    tractionBatteryPercent: percent(raw.elecPercent),
    fuelPercent: percent(raw.oilPercent),
    chargingState: chargingState(raw.chargingState),
    chargingPowerKw: finite(raw.chargingPower),
    remainingChargeMinutes,
    odometerKm: finite(raw.totalMileage),
    updatedAt: text(raw.updatedAt) || text(raw.updateTime) || text(raw.time),
  };
}

export function normalizeVehicleEnergy(raw: RawVehicle): VehicleEnergy {
  return {
    recentDistanceKm: finite(raw.recentDistanceKm) ?? finite(raw.recent50kmMileage),
    equivalentFuelLitresPer100Km: finite(raw.equivalentFuelLitresPer100Km) ?? finite(raw.recent50kmEnergy),
    electricityKwhPer100Km: finite(raw.electricityKwhPer100Km) ?? finite(raw.recent50kmElecAverage),
    fuelLitresPer100Km: finite(raw.fuelLitresPer100Km) ?? finite(raw.recent50kmOilAverage),
    totalDistanceKm: finite(raw.totalDistanceKm) ?? finite(raw.totalMileage),
    cumulativeEquivalentFuelLitresPer100Km: finite(raw.cumulativeEquivalentFuelLitresPer100Km) ?? finite(raw.totalEnergy),
    cumulativeElectricityKwhPer100Km: finite(raw.cumulativeElectricityKwhPer100Km) ?? finite(raw.totalElecAverage),
    cumulativeFuelLitresPer100Km: finite(raw.cumulativeFuelLitresPer100Km) ?? finite(raw.totalOilAverage),
    recentTrend: [],
    updatedAt: text(raw.updatedAt) || text(raw.updateTime) || text(raw.time),
  };
}
