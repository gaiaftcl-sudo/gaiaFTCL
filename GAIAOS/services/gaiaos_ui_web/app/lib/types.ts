export type ReflectionReport = {
  database?: string;
  arango_url?: string;
  collection_counts?: { collection: string; count: number }[];
  recommended_next_worlds?: {
    world: string;
    rationale: string;
    required_real_ingests: string[];
    required_validator_gates: string[];
  }[];
  notes?: string[];
};

export type RecentValidationsResponse = {
  limit: number;
  validations: any[];
};

export type RecentObservationsResponse = {
  limit: number;
  observations: any[];
};

export type RecentTilesResponse = {
  limit: number;
  tiles: any[];
};


