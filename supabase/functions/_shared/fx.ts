// Pure FX helpers (parsing dolarapi responses). Kept separate from the
// fx-rates function so they can be unit tested without starting a server.

export interface DolarApiResponse {
  compra?: number;
  venta?: number;
  casa?: string;
  nombre?: string;
}

/** Maps a dolarapi "casa" to our fx_kind enum value. */
export function mapCasaToKind(casa?: string): string {
  switch ((casa ?? "").toLowerCase()) {
    case "oficial": return "oficial";
    case "blue": return "blue";
    case "bolsa":
    case "mep": return "mep";
    case "tarjeta": return "tarjeta";
    case "cripto": return "cripto";
    case "mayorista": return "mayorista";
    default: return "blue";
  }
}

/** Reference rate to store: sell price (cost to buy USD), falling back to buy. */
export function pickRate(r: DolarApiResponse): number {
  return r.venta ?? r.compra ?? 0;
}
