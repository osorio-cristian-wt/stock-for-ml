import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { pgrestQuote, variationRows } from "../_shared/items.ts";
import { MeliVariation } from "../_shared/meli.ts";

Deno.test("pgrestQuote wraps and escapes PostgREST-hostile characters", () => {
  assertEquals(pgrestQuote("TPSLI20281"), '"TPSLI20281"');
  // A comma or parenthesis inside a SKU must not break or=(...)/in.(...).
  assertEquals(pgrestQuote("SKU,1(2)"), '"SKU,1(2)"');
  assertEquals(pgrestQuote('A"B'), '"A\\"B"');
  assertEquals(pgrestQuote("A\\B"), '"A\\\\B"');
});

Deno.test("variationRows maps ML variations to listing_variations rows", () => {
  const variations: MeliVariation[] = [
    {
      id: 181234567,
      price: 15999,
      available_quantity: 4,
      attribute_combinations: [
        { id: "COLOR", name: "Color", value_name: "Rojo" },
        { id: "SIZE", name: "Talle", value_name: "XL" },
      ],
    },
    { id: 181234568 }, // ML can omit price/qty/attributes
  ];

  const rows = variationRows("prof-1", "list-1", variations);
  assertEquals(rows.length, 2);
  assertEquals(rows[0], {
    profile_id: "prof-1",
    ml_listing_id: "list-1",
    ml_variation_id: "181234567",
    attributes: variations[0].attribute_combinations,
    price: 15999,
    available_quantity: 4,
  });
  assertEquals(rows[1].ml_variation_id, "181234568");
  assertEquals(rows[1].price, null);
  assertEquals(rows[1].available_quantity, 0);
  assertEquals(rows[1].attributes, []);
});

Deno.test("variationRows returns empty for items without variations", () => {
  assertEquals(variationRows("prof-1", "list-1", undefined), []);
  assertEquals(variationRows("prof-1", "list-1", []), []);
});
