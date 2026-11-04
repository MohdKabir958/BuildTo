-- Production-safe catalog REFERENCE DATA only. Does not create users, suppliers, listings, stock or approvals.
-- Re-running this file never overwrites operator-edited categories or units.
BEGIN;
INSERT INTO "UnitOfMeasure" ("code", "name", "dimension", "scale", "active") VALUES
 ('BAG',    'Bag',          'COUNT', 0, true),
 ('PIECE',  'Piece',        'COUNT', 0, true),
 ('ROD',    'Rod',          'COUNT', 0, true),
 ('BUNDLE', 'Bundle',       'COUNT', 0, true),
 ('PACK',   'Pack',         'COUNT', 0, true),
 ('CAN',    'Can',          'COUNT', 0, true),
 ('SET',    'Set',          'COUNT', 0, true),
 ('BUCKET', 'Bucket',       'COUNT', 0, true),
 ('COIL',   'Coil',         'COUNT', 0, true),
 ('ROLL',   'Roll',         'COUNT', 0, true),
 ('KG',     'Kilogram',     'MASS',  3, true),
 ('TONNE',  'Metric tonne', 'MASS',  3, true),
 ('CFT',    'Cubic foot',   'VOLUME',3, true),
 ('CUM',    'Cubic metre',  'VOLUME',3, true),
 ('BRASS',  'Brass (local volumetric unit)', 'VOLUME', 3, true),
 ('SQM',    'Square metre', 'AREA',  3, true),
 ('SQFT',   'Square foot',  'AREA',  3, true),
 ('METRE',  'Metre',        'LENGTH',3, true)
ON CONFLICT ("code") DO NOTHING;

INSERT INTO "Category" ("id", "slug", "name", "displayOrder", "active") VALUES
 ('10000000-0000-4000-8000-000000000001', 'cement-concrete','Cement & Concrete',1,true),
 ('10000000-0000-4000-8000-000000000002', 'steel-tmt-bars','Steel & TMT Bars',2,true),
 ('10000000-0000-4000-8000-000000000003', 'bricks-blocks','Bricks & Blocks',3,true),
 ('10000000-0000-4000-8000-000000000004', 'sand-aggregates','Sand & Aggregates',4,true),
 ('10000000-0000-4000-8000-000000000005', 'plumbing-pipes','Plumbing & Pipes',5,true),
 ('10000000-0000-4000-8000-000000000006', 'electrical-wiring','Electrical & Wiring',6,true),
 ('10000000-0000-4000-8000-000000000007', 'paints-finishes','Paints & Finishes',7,true),
 ('10000000-0000-4000-8000-000000000008', 'tools-hardware','Tools & Hardware',8,true),
 ('10000000-0000-4000-8000-000000000009', 'waterproofing','Waterproofing',9,true)
ON CONFLICT ("slug") DO NOTHING;
COMMIT;
