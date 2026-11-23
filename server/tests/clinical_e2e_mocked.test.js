const test = require('node:test');
const assert = require('node:assert/strict');
const { getDb, initSchema } = require('../src/db');
const { discoverAndIngestDrug } = require('../src/ingestion/live_feeds');
const { auditDrugRecord, auditDatabase } = require('../src/auditor/clinicalInvariants');

function jsonResponse(payload, ok = true) {
  return {
    ok,
    status: ok ? 200 : 404,
    async json() {
      return payload;
    },
  };
}

/**
 * Realistic FDA/RxNorm/CMS mock router reproducing the exact Flomax vs. Jalyn
 * and Tamsulosin collision scenario deterministically offline.
 */
function createMockFetch() {
  return async (rawUrl) => {
    const url = decodeURIComponent(String(rawUrl));

    // 1. RxNav /drugs.json
    if (url.includes('rxnav.nlm.nih.gov/REST/drugs.json')) {
      if (url.includes('name=Flomax')) {
        return jsonResponse({
          drugGroup: {
            conceptGroup: [
              { tty: 'SBD', conceptProperties: [{ rxcui: '863671', name: 'tamsulosin hydrochloride 0.4 MG Oral Capsule [Flomax]' }] },
            ],
          },
        });
      }
      if (url.includes('name=Jalyn')) {
        return jsonResponse({
          drugGroup: {
            conceptGroup: [
              { tty: 'SBD', conceptProperties: [{ rxcui: '996101', name: 'dutasteride 0.5 MG / tamsulosin hydrochloride 0.4 MG Oral Capsule [Jalyn]' }] },
            ],
          },
        });
      }
      if (url.toLowerCase().includes('tamsulosin')) {
        return jsonResponse({
          drugGroup: {
            conceptGroup: [
              {
                tty: 'SBD',
                conceptProperties: [
                  { rxcui: '996101', name: 'dutasteride 0.5 MG / tamsulosin hydrochloride 0.4 MG Oral Capsule [Jalyn]' },
                  { rxcui: '863671', name: 'tamsulosin hydrochloride 0.4 MG Oral Capsule [Flomax]' },
                ],
              },
              {
                tty: 'SCD',
                conceptProperties: [
                  { rxcui: '996100', name: 'dutasteride 0.5 MG / tamsulosin hydrochloride 0.4 MG Oral Capsule' },
                  { rxcui: '863669', name: 'tamsulosin hydrochloride 0.4 MG Oral Capsule' },
                ],
              },
            ],
          },
        });
      }
    }

    // 2. RxNav /related.json?tty=IN
    if (url.includes('/rxcui/863671/related.json') || url.includes('/rxcui/863669/related.json')) {
      return jsonResponse({
        relatedGroup: {
          conceptGroup: [{ tty: 'IN', conceptProperties: [{ rxcui: '77492', name: 'tamsulosin' }] }],
        },
      });
    }
    if (url.includes('/rxcui/996101/related.json') || url.includes('/rxcui/996100/related.json')) {
      return jsonResponse({
        relatedGroup: {
          conceptGroup: [
            {
              tty: 'IN',
              conceptProperties: [
                { rxcui: '228790', name: 'dutasteride' },
                { rxcui: '77492', name: 'tamsulosin' },
              ],
            },
          ],
        },
      });
    }

    // 3. OpenFDA NDC Directory
    if (url.includes('api.fda.gov/drug/ndc.json')) {
      // Discontinued Flomax returns 0 direct hits, triggering Fallback 2 -> generic_name:"tamsulosin"
      if (url.includes('brand_name:"Flomax"') || url.includes('brand_name:Flomax')) {
        return jsonResponse({ results: [] }, false);
      }
      if (url.includes('brand_name:"Jalyn"')) {
        return jsonResponse({
          results: [
            {
              product_ndc: '0173-0809',
              brand_name: 'Jalyn',
              generic_name: 'dutasteride and tamsulosin hydrochloride',
              product_type: 'HUMAN PRESCRIPTION DRUG',
              marketing_category: 'NDA',
              dosage_form: 'CAPSULE',
              labeler_name: 'GlaxoSmithKline',
              marketing_start_date: '20100614',
              active_ingredients: [
                { name: 'DUTASTERIDE', strength: '.5 mg/1' },
                { name: 'TAMSULOSIN HYDROCHLORIDE', strength: '.4 mg/1' },
              ],
            },
          ],
        });
      }
      // Generic search for "tamsulosin" returns BOTH Jalyn (NDA, 2 ingredients) AND Tamsulosin (ANDA, 1 ingredient)!
      if (url.toLowerCase().includes('tamsulosin')) {
        return jsonResponse({
          results: [
            {
              product_ndc: '0173-0809',
              brand_name: 'Jalyn',
              generic_name: 'dutasteride and tamsulosin hydrochloride',
              product_type: 'HUMAN PRESCRIPTION DRUG',
              marketing_category: 'NDA',
              dosage_form: 'CAPSULE',
              labeler_name: 'GlaxoSmithKline',
              marketing_start_date: '20100614',
              active_ingredients: [
                { name: 'DUTASTERIDE', strength: '.5 mg/1' },
                { name: 'TAMSULOSIN HYDROCHLORIDE', strength: '.4 mg/1' },
              ],
            },
            {
              product_ndc: '65862-0525',
              brand_name: 'Tamsulosin Hydrochloride',
              generic_name: 'tamsulosin hydrochloride',
              product_type: 'HUMAN PRESCRIPTION DRUG',
              marketing_category: 'ANDA',
              dosage_form: 'CAPSULE',
              labeler_name: 'Aurobindo Pharma',
              marketing_start_date: '20100302',
              active_ingredients: [{ name: 'TAMSULOSIN HYDROCHLORIDE', strength: '.4 mg/1' }],
            },
          ],
        });
      }
    }

    // 4. OpenFDA Drugs@FDA
    if (url.includes('api.fda.gov/drug/drugsfda.json')) {
      if (url.includes('"Flomax"')) {
        return jsonResponse({
          results: [
            {
              application_number: 'NDA020579',
              sponsor_name: 'SANOFISYNTHELABO',
              products: [
                {
                  brand_name: 'FLOMAX',
                  dosage_form: 'CAPSULE',
                  te_code: 'AB',
                  marketing_status: 'Discontinued',
                  active_ingredients: [{ name: 'TAMSULOSIN HYDROCHLORIDE', strength: '0.4MG' }],
                },
              ],
            },
          ],
        });
      }
      if (url.includes('"Jalyn"')) {
        return jsonResponse({
          results: [
            {
              application_number: 'NDA022460',
              sponsor_name: 'GLAXOSMITHKLINE',
              products: [
                {
                  brand_name: 'JALYN',
                  dosage_form: 'CAPSULE',
                  te_code: 'AB',
                  marketing_status: 'Prescription',
                  active_ingredients: [
                    { name: 'DUTASTERIDE', strength: '0.5MG' },
                    { name: 'TAMSULOSIN HYDROCHLORIDE', strength: '0.4MG' },
                  ],
                },
              ],
            },
          ],
        });
      }
      if (url.toLowerCase().includes('tamsulosin')) {
        return jsonResponse({
          results: [
            {
              application_number: 'ANDA078691',
              sponsor_name: 'AUROBINDO',
              submissions: [{ submission_type: 'ORIG', submission_status: 'AP', submission_status_date: '20100302' }],
              products: [
                {
                  brand_name: 'TAMSULOSIN HYDROCHLORIDE',
                  dosage_form: 'CAPSULE',
                  te_code: 'AB',
                  marketing_status: 'Prescription',
                  active_ingredients: [{ name: 'TAMSULOSIN HYDROCHLORIDE', strength: '0.4MG' }],
                },
              ],
            },
            {
              application_number: 'ANDA203123',
              sponsor_name: 'TEVA',
              submissions: [{ submission_type: 'ORIG', submission_status: 'AP', submission_status_date: '20151120' }],
              products: [
                {
                  brand_name: 'DUTASTERIDE AND TAMSULOSIN HYDROCHLORIDE',
                  dosage_form: 'CAPSULE',
                  te_code: 'AB',
                  marketing_status: 'Prescription',
                  active_ingredients: [
                    { name: 'DUTASTERIDE', strength: '0.5MG' },
                    { name: 'TAMSULOSIN HYDROCHLORIDE', strength: '0.4MG' },
                  ],
                },
              ],
            },
          ],
        });
      }
    }

    // 5. CMS NADAC Metastore & Query
    if (url.includes('data.medicaid.gov/api/1/metastore')) {
      return jsonResponse([
        { identifier: 'mock-nadac-2026', title: 'NADAC (National Average Drug Acquisition Cost) 2026' },
      ]);
    }
    if (url.includes('data.medicaid.gov/api/1/datastore/query/mock-nadac-2026')) {
      return jsonResponse({
        results: [
          {
            ndc: '65862052599',
            ndc_description: 'TAMSULOSIN HCL 0.4 MG CAPSULE',
            nadac_per_unit: '0.0612',
            classification_for_rate_setting: 'G',
            effective_date: '2026-10-01',
            pricing_unit: 'EA',
          },
          {
            ndc: '00093778156',
            ndc_description: 'DUTASTERIDE-TAMSULOSIN 0.5-0.4',
            nadac_per_unit: '3.4500',
            classification_for_rate_setting: 'G',
            effective_date: '2026-10-01',
            pricing_unit: 'EA',
          },
        ],
      });
    }

    // 6. DailyMed SPL
    if (url.includes('dailymed.nlm.nih.gov')) {
      return jsonResponse({ data: [] });
    }

    return jsonResponse({}, false);
  };
}

