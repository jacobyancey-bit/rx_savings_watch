const test = require('node:test');
const assert = require('node:assert/strict');
const {
  normalizeIngredientName,
  parseExpectedIngredients,
  matchesExpectedIngredients,
  isMultiIngredientRxNormName,
  extractRxNormBrand,
  filterRxNormConcepts,
  matchesNadacIngredientProfile,
} = require('../src/ingestion/live_feeds');

test('Clinical Mapping: normalizes salts to base chemical moiety', () => {
  assert.equal(normalizeIngredientName('TAMSULOSIN HYDROCHLORIDE'), 'tamsulosin');
  assert.equal(normalizeIngredientName('Metformin Hydrochloride'), 'metformin');
  assert.equal(normalizeIngredientName('Losartan Potassium'), 'losartan');
  assert.equal(normalizeIngredientName('Amlodipine Besylate'), 'amlodipine');
  assert.equal(normalizeIngredientName('Dutasteride'), 'dutasteride');
});

test('Clinical Mapping: Flomax (1 ingredient) strictly rejects Jalyn (2 ingredients) and vice versa', () => {
  const flomaxExpected = parseExpectedIngredients(['tamsulosin']);
  const jalynExpected = parseExpectedIngredients(['dutasteride', 'tamsulosin']);

  const tamsulosinOnlyNdc = [{ name: 'TAMSULOSIN HYDROCHLORIDE', strength: '0.4 mg/1' }];
  const jalynComboNdc = [
    { name: 'DUTASTERIDE', strength: '0.5 mg/1' },
    { name: 'TAMSULOSIN HYDROCHLORIDE', strength: '0.4 mg/1' },
  ];

  // Flomax MUST accept tamsulosin-only and REJECT dutasteride + tamsulosin
  assert.equal(matchesExpectedIngredients(tamsulosinOnlyNdc, flomaxExpected), true);
  assert.equal(matchesExpectedIngredients(jalynComboNdc, flomaxExpected), false);

  // Jalyn MUST accept dutasteride + tamsulosin and REJECT tamsulosin-only
  assert.equal(matchesExpectedIngredients(jalynComboNdc, jalynExpected), true);
  assert.equal(matchesExpectedIngredients(tamsulosinOnlyNdc, jalynExpected), false);
});

test('Clinical Mapping: Glucophage/Prinivil/Omeprazole strictly reject combination NDAs', () => {
  // Glucophage (metformin) must reject Janumet (sitagliptin + metformin)
  assert.equal(
    matchesExpectedIngredients(
      [{ name: 'SITAGLIPTIN PHOSPHATE' }, { name: 'METFORMIN HYDROCHLORIDE' }],
      ['metformin']
    ),
    false
  );
  assert.equal(
    matchesExpectedIngredients([{ name: 'METFORMIN HYDROCHLORIDE' }], ['metformin']),
    true
  );

  // Prinivil (lisinopril) must reject lisinopril + hydrochlorothiazide
  assert.equal(
    matchesExpectedIngredients(
      [{ name: 'LISINOPRIL' }, { name: 'HYDROCHLOROTHIAZIDE' }],
      ['lisinopril']
    ),
    false
  );

  // Omeprazole must reject Talicia (omeprazole + amoxicillin + rifabutin)
  assert.equal(
    matchesExpectedIngredients(
      [{ name: 'OMEPRAZOLE' }, { name: 'AMOXICILLIN' }, { name: 'RIFABUTIN' }],
      ['omeprazole']
    ),
    false
  );
});

test('Clinical Mapping: mixed-salt amphetamine formulations (Adderall XR / Mydayis) still match', () => {
  const adderallSalts = [
    { name: 'AMPHETAMINE ASPARTATE' },
    { name: 'AMPHETAMINE SULFATE' },
    { name: 'DEXTROAMPHETAMINE SACCHARATE' },
    { name: 'DEXTROAMPHETAMINE SULFATE' },
  ];
  assert.equal(
    matchesExpectedIngredients(adderallSalts, ['amphetamine', 'dextroamphetamine']),
    true
  );
});

test('Clinical Mapping: RxNorm SBD/SCD concept filtering distinguishes Flomax vs Jalyn', () => {
  const rxConcepts = [
    { rxcui: '996101', name: 'dutasteride 0.5 MG / tamsulosin hydrochloride 0.4 MG Oral Capsule [Jalyn]' },
    { rxcui: '863671', name: 'tamsulosin hydrochloride 0.4 MG Oral Capsule [Flomax]' },
  ];

  assert.equal(isMultiIngredientRxNormName(rxConcepts[0].name), true);
  assert.equal(isMultiIngredientRxNormName(rxConcepts[1].name), false);
  // Concentration slash without spaces is NOT multi-ingredient
  assert.equal(isMultiIngredientRxNormName('adalimumab 40 MG/0.8 ML Prefilled Syringe [Humira]'), false);

  assert.equal(extractRxNormBrand(rxConcepts[0].name), 'jalyn');
  assert.equal(extractRxNormBrand(rxConcepts[1].name), 'flomax');

  const forFlomax = filterRxNormConcepts(rxConcepts, {
    brandName: 'Flomax',
    expectedIngredients: ['tamsulosin'],
  });
  assert.equal(forFlomax.length, 1);
  assert.equal(forFlomax[0].rxcui, '863671');

  const forJalyn = filterRxNormConcepts(rxConcepts, {
    brandName: 'Jalyn',
    expectedIngredients: ['dutasteride', 'tamsulosin'],
  });
  assert.equal(forJalyn.length, 1);
  assert.equal(forJalyn[0].rxcui, '996101');

  const forSingleGeneric = filterRxNormConcepts(rxConcepts, {
    brandName: null,
    expectedIngredients: ['tamsulosin'],
  });
  assert.equal(forSingleGeneric.length, 1);
  assert.equal(forSingleGeneric[0].rxcui, '863671');
});

test('Clinical Mapping: CMS NADAC filtering prevents combo prices on single-ingredient drugs', () => {
  assert.equal(matchesNadacIngredientProfile('TAMSULOSIN HCL 0.4 MG CAPSULE', ['tamsulosin'], false), true);
  assert.equal(matchesNadacIngredientProfile('DUTASTERIDE-TAMSULOSIN 0.5-0.4', ['tamsulosin'], false), false);
  assert.equal(matchesNadacIngredientProfile('LISINOPRIL-HCTZ 20-12.5 MG TAB', ['lisinopril'], false), false);
  assert.equal(matchesNadacIngredientProfile('LISINOPRIL 20 MG TABLET', ['lisinopril'], false), true);
  assert.equal(
    matchesNadacIngredientProfile('DUTASTERIDE-TAMSULOSIN 0.5-0.4', ['dutasteride', 'tamsulosin'], false),
    true
  );
});
