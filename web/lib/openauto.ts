export type VehiclePowerState = "off" | "on" | "unknown";

export type VehicleSummary = {
  id: string;
  name: string;
  powerState: VehiclePowerState;
  estimatedRangeKm?: number;
  tractionBatteryPercent?: number;
  fuelPercent?: number;
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