test('E2E Mocked: Flomax, Jalyn, and Tamsulosin resolve cleanly without cross-contamination', async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = createMockFetch();
  try {
    const db = getDb(':memory:');
    initSchema(db);

    const flomax = await discoverAndIngestDrug(db, 'Flomax');
    assert.ok(flomax);
    assert.equal(flomax.rxcui, '863671');
    assert.equal(flomax.brand_name, 'Flomax');
    assert.equal(flomax.generic_name, 'tamsulosin hydrochloride');
    assert.equal(flomax.active_ingredient, 'tamsulosin');
    assert.equal(flomax.strength, '0.4 mg');

    // Ingesting Jalyn right after Flomax must create a separate row and NEVER overwrite Flomax
    const jalyn = await discoverAndIngestDrug(db, 'Jalyn');
    assert.ok(jalyn);
    assert.equal(jalyn.rxcui, '996101');
    assert.equal(jalyn.brand_name, 'Jalyn');
    assert.equal(jalyn.generic_name, 'dutasteride and tamsulosin hydrochloride');
    assert.equal(jalyn.active_ingredient, 'dutasteride / tamsulosin');
    assert.equal(jalyn.strength, '0.5 mg / 0.4 mg');

    // Unbranded generic search for "Tamsulosin" must NOT be hijacked by Jalyn
    const tamsulosin = await discoverAndIngestDrug(db, 'Tamsulosin');
    assert.ok(tamsulosin);
    assert.equal(tamsulosin.rxcui, '863669');
    assert.equal(tamsulosin.brand_name, null);
    assert.equal(tamsulosin.generic_name, 'tamsulosin hydrochloride');
    assert.equal(tamsulosin.strength, '0.4 mg');

    // Verify all 3 rows coexist cleanly and pass every universal clinical invariant
    const report = auditDatabase(db);
    assert.equal(report.totalDrugs, 3);
    assert.equal(report.errorCount, 0, `Unexpected audit errors: ${JSON.stringify(report.findings)}`);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('E2E Mocked: forceRefresh self-heals a previously corrupted Flomax row', async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = createMockFetch();
  try {
    const db = getDb(':memory:');
    initSchema(db);

    // Seed a corrupted production-like Flomax row (what the pharmacist reported!)
    db.prepare(`
      INSERT INTO drugs (rxcui, brand_name, generic_name, active_ingredient, dosage_form, strength, drug_type)
      VALUES ('863671', 'Flomax', 'dutasteride and tamsulosin hydrochloride', 'tamsulosin', 'capsule', '0.4 mg, 0.5 mg / 0.4 mg', 'small_molecule')
    `).run();

    // Auditor MUST catch the corrupted row before refresh
    const beforeAudit = auditDatabase(db);
    assert.ok(beforeAudit.errorCount >= 2, 'Auditor should flag both ingredient-count mismatch and combo strength');

    // Rolling audit runs forceRefresh: true -> must self-heal the row cleanly!
    const healed = await discoverAndIngestDrug(db, 'Flomax', { forceRefresh: true });
    assert.equal(healed.rxcui, '863671');
    assert.equal(healed.brand_name, 'Flomax');
    assert.equal(healed.generic_name, 'tamsulosin hydrochloride');
    assert.equal(healed.strength, '0.4 mg');

    const afterAudit = auditDatabase(db);
    assert.equal(afterAudit.errorCount, 0, `Healed DB should have 0 errors: ${JSON.stringify(afterAudit.findings)}`);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('Clinical Invariants Auditor: flags ingredient mismatch, combo strengths, brand===generic, and NADAC inversion', () => {
  const badFlomax = auditDrugRecord({
    brand_name: 'Flomax',
    generic_name: 'dutasteride and tamsulosin hydrochloride',
    active_ingredient: 'tamsulosin',
    strength: '0.4 mg, 0.5 mg / 0.4 mg',
  });
  assert.equal(badFlomax.errors.length, 2);

  const badPlaceholder = auditDrugRecord({
    brand_name: 'mydayis',
    generic_name: 'mydayis',
    active_ingredient: 'mydayis',
    strength: '12.5 mg',
  });
  assert.equal(badPlaceholder.errors.length, 1);

  const badNadac = auditDrugRecord(
    {
      brand_name: 'TestDrug',
      generic_name: 'tamsulosin hydrochloride',
      active_ingredient: 'tamsulosin',
      strength: '0.4 mg',
    },
    {
      marketRows: [
        { source: 'cms_nadac', marketing_category: 'NDA', nadac_per_unit: 1.0 },
        { source: 'cms_nadac', marketing_category: 'ANDA', nadac_per_unit: 3.5 },
      ],
    }
  );
  assert.equal(badNadac.errors.length, 0);
  assert.equal(badNadac.warnings.length, 1);
});
