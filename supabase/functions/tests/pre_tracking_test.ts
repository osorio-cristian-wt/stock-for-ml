// Cutoff pre-import: órdenes anteriores al espejado de la publicación no
// tocan stock (su efecto ya venía descontado en el snapshot importado de ML).
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { preTracking } from "../_shared/orders.ts";

const MIRRORED = "2026-07-01T10:00:00Z";

Deno.test("preTracking: order older than the listing mirror is pre-tracking", () => {
  assertEquals(preTracking("2026-06-15T09:00:00Z", MIRRORED), true);
});

Deno.test("preTracking: order after the mirror reconciles normally", () => {
  assertEquals(preTracking("2026-07-02T09:00:00Z", MIRRORED), false);
});

Deno.test("preTracking: same instant counts as tracked (not pre)", () => {
  assertEquals(preTracking(MIRRORED, MIRRORED), false);
});

Deno.test("preTracking: missing dates never zero the effect", () => {
  assertEquals(preTracking(undefined, MIRRORED), false);
  assertEquals(preTracking("2026-06-15T09:00:00Z", null), false);
  assertEquals(preTracking(null, undefined), false);
});

Deno.test("preTracking: unparseable dates fall back to tracked", () => {
  assertEquals(preTracking("garbage", MIRRORED), false);
  assertEquals(preTracking("2026-06-15T09:00:00Z", "garbage"), false);
});
